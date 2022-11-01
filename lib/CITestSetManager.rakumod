unit class CITestSetManager;

use Log::Async;

use SerialDedup;
use DB;
use SourceArchiveCreator;
use Config;
use Red::Operators:api<2>;

has SetHash $!status-listeners .= new;
has SetHash $!test-set-listeners .= new;
has $!source-archive-creator is built is required;
has $!flapper-detector is built is required;

method register-status-listener($status-listener) {
    $!status-listeners.set: $status-listener;
}

method register-test-set-listener($test-set-listener) {
    $!test-set-listeners.set: $test-set-listener;
}

method process-worklist() is serial-dedup {
    trace "CITestSetManager: Processing worklist";
    for DB::Command.^all.grep(*.status == DB::COMMAND_NEW) -> $command {
        given $command.command {
            when DB::RE_TEST {
                if $command.pr {
                    my $ts = DB::CITestSet.^all.sort(-*.id).first( *.pr.number == $command.pr.number );
                    unless $ts {
                        error "No TestSet for the PR of the given command found: " ~ $command.id;
                        $command.status = DB::COMMAND_DONE;
                        $command.^save;
                        next;
                    }

                    $command.test-set = $ts;
                    $command.^save;

                    debug "CITestSetManager: Starting re-test for command: " ~ $command.id;

                    for $!test-set-listeners.keys {
                        $_.re-test-test-set($ts)
                    }

                    $ts.status = DB::WAITING_FOR_TEST_RESULTS;
                    $ts.^save;

                    $command.status = DB::COMMAND_DONE;
                    $command.^save;

                    $_.command-accepted($command) for $!status-listeners.keys;
                }
            }
        }
    }

    for DB::CITestSet.^all.grep(
      *.status ⊂ (DB::UNPROCESSED, DB::SOURCE_ARCHIVE_CREATED, DB::WAITING_FOR_TEST_RESULTS))
      -> $test-set {
        given $test-set.status {
            when DB::UNPROCESSED {
                debug "CITestSetManager: processing unprocessed " ~ $test-set.id;
                my $id = $!source-archive-creator.create-archive($test-set.source-spec);
                $test-set.source-archive-id = $id;
                $test-set.status = DB::SOURCE_ARCHIVE_CREATED;
                $test-set.^save;
                proceed;

                CATCH {
                    when X::ArchiveCreationException {
                        warn "ArchiveCreationException: " ~ $_.message;

                        if ++$test-set.source-retrieval-retries > config.github-max-source-retrieval-retries {
                            $test-set.status = DB::ERROR;
                            warn "Now giving up retrieving the source archive: " ~ $test-set.id;
                        }
                        $test-set.^save;
                    }
                }
            }
            when DB::SOURCE_ARCHIVE_CREATED {
                debug "CITestSetManager: processing source_archive_created " ~ $test-set.id;
                for $!test-set-listeners.keys {
                    $_.new-test-set($test-set)
                }
                $test-set.status = DB::WAITING_FOR_TEST_RESULTS;
                $test-set.^save;
            }
            when DB::WAITING_FOR_TEST_RESULTS {
                self!check-test-set-done($test-set);
            }
        }
    }

    self!check-for-flappers();

    CATCH {
        default {
            error "Failed processing CITestSetManagers worklist: " ~ .message ~ .backtrace.Str
        }
    }
}

method add-test-set(:$test-set!, :$source-spec!) {
    $test-set.status = DB::UNPROCESSED;
    $test-set.source-spec: $source-spec;
    $test-set.^save;
    self.process-worklist;
}

method add-tests(*@tests) {
    $_.tests-queued(@tests) for $!status-listeners.keys;
}

method test-status-updated($test) {
    $_.test-status-changed($test) for $!status-listeners.keys;
    self.process-worklist;
}

method platform-test-set-done($platform-test-set) {
    self.process-worklist;
}

method !check-test-set-done($test-set) {
    return if $test-set.platform-test-sets.elems < $!test-set-listeners.elems;
    if [&&] $test-set.platform-test-sets.map(*.status == DB::PLATFORM_DONE) {
        $test-set.finished-at = DateTime.now;
        $test-set.status = DB::DONE;
        $test-set.^save;
        $_.test-set-done($test-set) for $!status-listeners.keys;
    }
}

method !check-for-flappers() {
    for DB::CITest.^all.grep({
            $_.status == DB::FAILURE &&
            !$_.flapper-checked
    }) -> $test {
        without DB::CITest.^all.first({
                $_.successor.id == $test.id &&
                $_.flapper-checked &&
                $_.flapper.defined
        }) {
            # It's not a flapper re-test.
            if $!flapper-detector.is-flapper($test.log) {
                my $ts = $test.platform-test-set.test-set;
                for $!test-set-listeners.keys {
                    $_.re-test-test-set($ts)
                }

                $ts.status = DB::WAITING_FOR_TEST_RESULTS;
                $ts.^save;
            }

            $test.flapper-checked = True;
            $test.^save;
        }
    }
}
