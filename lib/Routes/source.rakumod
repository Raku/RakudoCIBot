use SourceArchiveCreator;

use Cro::HTTP::Router;
use Cro::WebApp::Template;

sub source-routes(SourceArchiveCreator $sac) is export {
    route {
        get -> "source", $id {
            my $path = $sac.get-archive-path($id);
            if $path.f {
                header "Content-Length", $path.s;
                header "Content-Disposition", "attachment; filename=\"" ~  $id ~ ".tar.xz\"";
                static $path;
            }
            else {
                not-found 'text/html', render-template("404.crotmp", "Source archive with ID $id");
            }
        }
    }
}
