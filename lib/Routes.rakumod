use Cro::HTTP::Router;
use Cro::WebApp::Template;

use Routes::home;
use Routes::test;
use Routes::testset;
use Routes::source;
use Routes::GitHubHook;
use SourceArchiveCreator;
use GitHubInterface;
use OBS;

sub routes(SourceArchiveCreator $sac, GitHubInterface $github-interface, OBS $obs) is export {
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

        include home-routes;
        include test-routes;
        include testset-routes;
        include source-routes($sac);
        include github-hook-routes($github-interface);
    }
}
