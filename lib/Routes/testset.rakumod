use DB;
use Formatters;

use Cro::HTTP::Router;
use Cro::WebApp::Template;
use Red::Operators:api<2>;

sub testset-routes($sac) is export {
    route {
        get -> "testset", UInt $id {
            with DB::CITestSet.^load($id) {
                sub order-tests(@tests) {
                    my @ordered = @tests.grep(!*.obs-before-re-test);
                    my @superseded = @tests.grep(*.obs-before-re-test);
                    @ordered.map: {
                        my @a = $_;
                        my $a-size = @a.elems;
                        repeat {
                            for @superseded -> $s {
                                say $s.successor.id if $s.successor;
                                if $s.successor && $s.successor.id == @a[*-1].id {
                                    @a.push: $s;
                                    last;
                                }
                            }
                        } while @a.elems > $a-size++;
                        |@a;
                    };
                }
                my %data =
                    id => .id,
                    created-at => .creation,
                    project => .project,
                    user-url => .user-url,
                    commit-sha => .commit-sha,
                    status => .status,
                    status-indicator-class =>
                        (.status != DB::DONE ?? "in-progress" !!
                        ([&&] .platform-test-sets.Seq.map({ $_.tests.Seq.map({.status == DB::SUCCESS}) }).flat) ?? "success" !! "failure"),
                    error => .error,
                    rakudo-git-url => .source-spec.rakudo-git-url,
                    rakudo-commit-sha => .source-spec.rakudo-commit-sha,
                    nqp-git-url => .source-spec.nqp-git-url,
                    nqp-commit-sha => .source-spec.nqp-commit-sha,
                    moar-git-url => .source-spec.moar-git-url,
                    moar-commit-sha => .source-spec.moar-commit-sha,
                    source-url => (.source-archive-id ?? "/source/" ~ $sac.get-filename(.source-archive-id) !! ""),
                    backends => .platform-test-sets.Seq.map({%(
                        name => do given .platform {
                            when DB::AZURE { "Azure CI" }
                            when DB::OBS   { "OBS" }
                        },
                        id => .id,
                        tests => order-tests(.tests.Seq).map({%(
                            id => .id,
                            superseded-class => .obs-before-re-test ?? "superseded" !! "",
                            status-indicator-class =>
                                .status == DB::SUCCESS ?? "success" !!
                                .status == DB::IN_PROGRESS ?? "in-progress" !!
                                .status == DB::NOT_STARTED ?? "not-started" !!
                                "failure",
                            name => .name,
                            status => .status,
                            created-at => format-dt(.creation),
                            started-at => format-dt(.test-started-at),
                            finished-at => format-dt(.test-finished-at),
                            backend-url => .ci-url // "",
                            log-url => .log ?? "/test/{.id}/log" !! "",
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
