use CITestSetListener;
unit class OBS does CITestSetListener;

use DB;
use SourceArchiveCreator;
use OBSInterface;
use SerialDedup;
use Red::Operators:api<2>;
use Log::Async;
use Config;
use CITestSetManager;

has SourceArchiveCreator $.source-archive-creator is required;
has IO::Path $!work-dir is built is required where *.d;
has OBSInterface $!interface is built is required;
has CITestSetManager $!testset-manager is built is required;

has $.hook-suffix = "obs-hook";

my %projects =
    rakudo => {
        package => "rakudo-moarvm",
    },
    nqp => {
        package => "nqp-moarvm",
    },
    moar => {
        package => "moarvm",
    },
;

method new-test-set(DB::CITestSet:D $test-set) {
    DB::CIPlatformTestSet.^create:
        :$test-set,
        platform => DB::OBS;

    self.process-worklist();
}

method re-test-test-set(DB::CITestSet:D $test-set) {
    my $pts = DB::CIPlatformTestSet.^all.first({
        $_.platform == DB::OBS &&
        $_.test-set.id == $test-set.id
    });
    if $pts {
        $pts.status = DB::PLATFORM_NOT_STARTED;
        $pts.obs-started-at = Nil;
        $pts.obs-finished-at = Nil;
        $pts.re-test = True;
        $pts.^save;
        self.process-worklist();
    }
}

