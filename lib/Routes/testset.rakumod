use DB;

use Cro::HTTP::Router;
use Cro::WebApp::Template;
use Red::Operators:api<2>;

sub testset-routes() is export {
    route {
        get -> "testset", UInt $id {
            with DB::CITestSet.^load($id) {
                my %data =
                    id => .id,
                    created-at => .creation,
                    project => .project,
                    user-url => .user-url,
                    commit-sha => .commit-sha,
                    status => .status,
                    status-indicator-class =>
                        (.status != DB::DONE ?? "in-progress" !!
                        [&&] .tests.Seq.map({.status == DB::SUCCESS}) ?? "success" !! "failure"),
                    error => .error,
                    rakudo-git-url => .source-spec.rakudo-git-url,
                    rakudo-commit-sha => .source-spec.rakudo-commit-sha,
                    nqp-git-url => .source-spec.nqp-git-url,
                    nqp-commit-sha => .source-spec.nqp-commit-sha,
                    moar-git-url => .source-spec.moar-git-url,
                    moar-commit-sha => .source-spec.moar-commit-sha,
                    source-link => "/source/" ~ .source-archive-id,
                    backends => .platform-test-sets.Seq.map({%(
                        name => do given .platform {
                            when DB::AZURE { "Azure CI" }
                            when DB::OBS   { "OBS" }
                        },
                        tests => .tests.Seq.map({%(
                            status-indicator-class =>
                                .status == DB::SUCCESS ?? "success" !!
                                .status == DB::IN_PROGRESS ?? "in-progress" !!
                                .status == DB::NOT_STARTED ?? "not-started" !!
                                "failure",
                            name => .name,
                            status => .status,
                            created-at => .creation,
                            started-at => .test-started-at,
                            finished-at => .test-finished-at,
                            backend-url => "todo",
                            log-url => "/test/{.id}/log",
                        )}),
                    )}),
                ;
                template "testset.crotmp", %data;
            }
            else {
                not-found 'text/html', render-template("404.crotmp", "Test Set $id");
            }
        }
    }
}
