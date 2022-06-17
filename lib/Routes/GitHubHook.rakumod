use Cro::HTTP::Router;

sub github-hook-routes($github-interface) is export {
    route {
        post -> 'github-hook', :$X-Github-Event! is header {
            request-body -> %json {
                $github-interface.parse-hook-request($X-Github-Event, %json);
                content 'text/txt', 'Hi GitHub!';
            }
        }
    }
}
