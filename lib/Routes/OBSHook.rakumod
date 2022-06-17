use Cro::HTTP::Router;

sub obs-hook-routes($obs) is export {
    route {
        post -> $ where { $_ eq $obs.hook-suffix }, UInt $pts-id {
            $obs.hook-call-received($pts-id);
            content 'text/txt', 'Hi GitHub!';
        }
    }
}
