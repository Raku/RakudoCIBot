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
has AzureInterface $!interface is built is required;
has CITestSetManager $!testset-manager is built is required;

has $.hook-suffix = "azure-hook";

method new-test-set(DB::CITestSet:D $test-set) {
    DB::CIPlatformTestSet.^create:
        :$test-set,
        platform => DB::AZURE;

    self.process-worklist();
}

method re-test-test-set(DB::CITestSet:D $test-set) {
    ...
}

method process-worklist() is serial-dedup {
    trace "Azure: Processing worklist";

    # New PTSes
    for DB::CIPlatformTestSet.^all.grep({
            $_.platform == DB::AZURE &&
            $_.status == DB::PLATFORM_NOT_STARTED }) -> $pts {
        # TODO: don't hard code the source URL here.
        $pts.azure-run-id = $!interface.run-pipeline('/source/' ~ $sac.get-filename($pts.test-set.source-archive-id), $pts.test-set.project);
        ...
        $pts.^save;
    }

    # Check for status changes in running PTSes
    for DB::CIPlatformTestSet.^all.grep({
            $_.platform == DB::AZURE &&
            $_.status == DB::PLATFORM_IN_PROGRESS }) {
        ...
    }

    CATCH {
        default {
            error "Failed processing Azure worklist: " ~ .message ~ .backtrace.Str
        }
    }
}

