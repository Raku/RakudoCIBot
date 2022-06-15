use CITestSetListener;
unit class OBS does CITestSetListener;

use Log::Async;

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

method new-test-set(DB::CITestSet $test-set) {
    DB::CIPlatformTestSet.^create:
        :$test-set,
        platform => DB::OBS;

    self.process-worklist();
}

method process-worklist() is serial-dedup {
    trace "OBS: Processing worklist";
    my @running-ptses = DB::CIPlatformTestSet.^all.grep({
        $_.platform == DB::OBS &&
        $_.status == DB::PLATFORM_IN_PROGRESS &&
        $_.obs-started-at.defined &&
        !$_.obs-finished-at.defined });

    my DB::CIPlatformTestSet $running-pts;

    if @running-ptses.elems > 1 {
        error "More than one running OBS TestSet found.";
        return;
    }
    elsif @running-ptses.elems == 0 {
        # No in progress test set found. Let's see if we can start a new one.
        with DB::CIPlatformTestSet.^all.first({
                $_.platform == DB::OBS &&
                $_.status == DB::PLATFORM_IN_PROGRESS &&
                !$_.obs-started-at.defined }) {
            $running-pts = $_;
            trace "OBS: Starting new run: " ~ $running-pts.id;

            my $source-id = $running-pts.test-set.source-archive-id;
            for "moar", "moarvm",
                    "nqp", "nqp-moarvm",
                    "rakudo", "rakudo-moarvm" -> $project, $obs-project {
                my @sources = $!interface.sources($obs-project);
                $!interface.delete-file($obs-project, $_.name) with @sources.first({ $_.name ~~ / ^ 'PTS-ID-' / });
                $!interface.delete-file($obs-project, $_.name) with @sources.first({ $_.name ~~ / '-' $project '.tar.xz' $ / });

                my $archive-path = $!source-archive-creator.get-archive-path($source-id, $project);
                $!interface.upload-file($obs-project, "PTS-ID-" ~ $running-pts.id, :blob(""));
                $!interface.upload-file($obs-project, $source-id ~ "-" ~ $project ~ ".tar.xz", :path($archive-path));
                my $spec = %?RESOURCES{$obs-project ~ ".spec"}.slurp;
                $spec ~~ s{ '<moar_rev>' }   = $source-id;
                $spec ~~ s{ '<nqp_rev>' }    = $source-id;
                $spec ~~ s{ '<rakudo_rev>' } = $source-id;
                $!interface.upload-file($obs-project, $obs-project ~ ".spec", :blob($spec));
                my $dom = $!interface.commit($obs-project);
            }

            $running-pts.obs-started-at = DateTime.now;
            $running-pts.^save;
        }
    }
    # @running-ptses.elems == 1
    elsif DateTime.now - @running-ptses[0].obs-last-check-time >= config.obs-check-duration {
        # Still have a test set we are working on and it's time to have a look at it again.
        $running-pts = @running-ptses[0];

        trace "OBS: Looking at test set again: " ~ $running-pts.id;

        # Let's retrieve the ID of that test run and validate our database and OBS agree.
        # TODO: Hardcoding the project here is OK?
        my @sources = $!interface.sources("rakudo-moarvm");
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
        # There is a running test we should check for.
        my @known-tests = DB::CITest.^all.grep({
            $_.platform-test-set.id == $running-pts.id
        });

        for $!interface.builds() -> $build {
            my $test-name = $build.arch ~ "-" ~ $build.repository;

            my $status = $build.state eq "building"                       ?? DB::IN_PROGRESS !!
                         $build.status.values.grep( * eq "failed")        ?? DB::FAILURE !!
                         $build.status.values.grep( * eq "building")      ?? DB::IN_PROGRESS !!
                         [&&] $build.status.values.map( * eq "succeeded") ?? DB::SUCCESS !!
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
                        $pack-log

                        EOF
                    }
                    $log .= trim-trailing;
                    $log;
                };
            }

            $test.^save;

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
                && DateTime.now - $running-pts.obs-started-at > config.obs-min-run-duration {
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
