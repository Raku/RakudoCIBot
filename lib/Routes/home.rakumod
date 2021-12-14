use Cro::HTTP::Router;
use Cro::WebApp::Template;

sub home-routes() is export {
    route {
        get -> {
            template "home.crotmp";
        }
    }
}
