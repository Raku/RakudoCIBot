use Cro::HTTP::Router;

sub routes($gh-pat) is export {
    route {
        post -> 'github-hook', :$X-Github-Event! is header where 'pull_request' {
            request-body -> %json {
                if %json<action> eq 'opened' {
                    # Got a new PR. Process.

                }
                say %json;
                content 'text/txt', 'Hi GitHub PR';
            }
        }
        post -> 'github-hook', :$X-Github-Event! is header where 'issue_comment' {
            request-body -> %json {
                if %json<issue><pull_request>:exists {
                    content 'text/txt', 'Hi GitHub PR comment';
                }
            }
        }

        post -> 'github-hook', :$X-Github-Event! is header {
            request-body -> %json {
                say "Unknown event type $X-Github-Event received";
                content 'text/txt', 'Hi GitHub whatever';
            }
        }
    }
}
