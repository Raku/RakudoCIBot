use DB;
use Formatters;

use Cro::HTTP::Router;
use Cro::WebApp::Template;
use Red::Operators:api<2>;

sub home-routes() is export {
    route {
        get -> {
            my %data = test-sets => ();
            for DB::CITestSet.^all.sort(-*.id).head(20) {
                %data<test-sets>.push: %(
                    id => .id,
                    project => .project,
                    commit-sha => .commit-sha // "",
                    created-at => format-dt(.creation),
                    finished-at => format-dt(.finished-at),
                    status => .status,
                    status-indicator-class =>
                        (.status != DB::DONE ?? "in-progress" !!
                        ([&&] .platform-test-sets.Seq.map({ $_.tests.Seq.map({.status == DB::SUCCESS}) }).flat) ?? "success" !! "failure"),
                    test-set-url => "/testset/" ~ .id,
                );
            }
            template "home.crotmp", %data;
        }
    }
}
