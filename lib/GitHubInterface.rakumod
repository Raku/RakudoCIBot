unit class GitHubInterface;

use Config;
use Log::Async;
use WebService::GitHub::AppAuth;
use WebService::GitHub;
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

method !parse-pr-state($text) {
    # The GraphQL API differentiates between closed and merged. The REST API does not.
    # Thus go for the smallest common and mush together closed and merged here.
    given $text {
        when "open" | "OPEN"     { GitHubCITestRequester::PRState::PR_OPEN }
        when "closed" | "CLOSED" | "merged" | "MERGED" { GitHubCITestRequester::PRState::PR_CLOSED }
        default {
            die "Unknown PRState found: " ~ $_;
        }
    }
}

method !validate(%data) {
    if %data<errors>:exists {
        note "Error in GitHub response: " ~ %data.gist;
    }
    return %data;
}

method parse-hook-request($event, %json) {
    given $event {
        # This event is only called for new commits, but not PRs.
        when 'check_suite' {
            if %json<action> eq 'requested' {
                if %json<check_suite><pull_requests>.elems == 0 {
                    # Simple commit
                    info "GitHubInterface: Received PUSH request for " ~ %json<repository><name> ~ " " ~ %json<check_suite><head_sha>;
                    $!processor.add-task: GitHubCITestRequester::CommitTask.new:
                        repo       => %json<repository><name>,
                        commit-sha => %json<check_suite><head_sha>,
                        user-url   => %json<repository><html_url> ~ "/commit/" ~ %json<check_suite><head_sha>,
                        git-url    => %json<repository><clone_url>,
                        branch     => %json<check_suite><head_branch>,
                    ;
                }
            }
        }
        # This event is called when PRs are created (action == opened) or changed (action == synchronize).
        when 'pull_request' {
            if %json<action> eq 'synchronize'|'opened' {
                $!processor.add-task: GitHubCITestRequester::PRTask.new(
                    repo        => %json<pull_request><base><repo><name>,
                    head-url    => %json<pull_request><head><repo><clone_url>,
                    base-url    => %json<pull_request><base><repo><clone_url>,
                    head-branch => %json<pull_request><head><ref>,
                    number      => %json<pull_request><number>,
                    title       => %json<pull_request><title>,
                    body        => %json<pull_request><body> // "",
                    state       => self!parse-pr-state(%json<pull_request><state>),
                    user-url    => %json<pull_request><html_url>,
                    comments    => [GitHubCITestRequester::PRCommentTask.new(
                        id         => %json<pull_request><node_id>,
                        created-at => %json<pull_request><created_at>,
                        updated-at => %json<pull_request><updated_at>,
                        pr-repo    => %json<pull_request><base><repo><name>,
                        pr-number  => %json<pull_request><number>,
                        user-url   => %json<pull_request><html_url>,
                        author     => %json<pull_request><user><login>,
                        body       => %json<pull_request><body>,
                    )],
                    commit-task => GitHubCITestRequester::PRCommitTask.new(
                        repo       => %json<pull_request><base><repo><name>,
                        pr-number  => %json<pull_request><number>,
                        commit-sha => %json<pull_request><head><sha>,
                        user-url   => %json<pull_request><html_url> ~ "/commits/" ~ %json<pull_request><head><sha>,
                    ),
                );
            }
        }
        when 'issue_comment' {
            if %json<action> eq 'created' && %json<issue><pull_request> && %json<comment><user><type> ne "Bot" {
                $!processor.add-task: GitHubCITestRequester::PRCommentTask.new(
                    id         => %json<comment><node_id>,
                    created-at => %json<comment><created_at>,
                    updated-at => %json<comment><updated_at>,
                    pr-repo    => %json<repository><name>,
                    pr-number  => %json<issue><number>,
                    user-url   => %json<comment><html_url>,
                    author     => %json<comment><user><login>,
                    body       => %json<comment><body>,
                );
            }
        }
        #`[
        when 'issue_comment' {
            if %json<action> eq "created" && (%json<issue><pull_request>:exists) {
                with $!processor { .new-pr-comment:
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

            with $!processor { .new-commit:
                repo => %json<repository><full_name>,
                :$branch,
                commit-sha => %json<head_commit><id>,
                user-url => %json<head_commit><url>;
            }
        }
        when 'commit_comment' {
            if %json<action> eq "created" {
                with $!processor { .new-commit-comment:
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
        my %data = self!validate($!gh.graphql.query(q:to<EOQ>).data);
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
        my %data = self!validate($!gh.graphql.query(q:to<EOQ>).data);
            {
              repository(name: "\qq[$repo]", owner: "\qq[$project]") {
                pullRequests(\qq[$limiter], orderBy: {direction: ASC, field: UPDATED_AT}) {
                  edges {
                    cursor
                    node {
                      id
                      author {
                        login
                      }
                      body
                      createdAt
                      lastEditedAt
                      state
                      title
                      number
                      url
                      headRefName
                      baseRepository {
                        url
                      }
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
                          id
                          body
                          createdAt
                          id
                          updatedAt
                          url
                          author {
                              login
                              __typename
                          }
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
                    base-url     => %pull-data<baseRepository><url> ~ '.git',
                    head-url     => %pull-data<headRepository><url> ~ '.git',
                    head-branch  => %pull-data<headRefName>,
                    number       => %pull-data<number>,
                    title        => %pull-data<title>,
                    body         => %pull-data<body>,
                    state        => self!parse-pr-state(%pull-data<state>),
                    user-url     => %pull-data<url>,
                    comments     => [
                        GitHubCITestRequester::PRCommentTask.new(
                            id         => %pull-data<id>,
                            created-at => %pull-data<createdAt>,
                            updated-at => %pull-data<lastEditedAt>,
                            pr-repo    => $repo,
                            pr-number  => %pull-data<number>,
                            user-url   => %pull-data<url>,
                            author     => %pull-data<author><login>,
                            body       => %pull-data<body>),
                        |%pull-data<comments><nodes>.grep({ $_<author><__typename> ne "Bot" }).map({
                            GitHubCITestRequester::PRCommentTask.new:
                                id         => $_<id>,
                                created-at => $_<createdAt>,
                                updated-at => $_<updatedAt>,
                                pr-repo    => $repo,
                                pr-number  => %pull-data<number>,
                                user-url   => $_<url>,
                                author     => $_<author><login>,
                                body       => $_<body>,
                        })
                    ],
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
    my $data = self!validate($!gh.checks-runs.create($owner, $repo, :$name, :head-sha($sha), :details-url($url), :external-id($id), :started-at($started-at.Str)).data);
    return $data<id>;
}

method update-check-run(:$owner!, :$repo!, Str() :$check-run-id!, :$status!, DateTime:D :$completed-at, :$conclusion) {
    self!validate($!gh.checks-runs.update($owner, $repo, $check-run-id,
        :$status,
        |($completed-at ?? completed-at => $completed-at.Str !! {}),
        :$conclusion
    ).data)
}

method add-issue-comment(:$owner!, :$repo!, :$number!, :$body) {
    self!validate($!gh.issues-comments.create-comment($owner, $repo, $number, :$body).data);
}

method merge-pr(:$owner!, :$repo!, :$number!, :$sha) {
    self!validate($!gh.pulls.merge($owner, $repo, $number, |($sha ?? :$sha !! ())).data);
}

method can-user-merge-repo(Str :$owner!, Str :$repo!, Str :$username! --> Bool) {
    my %data = self!validate($!gh.repos-collaborators.get-collaborator-permission-level($owner, $repo, $username).data);
    return %data<permission> ~~ ("admin" | "write");
}

method get-branch(Str :$owner!, Str :$repo!, Str :$branch!) {
    my $res = self!validate($!gh.repos-branches.get-branch($owner, $repo, $branch).data);
    CATCH { return Nil }
    return $res
}
