use DB;

use Cro::HTTP::Router;
use Cro::WebApp::Template;
use Red::Operators:api<2>;

sub test-routes(&gen-login-data) is export {
    route {
        get -> "test", UInt $id {
            with DB::CITest.^load($id) {
                my %data =
                    login-url => gen-login-data("/test/$id"),
                    id => .id,
                    name => .name,
                    backend => .platform-test-set.platform,
                    status => .status,
                    log-url => "/test/{.id}/log",
                    created-at => .creation,
                    started-at => .test-started-at,
                    finished-at => .test-finished-at,
                    commit-url => "todo",
                    backend-url => "todo",
                    test-set-url => "/testset/" ~ .platform-test-set.test-set.id,
                ;

                template "test.crotmp", %data;
            }
            else {
                not-found 'text/html', render-template("404.crotmp", "Test $id");
            }
        }

        get -> "test", UInt $id, "log" {
            with DB::CITest.^load($id) {
                content "text/plain", $_.log;
            }
            else {
                not-found 'text/html', render-template("404.crotmp", "Test $id log");
            }
        }
    }
}
