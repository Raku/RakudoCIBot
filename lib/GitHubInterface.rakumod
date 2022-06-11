unit class GitHubInterface;

use Config;
use Log::Async;
use WebService::GitHub::AppAuth;
use WebService::GitHub;
use Cro::HTTP::Client;
use GitHubCITestRequester;

constant $gql-endpoint = "https://api.github.com/graphql";
has WebService::GitHub::AppAuth $!gh-auth;
has WebService::GitHub $!gh;
has GitHubCITestRequester $.processor is required;

submethod TWEAK(:$app-id!, :$pem!) {
    $!gh-auth .= new:
        :$app-id,
        :$pem
    ;

    $!gh .= new:
        app-auth   => $!gh-auth,
        install-id => config.projects.rakudo.install-id,
    ;
}

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
                    repo        => %json<pull_request><base><repo><owner><login>,
                    number      => %json<pull_request><number>,
                    title       => %json<pull_request><title>,
                    body        => %json<pull_request><body>,
                    state       => %json<pull_request><state>,
                    git-url     => %json<pull_request><head><repo><clone_url>,
                    head-branch => %json<pull_request><head><ref>,
                    user-url    => %json<pull_request><url>,
                    commit-task => GitHubCITestRequester::PRCommitTask.new(
                        repo       => %json<pull_request><base><repo><owner><login>,
                        pr-number  => %json<pull_request><number>,
                        commit-sha => %json<pull_request><head><sha>,
                        user-url   => "https://github.com/patrickbkr/GitHub-API-Testing/pull/" ~ %json<pull_request><number> ~ "/commits/" ~ %json<pull_request><head><sha>,
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

method retrieve-default-branch-commits($project, $repo, :$last-cursor) {
    my $batch-count = config.github-check-batch-count;
    my $running-cursor;
    my $backup-counter = 100;
    my $git-url;
    my $branch;
    my @commits;
    LOOPER: loop {
        my $limiter = ($running-cursor ?? "after: \"$running-cursor\", " !! "") ~ "first: " ~ ($last-cursor ?? $batch-count !! "1");
        my %data = $!gh.graphql.query(q:to<EOQ>).data;
            {
              repository(name: "\qq[$repo]", owner: "\qq[$project]") {
                url
                defaultBranchRef {
                  name
                  target {
                    ... on Commit {
                      history(\qq[$limiter]) {
                        nodes {
                          oid
                          commitUrl
                          message
                          messageBody
                          author {
                            user {
                              login
                              name
                            }
                          }
                        }
                        pageInfo {
                          endCursor
                        }
                      }
                    }
                  }
                }
              }
            }
            EOQ
        $git-url = %data<data><repository><url> ~ ".git"           unless $git-url;
        $branch  = %data<data><repository><defaultBranchRef><name> unless $branch;
        for %data<data><repository><defaultBranchRef><target><history><nodes><> -> %commit {
            if $backup-counter-- == 0 {
                error "Didn't find last-cursor. Aborting retrieving more commits. Started search at @commits[0]<oid>, stopped at %commit<oid>.";
                last LOOPER;
            }
            last LOOPER if  $last-cursor && %commit<oid> eq $last-cursor;
            @commits.push: %commit;
            last LOOPER if  !$last-cursor;
        }
        $running-cursor = %data<data><repository><defaultBranchRef><target><history><pageInfo><endCursor>;
    }

    @commits = @commits
        .reverse
        .map: -> %commit {
            GitHubCITestRequester::CommitTask.new:
                :$repo,
                commit-sha   => %commit<oid>,
                user-url     => %commit<commitUrl>,
                :$git-url,
                :$branch,
            ;
        };

    %(
        last-cursor => @commits ?? @commits[*-1].commit-sha !! $last-cursor,
        :@commits,
    )
}

method retrieve-pulls($project, $repo, :$last-cursor is copy) {
    my $batch-count = config.github-check-batch-count;
    my @prs;
    loop {
        my $limiter = $last-cursor.defined ?? "after: \"$last-cursor\", first: $batch-count" !! "last: 1";
        my %data = $!gh.graphql.query(q:to<EOQ>).data;
            {
              repository(name: "\qq[$repo]", owner: "\qq[$project]") {
                pullRequests(\qq[$limiter], orderBy: {direction: ASC, field: UPDATED_AT}) {
                  edges {
                    cursor
                    node {
                      body
                      state
                      title
                      number
                      url
                      headRefName
                      headRepository {
                        url
                      }
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
        my @new-prs = %data<data><repository><pullRequests><edges>.map(-> %pull-data is copy {
                %pull-data = %pull-data<node>;
                GitHubCITestRequester::PRTask.new:
                    :$repo,
                    git-url      => %pull-data<headRepository><url> ~ '.git',
                    head-branch  => %pull-data<headRefName>,
                    number       => %pull-data<number>,
                    title        => %pull-data<title>,
                    body         => %pull-data<body>,
                    state        => %pull-data<state>,
                    user-url     => %pull-data<url>,
                    comments     => %pull-data<comments><nodes>.map({
                        GitHubCITestRequester::PRCommentTask.new:
                            id         => $_<id>,
                            created-at => $_<createdAt>,
                            updated-at => $_<updatedAt>,
                            pr-number  => %pull-data<number>,
                            user-url   => $_<url>,
                            body       => $_<body>,
                    }),
                    commit-task  => GitHubCITestRequester::PRCommitTask.new(
                        :$repo,
                        pr-number => %pull-data<number>,
                        commit-sha => %pull-data<commits><nodes>[0]<commit><oid>,
                        user-url => %pull-data<commits><nodes>[0]<url>,
                    ),
                ;
            }
        );
        if @new-prs {
            @prs.append: @new-prs;
            $last-cursor = %data<data><repository><pullRequests><edges>[*-1]<cursor>;
        }
        else {
            last;
        }
    }
    %(
        :$last-cursor,
        :@prs;
    );
}

method create-check-run(:$owner!, :$repo!, :$name!, :$sha!, :$url!, Str() :$id!, DateTime:D :$started-at!) {
    my $data = $!gh.checks-runs.create($owner, $repo, :$name, :head-sha($sha), :details-url($url), :external-id($id), :started-at($started-at.Str)).data;
    return $data<id>;
}

method update-check-run(:$owner!, :$repo!, Str() :$check-run-id!, :$status!, DateTime:D :$completed-at, :$conclusion) {
    $!gh.checks-runs.update($owner, $repo, $check-run-id,
        :$status,
        |($completed-at ?? completed-at => $completed-at.Str !! {}),
        :$conclusion
    ).data
}
