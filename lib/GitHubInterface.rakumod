unit class GitHubInterface;

use Log::Async;

has #`[GitHubCITestRequester] $.processor;

method parse-request($event, %json) {
    given $event {
        when 'pull_request' {
            if %json<action> eq 'opened' {
                with $.processor { .new-pr:
                    pr-number => %json<pull_request><number>,
                    user-url => %json<pull_request><url>,
                    body => %json<pull_request><body>,
                    from-repo => %json<pull_request><head><repo><full_name>,
                    from-branch => %json<pull_request><head><ref>,
                    to-repo => %json<pull_request><base><repo><full_name>,
                    to-branch => %json<pull_request><base><ref>;
                }
            }
        }
        when 'issue_comment' {
            if %json<action> eq "created" && (%json<issue><pull_request>:exists) {
                with $.processor { .new-pr-comment:
                    repo => %json<repository><full_name>,
                    pr-number => %json<issue><number>,
                    comment-id => %json<comment><id>,
                    comment-text => %json<comment><body>,
                    user-url => %json<comment><html_url>;
                }
            }
        }
        when 'push' {
            unless %json<ref> ~~ / 'ref/' (heads | tags) '/' (.*) / {
                fatal "couldn't match ref: '{ %json<ref> }'";
                return;
            }
            return if $0 eq "tags";

            my $branch = $1;

            with $.processor { .new-commit:
                repo => %json<repository><full_name>,
                :$branch,
                commit-sha => %json<head_commit><id>,
                user-url => %json<head_commit><url>;
            }
        }
        when 'commit_comment' {
            if %json<action> eq "created" {
                with $.processor { .new-commit-comment:
                    repo => %json<repository><full_name>,
                    commit-sha => %json<comment><commit_id>,
                    comment-id => %json<comment><id>,
                    comment-text => %json<comment><body>,
                    user-url => %json<comment><html_url>;
                }
            }
        }
    }
}