method process-worklist() is serial-dedup {
    trace "OBS: Processing worklist";
    my @running-ptses = DB::CIPlatformTestSet.^all.grep({
        $_.platform == DB::OBS &&
        $_.status == DB::PLATFORM_IN_PROGRESS });

    my DB::CIPlatformTestSet $running-pts;

    if @running-ptses.elems > 1 {
        error "More than one running OBS TestSet found.";
        return;
    }
    elsif @running-ptses.elems == 0 {
        # No in progress test set found. Let's see if we can start a new one.
        with DB::CIPlatformTestSet.^all.first({
                $_.platform == DB::OBS &&
                $_.status == DB::PLATFORM_NOT_STARTED }) {
            $running-pts = $_;
            trace "OBS: Starting new run: " ~ $running-pts.id;

            $running-pts.status = DB::PLATFORM_IN_PROGRESS;

            if $running-pts.re-test {
                # It's a re-test. So only run tests that have failed.
                # I.e. disable all succeeded tests.

                for DB::CITest.^all.grep({
                        $_.platform-test-set.id == $running-pts.id
                }) -> $test {
                    if $test.status == DB::SUCCESS {
                        for %projects.keys -> $project {
                            my $package = %projects{$project}<package>;
                            $!interface.set-test-disabled($package, $test.obs-arch, $test.obs-repository);
                        }
                    }
                    else {
                        $test.superseded = True;
                        $test.^save;
                    }
                }
            }
            else {
                # Reset all DISABLED flags.
                for %projects.keys -> $project {
                    my $package = %projects{$project}<package>;
                    $!interface.enable-all-tests($package);
                }
            }

            my $source-id = $running-pts.test-set.source-archive-id;
            for %projects.keys -> $project {
                my $package = %projects{$project}<package>;
                my @sources = $!interface.sources($package);
                $!interface.delete-file($package, $_.name) with @sources.first({ $_.name ~~ / ^ 'PTS-ID-' / });
                $!interface.delete-file($package, $_.name) with @sources.first({ $_.name ~~ / '-' $project '.tar.xz' $ / });

                my $archive-path = $!source-archive-creator.get-archive-path($source-id, $project);
                $!interface.upload-file($package, "PTS-ID-" ~ $running-pts.id, :blob(""));
                $!interface.upload-file($package, $source-id ~ "-" ~ $project ~ ".tar.xz", :path($archive-path));
                my $spec = %?RESOURCES{$package ~ ".spec"}.slurp;
                $spec ~~ s{ '<moar_rev>' }     = $source-id;
                $spec ~~ s{ '<nqp_rev>' }      = $source-id;
                $spec ~~ s{ '<rakudo_rev>' }   = $source-id;
                $spec ~~ s{ '<rcb_hook_url>' } = config.hook-url ~ $!hook-suffix ~ "?pts-id=" ~ $running-pts.id;
                $!interface.upload-file($package, $package ~ ".spec", :blob($spec));
                my $dom = $!interface.commit($package);
            }

            $running-pts.obs-started-at = DateTime.now;
            $running-pts.^save;
        }
    }
    # @running-ptses.elems == 1
    elsif DateTime.now - @running-ptses[0].obs-last-check-time >= config.obs-check-duration ||
            DateTime.now - @running-ptses[0].obs-started-at >= config.obs-min-run-duration &&
            DateTime.now - @running-ptses[0].obs-last-check-time >= config.obs-build-end-poll-interval
    {
        # Still have a test set we are working on and it's time to have a look at it again.
        $running-pts = @running-ptses[0];

        trace "OBS: Looking at test set again: " ~ $running-pts.id;

        # Let's retrieve the ID of that test run and validate our database and OBS agree.
        my @sources = $!interface.sources(%projects<rakudo><package>);
        unless my $id-source = @sources.first({ $_.name ~~ / ^ 'PTS-ID-' / }) {
            error "No id found in OBS build files.";
            return;
        }

        my $obs-pts-id = +$id-source.name.substr('PTS-ID-'.chars);
        if $obs-pts-id != $running-pts.id {
            error "OBS and our database have run out of sync.";
            return;
        }
    }

    if $running-pts {
        # There is a running pts we should check for.
        my @known-tests = DB::CITest.^all.grep({
            $_.platform-test-set.id == $running-pts.id &&
            !$_.superseded
        });

        for $!interface.builds() -> $build {
            if $build.status.values.grep(* eq "disabled") {
                # It's a disabled test. Usually a re-test run and the test hadn't failed and is thus not tested again.
                next;
            }

            my $test-name = $build.arch ~ "-" ~ $build.repository;

            my $status = $build.state eq "building"                         ?? DB::IN_PROGRESS !!
                         $build.status.values.grep( * eq "failed")          ?? DB::FAILURE !!
                         $build.status.values.grep( * eq "building")        ?? DB::IN_PROGRESS !!
                         ([&&] $build.status.values.map( * eq "succeeded")) ?? DB::SUCCESS !!
                                                                               DB::UNKNOWN;

            my $test-is-new = False;
            my $test =
                do with @known-tests.first(*.name eq $test-name) {
                    $_
                }
                else {
                    $test-is-new = True;
                    DB::CITest.new:
                        name              => $test-name,
                        obs-arch          => $build.arch,
                        obs-repository    => $build.repository,
                        :$status,
                        platform-test-set => $running-pts,
                        test-started-at   => DateTime.now,
                        ciplatform        => DB::OBS;
                }

            next if $test.test-finished-at;
            next if !$test-is-new && $test.status == $status;

            $test.status = $status;

            if $status ⊂ (DB::SUCCESS, DB::FAILURE, DB::ABORTED) {
                trace "OBS: Test finished: " ~ ($test.id || "new test");
                $test.test-finished-at //= DateTime.now;
                $test.log //= do {
                    my $log;
                    for config.obs-packages.map({ $_, $!interface.build-log($_, $build.arch, $build.repository) }).flat -> $package, $pack-log {
                        $log ~= qq:to/EOF/;
                        ================================================================================
                                                          $package
                        ================================================================================
                        { $pack-log // "No log found" }

                        EOF
                    }
                    $log .= trim-trailing;
                    $log;
                };
            }

            $test.^save;

            if $test-is-new && $running-pts.re-test {
                with DB::CITest.^all.first({
                        $_.platform-test-set.id == $running-pts.id &&
                        $_.name eq $test-name &&
                        $_.superseded &&
                        !$_.successor.defined
                }) {
                    $_.successor = $test;
                }
            }

            if $test-is-new {
                $!testset-manager.add-tests($test);
            }
            else {
                $!testset-manager.test-status-updated($test);
            }
        }

        $running-pts.obs-last-check-time = DateTime.now;

        if DB::CITest.^all.grep({
                $_.platform-test-set.id == $running-pts.id &&
                $_.status ⊂ (DB::NOT_STARTED, DB::IN_PROGRESS)
                }) == 0
                && DateTime.now - $running-pts.obs-started-at >= config.obs-min-run-duration {
            trace "OBS: TestSet finished: " ~ $running-pts.id;
            $running-pts.status = DB::PLATFORM_DONE;
            $running-pts.obs-finished-at = DateTime.now;
            $running-pts.^save;
            $!testset-manager.platform-test-set-done($running-pts);
            # We are done. Makes sense to have a look whether there already is a new test set to test.
            self.process-worklist();
        }
        else {
            $running-pts.^save;
        }
    }

    CATCH {
        default {
            error "Failed processing OBS worklist: " ~ .message ~ .backtrace.Str
        }
    }
}
