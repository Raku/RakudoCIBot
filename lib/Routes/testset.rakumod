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
                    error => .error,
                    rakudo-git-url => .source-spec.rakudo-git-url,
                    rakudo-commit-sha => .source-spec.rakudo-commit-sha,
                    nqp-git-url => .source-spec.nqp-git-url,
                    nqp-commit-sha => .source-spec.nqp-commit-sha,
                    moar-git-url => .source-spec.moar-git-url,
                    moar-commit-sha => .source-spec.moar-commit-sha,
                    source-link => "/sources/" ~ .source-archive-id,
                    tests => .platform-test-sets.map(*.tests).flat.map({%(
                        id => .id,
                        name => .name,
                        status => .status,
                        url => "/test/{.id}",
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
