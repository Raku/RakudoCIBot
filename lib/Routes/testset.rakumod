use DB;
use Formatters;
use Config;

use Cro::HTTP::Router;
use Cro::WebApp::Template;
use Red::Operators:api<2>;

sub testset-routes($sac, $tsm, $github-interface, &gen-login-data) is export {
    route {
        post -> Cro::HTTP::Auth $session, "testset", UInt $id, :$command where "retest" {
            my $gh-token = $session.token<gh-token>;
            my $gh-user = $session.token<username>;

            my $ts = DB::CITestSet.^load: :$id;
            my $conf = config.projects.for-id($ts.project);
            if $github-interface.can-user-merge-repo(owner => $conf.project, repo => $conf.repo, username => $gh-user) {
                $tsm.re-test($ts);
                created "/testset/$id";
            }
            else {
                forbidden;
            }
        }

        get -> Cro::HTTP::Auth $session, "testset", UInt $id {
            make-testset-page($id, True);
        }

        get -> "testset", UInt $id {
            make-testset-page($id, False);
        }

        sub make-testset-page($id, $logged-in) {
            with DB::CITestSet.^load($id) {
                sub order-tests(@tests) {
                    my @ordered = @tests.grep(!*.superseded);
                    my @superseded = @tests.grep(*.superseded);
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
                    login-data => gen-login-data("/testset/$id"),
                    id => .id,
                    created-at => .creation,
                    project => .project,
                    user-url => .user-url,
                    commit-sha => .commit-sha,
                    status => .status,
                    status-indicator-class =>
                        (.status != DB::DONE ?? "in-progress" !!
                        ([&&] .platform-test-sets.Seq.map({ $_.tests.Seq.map({.superseded || .status == DB::SUCCESS}) }).flat) ?? "success" !! "failure"),
                    error => .error,
                    :$logged-in,
                    retest-url => "/testset/$id?command=retest",
                    rakudo-git-url => .source-spec.rakudo-git-url,
                    rakudo-commit-sha => .source-spec.rakudo-commit-sha,
                    nqp-git-url => .source-spec.nqp-git-url,
                    nqp-commit-sha => .source-spec.nqp-commit-sha,
                    moar-git-url => .source-spec.moar-git-url,
                    moar-commit-sha => .source-spec.moar-commit-sha,
                    source-url => (.source-archive-exists ?? "/source/" ~ $sac.get-filename(.source-archive-id) !! ""),
                    backends => .platform-test-sets.Seq.map({%(
                        name => do given .platform {
                            when DB::AZURE { "Azure CI" }
                            when DB::OBS   { "OBS" }
                        },
                        id => .id,
                        tests => order-tests(.tests.Seq).map({%(
                            id => .id,
                            superseded-class => .superseded ?? "superseded" !! "",
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
