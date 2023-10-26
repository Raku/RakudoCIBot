use Cro::HTTP::Router;
use Cro::HTTP::Auth::WebToken::FromCookie;
use Cro::WebApp::Template;
use Cro::Uri :encode-percents, :decode-percents;
use Red::Operators:api<2>;
use JSON::JWT;

use Routes::home;
use Routes::test;
use Routes::testset;
use Routes::source;
use Routes::GitHubHook;
use Config;
use SourceArchiveCreator;
use GitHubInterface;
use CITestSetManager;
use OBS;

constant $jwt-gh-cookie-name = "jwt-gh-login";
class JWT does Cro::HTTP::Auth::WebToken::FromCookie[$jwt-gh-cookie-name] {}

sub routes(CITestSetManager $tsm, SourceArchiveCreator $sac, GitHubInterface $github-interface, OBS $obs) is export {
    template-location 'resources/templates/';
    route {
        resources-from %?RESOURCES;
        #templates-from-resources prefix => 'templates';

        get -> "favicon.ico" {
            resource "static/favicon.ico";
        }
        get -> "css", *@path {
            resource "static/css", @path;
        }
        get -> "img", *@path {
            resource "static/img", @path;
        }
        get -> "js", *@path {
            resource "static/js", @path;
        }

        before JWT.new(secret => config.jwt-secret);

        template-part "login-part", -> Cro::HTTP::Auth $session {
            \(
                logged-in => True,
                name => $session.token<username>,
                logout-url => "/logout",
            )
        }

        template-part "login-part", -> {
            \(
                logged-in => False,
                name => "",
                logout-url => "",
            )
        }

        sub gen-login-data($origin) {
            my $url-data = $github-interface.oauth-step-one-url(encode-percents($origin));
            return $url-data;
        }

        post -> "logout" {
            set-cookie $jwt-gh-cookie-name, "", Max-Age => 0;
            redirect :see-other, "/";
        }

        get -> "gh-oauth-callback", :$code, :$state {
            # https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-user-access-token-for-a-github-app#using-the-web-application-flow-to-generate-a-user-access-token

            # 1. take code and generate an access-token
            my $gh-token = $github-interface.oauth-code-to-token($code, $state);
            my $gh-user = $github-interface.oauth-user-name($gh-token);

            # 2. stuff it into a web token saved in a cookie
            my $time = DateTime.new(now).later(days => 7).posix();
            my %data = :token($gh-token), :username($gh-user), :exp($time);
            my $token = JSON::JWT.encode(%data, :secret(config.jwt-secret), :alg('HS256'));
            set-cookie $jwt-gh-cookie-name, $token;

            # 3. Extract the originating URL from $state and forward there
            redirect decode-percents($state);
        }

        post -> Cro::HTTP::Auth $session, "retest", $testset-id {
            my $gh-token = $session.token<gh-token>;
            my $gh-user = $session.token<username>;

            my $ts = DB::CITestSet.^load: :id($testset-id);
            my $conf = config.projects.for-id($ts.pr.project);
            if $github-interface.can-user-merge-repo(owner => $conf.project, repo => $conf.repo, username => $gh-user) {
                $tsm.re-test($ts);
                created "/testset/$testset-id";
            }
            else {
                forbidden;
            }
        }

        include home-routes(&gen-login-data);
        include test-routes(&gen-login-data);
        include testset-routes($sac, &gen-login-data);
        include source-routes($sac);
        include github-hook-routes($github-interface);
    }
}
