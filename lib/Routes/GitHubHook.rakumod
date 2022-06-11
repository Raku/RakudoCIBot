use Cro::HTTP::Router;

sub github-hook-routes($github-interface) is export {
    route {
        post -> 'github-hook', :$X-Github-Event! is header {
            request-body -> %json {
                $github-interface.parse-hook-request($X-Github-Event, %json);
                content 'text/txt', 'Hi GitHub check_suite request';
            }
        }

    #`[
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
        post -> 'github-hook', :$X-Github-Event! is header where 'push' {
            request-body -> %json {
                if %json<head_commit><message>:exists {
                    content 'text/txt', 'Hi GitHub commit';
                }
            }
        }
        post -> 'github-hook', :$X-Github-Event! is header {
            request-body -> %json {
                say "Unknown event type $X-Github-Event received";
                content 'text/txt', 'Hi GitHub whatever';
            }
        }
    ]
    }
}
