unit class GitHubInterface;

use Log::Async;
use WebService::GitHub::Checks::Runs;
use Cro::HTTP::Client;
use GitHubCITestRequester;

constant $gql-endpoint = "https://api.github.com/graphql";

has $!pat is built is required;

has Cro::HTTP::Client $!cro .= new:
    content-type => 'application/json',
    headers => [
        Authorization => "bearer $!pat",
    ];

has $!gh-runs = WebService::GitHub::Checks::Runs.new:
    access-token => $!pat;

has GitHubCITestRequester $.processor is required;

method parse-hook-request($event, %json) {
    given $event {
        when 'pull_request' {
            if %json<action> eq 'opened' {
                my $project = do given %json<pull_request><base><repo><full_name> {
                    when 'rakudo/rakudo' { "rakudo" }
                    when 'Raku/nqp'      { "nqp" }
                    when "MoarVM/MoarVM" { "moarvm" }
                };
                $.processor.add-task: GitHubCITestRequester::PRTask.new:
                    project      => %json<pull_request><base><repo><owner><login>,
                    git-url      => %json<pull_request><head><repo><clone_url>,
                    head-branch  => %json<pull_request><head><ref>,
                    number       => %json<pull_request><number>,
                    title        => %json<pull_request><title>,
                    body         => %json<pull_request><body>,
                    state        => %json<pull_request><state>,
                    user-url     => %json<pull_request><url>,
                    commit-task  => GitHubCITestRequester::PRCommitTask.new(
                        project      => %json<pull_request><base><repo><owner><login>,
                        pr-number    => %json<pull_request><number>,
                        commit-sha   => %json<pull_request><head><sha>,
                        user-url     => "https://github.com/patrickbkr/GitHub-API-Testing/pull/" ~ %json<pull_request><number> ~ "/commits/" ~ %json<pull_request><head><sha>,
                    ),
                ;
            }
        }
        #`[
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
        ]
    }
}

method !req-graphql($query) {
    my $response = await $!cro.post($gql-endpoint, body => {
        :$query;
    });
    await $response.body;
}

method retrieve-default-branch-commits($project, $repo, DateTime $since) {
    my $since-str = $since.Str;
    self!req-graphql: q:to<EOQ>;
        {
          repository(name: "\qq[$repo]", owner: "\qq[$project]") {
            defaultBranchRef {
              name
              target {
                ... on Commit {
                  history(since: "\qq[$since-str]") {
                    edges {
                      cursor
                      node {
                        oid
                        message
                        messageBody
                        author {
                          user {
                            login
                            name
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
        EOQ
}

method retrieve-default-branch-comments($repo, $project) {
    self!req-graphql: q:to<EOQ>;
        {
          repository(name: "\qq[$repo]", owner: "\qq[$project]") {
            commitComments(last: 10, after: "Y3Vyc29yOnYyOpHOAzEv0w==") {
              edges {
                cursor
                node {
                  body
                  commit {
                    commitUrl
                    oid
                    associatedPullRequests(last: 1) {
                      nodes {
                        merged
                      }
                    }
                  }
                }
              }
            }
          }
        }
        EOQ
}

method retrieve-pulls($project, $repo, $count) {
    my %data = self!req-graphql: q:to<EOQ>;
        {
          repository(name: "\qq[$repo]", owner: "\qq[$project]") {
            pullRequests(first: \qq[$count], orderBy: {direction: DESC, field: UPDATED_AT}) {
              edges {
                cursor
                node {
                  body
                  state
                  title
                  number
                  url
                  headRefName
                  commits(last: 1) {
                    nodes {
                      url
                      commit {
                        oid
                      }
                    }
                  }
                  comments(last: 100) {
                    nodes {
                      body
                      createdAt
                      id
                      updatedAt
                      url
                    }
                  }
                }
              }
            }
          }
        }
        EOQ
    %data<data><repository><pullRequests><edges>.map: -> %pull-data is copy {
        %pull-data = %pull-data<node>;
        GitHubCITestRequester::PRTask.new:
            :$project,
            git-url      => %pull-data<url> ~ '.git',
            head-branch  => %pull-data<headRefName>,
            number       => %pull-data<number>,
            title        => %pull-data<title>,
            body         => %pull-data<body>,
            state        => %pull-data<state>,
            user-url     => %pull-data<url>,
            comments     => %pull-data<comments><nodes>.map: {
                GitHubCITestRequester::PRCommentTask.new:
                    id         => $_<id>,
                    created-at => $_<createdAt>,
                    updated-at => $_<updatedAt>,
                    pr-number  => %pull-data<number>,
                    user-url   => $_<url>,
                    body       => $_<body>,
            },
            commit-task  => GitHubCITestRequester::PRCommitTask.new(
                :$project,
                pr-number => %pull-data<number>,
                commit-sha => %pull-data<commits><nodes>[0]<oid>,
                user-url => %pull-data<commits><nodes>[0]<url>,
            ),
        ;
    };
}

method create-check-run(:$owner!, :$repo!, :$name!, :$sha!, :$url!, :$id!, :$started-at!) {
    my $data = $!gh-runs.create($owner, $repo, $sha, $name, :details-url($url), :external-id($id), :$started-at);
    return $data<id>;
}

method update-check-run(:$owner!, :$repo!, :$check-run-id!, :$status!, :$completed-at, :$conclusion) {
    $!gh-runs.update($owner, $repo, $check-run-id,
        :$status,
        :$completed-at,
        :$conclusion
    )
}
