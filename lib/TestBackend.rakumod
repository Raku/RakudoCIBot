use CITestSetListener;
unit class TestBackend does CITestSetListener;

use DB;
use SerialDedup;
use Red::Operators:api<2>;
use Log::Async;
use Config;
use CITestSetManager;

has CITestSetManager $!testset-manager is built is required;

has %in-progress;

method new-test-set(DB::CITestSet:D $test-set) {
    DB::CIPlatformTestSet.^create:
        :$test-set,
        platform => DB::TEST_BACKEND;

    self.process-worklist();
}

method re-test-test-set(DB::CITestSet:D $test-set) {
    my $pts = DB::CIPlatformTestSet.^all.first({
        $_.platform == DB::TEST_BACKEND &&
        $_.test-set.id == $test-set.id
    });
    if $pts {
        $pts.status = DB::PLATFORM_IN_PROGRESS;
        $pts.re-test = True;
        $pts.^save;
        self.process-worklist();
    }
}

method process-worklist() is serial-dedup {
    my @running-ptses = DB::CIPlatformTestSet.^all.grep({
        $_.platform == DB::TEST_BACKEND &&
        $_.status == DB::PLATFORM_IN_PROGRESS });

    for @running-ptses -> $pts {
        if %in-progress{$pts.id}:exists {
            my $start-time = %in-progress{$pts.id};
            if DateTime.now - $start-time < 10 {
                # Auto-done after 10 seconds
                trace "TestBackend: TestSet finished: " ~ $pts.id;
                my @tests = DB::CITest.^all.grep({
                    $_.platform-test-set.id == $pts.id
                });
                for @tests -> $test {
                    $test.status = $test.name eq "Test One" ?? DB::SUCCESS !! DB::FAILURE;
                    $test.test-finished-at = DateTime.now;
                    $test.log = "Some log text";
                    $test.^save;
                    $!testset-manager.test-status-updated($test);
                }

                $pts.status = DB::PLATFORM_DONE;
                $pts.^save;
                $!testset-manager.platform-test-set-done($pts);
            }
        }
        else {
            trace "TestBackend: New TestSet: " ~ $pts.test-set.id;
            %in-progress{$pts.id} = DateTime.now;
            my @tests = "Test One", "Test Two";
            for @tests -> $name {
                DB::CITest.^create:
                    name              => $name,
                    status            => DB::IN_PROGRESS,
                    platform-test-set => $pts,
                    test-started-at   => DateTime.now,
                    ciplatform        => DB::TEST_BACKEND;
            }
            $!testset-manager.add-tests(@tests);
        }
    }
    CATCH {
        default {
            error "Failed processing TestBackend worklist: " ~ .message ~ .backtrace.Str
        }
    }
}
