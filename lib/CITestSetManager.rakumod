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
                        error "No PR for the given command found: " ~ $command.id;
                        $command.status = DB::COMMAND_DONE;
                        $command.^save;
                        next;
                    }

                    $command.origin-test-set = $ts;
                    $command.^save;

                    trace "CITestSetManager: Adding re-test test set for command: " ~ $command.id;
                    my $re-ts = DB::CITestSet.new:
                        status => DB::UNPROCESSED,
                        event-type => DB::COMMAND,
                        project => $ts.project,
                        git-url => $ts.git-url,
                        commit-sha => $ts.commit-sha,
                        user-url => $ts.user-url,
                        |($ts.pr ?? (pr => $ts.pr,) !! ()),
                        command => $command,
                        source-archive-id => $ts.source-archive-id,
                    ;
                    $re-ts.source-spec($ts.source-spec);
                    $re-ts.^save;

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
                trace "CITestSetManager: processing unprocessed " ~ $test-set.id;
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
                trace "CITestSetManager: processing source_archive_created " ~ $test-set.id;
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
}

method platform-test-set-done($platform-test-set) {
    self.process-worklist;
}

method !check-test-set-done($test-set) {
    return if $test-set.platform-test-sets.elems < $!test-set-listeners.elems;
    if [&&] $test-set.platform-test-sets.map(*.status == DB::PLATFORM_DONE) {
        $test-set.finished-at = now;
        $test-set.status = DB::DONE;
        $test-set.^save;
        $_.test-set-done($test-set) for $!status-listeners.keys;
    }
}

