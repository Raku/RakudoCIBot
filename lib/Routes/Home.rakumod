use Cro::HTTP::Router;
use Cro::WebApp::Template;

sub home-routes() is export {
    route {
        get -> {
            template "page.html.tmpl", 'Hello from the Rakudo CI bot!';
        }
    }
}
