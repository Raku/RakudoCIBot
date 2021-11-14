use Cro::HTTP::Router;

use Routes::Home;
use Routes::GitHubHook;
use Cro::WebApp::Template;

sub routes() is export {
    route {
        resources-from %?RESOURCES;
        templates-from-resources prefix => 'templates';

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
        include github-hook-routes;
    }
}
