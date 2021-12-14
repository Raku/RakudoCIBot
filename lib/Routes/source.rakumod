use SourceArchiveCreator;

use Cro::HTTP::Router;
use Cro::WebApp::Template;
use Red::Operators:api<2>;

sub source-routes(SourceArchiveCreator $sac) is export {
    route {
        get -> "source", $id {
            my $path = $sac.get-archive-path($id);
            if $path.f {
                header "Content-Length", $path.s;
                header "Content-Disposition", "attachment; filename=\"" ~  $id ~ ".tar.xz\"";
                my $handle = $path.open: :r, :bin;
                LEAVE {$handle.close}
                # TODO: How to close the handle at the appropriate time?
                content "application/octet-stream", $handle.Supply;
            }
            else {
                not-found 'text/html', render-template("404.crotmp", "Source archive with ID $id");
            }
        }
    }
}
