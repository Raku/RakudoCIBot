use Log::Async;

use CITestStatusListener;
use DB;
use Red::Operators:api<2>;
use SerialDedup;
use SourceArchiveCreator;
use CITestSetManager;
use Config;


unit class GitHubCITestRequester does CITestStatusListener;

class CommitTask {
    has $.repo is required;
    has $.commit-sha is required;
    has $.user-url is required;
    has $.git-url is required;
    has $.branch is required;
}

class PRCommentTask {
    has $.id is required;
    has $.created-at is required;
    has $.updated-at is required;
    has $.pr-repo is required;
    has $.pr-number is required;
    has $.user-url is required;
    has $.body is required;
}

class PRCommitTask {
    has $.repo is required;
    has $.pr-number is required;
    has $.commit-sha is required;
    has $.user-url is required;
}

enum PRState <PR_OPEN PR_CLOSED>;
class PRTask {
    has $.repo is required;
    has $.number is required;
    has $.title is required;
    has PRState $.state is required;
    has $.base-url is required;
    has $.head-url is required;
    has $.head-branch is required;
    has $.user-url is required;
    has PRCommentTask @.comments;
    has PRCommitTask $.commit-task is required;
}

has CITestSetManager $.testset-manager is required;
has $.github-interface is rw;

has Supplier::Preserving $!input-task-supplier .= new;
has $!input-task-supply = $!input-task-supplier.Supply;

submethod TWEAK() {
    $!input-task-supply.tap: -> $task {
        given $task {
            when CommitTask    { self!process-commit-task($task) }
            when PRTask        { self!process-pr-task($task) }
            when PRCommentTask { self!process-pr-comment-task($task) }
            when PRCommitTask  { self!process-pr-commit-task($task) }
            default            { die "Unknown task: " ~ $task.^name }
        }
    }
}

method add-task($task) {
    $!input-task-supplier.emit: $task
}

method !process-pr-task(PRTask $pr) {
    # Check if it's new
    my $project = self!repo-to-db-project($pr.repo);
    if DB::GitHubPR.^all.grep({
                $_.project == $project &&
                $_.number == $pr.number
            }).elems == 0
            && $pr.state == PR_OPEN {
        # Unknown PR, add it!
        info "GitHub: Adding PR: " ~ $pr.number;
        my $db-pr = DB::GitHubPR.^create:
            project      => self!repo-to-db-project($pr.repo),
            number       => $pr.number,
            base-url     => $pr.base-url,
            head-url     => $pr.head-url,
            head-branch  => $pr.head-branch,
            user-url     => $pr.user-url,
            status       => DB::OPEN,
        ;
    }

    self!process-pr-commit-task($pr.commit-task);
    self!process-pr-comment-task($_) for $pr.comments;
}

method !process-pr-commit-task(PRCommitTask $commit) {
    my $project = self!repo-to-db-project($commit.repo);
    my $pr = DB::GitHubPR.^all.first({
                $_.number == $commit.pr-number
                && $_.project == $project
            });
    return unless $pr; # If the PR object isn't there, we'll just pass. Polling will take care of it.

    my $ts = DB::CITestSet.^all.first({
            $_.event-type == DB::PR
            && $_.pr.number == $commit.pr-number
            && $_.project == $project
            && $_.commit-sha eq $commit.commit-sha
    });
    without $ts {
        info "GitHub: Adding PR commit: " ~ $commit.commit-sha;
        DB::CITestSet.^create:
            event-type => DB::PR,
            :$project,
            git-url    => $pr.head-url,
            commit-sha => $commit.commit-sha,
            user-url   => $commit.user-url,
            :$pr,
            ;
        self.process-worklist;
    }
}

method !process-pr-comment-task(PRCommentTask $comment) {
    my Bool $need-to-process = False;
    for $comment.body ~~ m:g:i/ '{' \s* 'rcb:' \s* ( <[ \w - ]>+ ) \s* '}' / -> $m {
        my $command-text = $m[0];
        my $command = self!command-to-enum($command-text);
        my $proj-repo = self!repo-to-project-repo($comment.pr-repo);

        my $pr = DB::GitHubPR.^all.first({
                    $_.number == $comment.pr-number
                    && $_.project == $proj-repo<db-project>
                });
        return unless $pr; # If the PR object isn't there, we'll just pass. Polling will take care of it.

        with $command {
            return with DB::Command.^all.first({
                $_.comment-id eq $comment.id &&
                $_.pr.id == $pr.id &&
                $_.command == $command
            });

            info "Adding PR comment: " ~ $comment.created-at;

            DB::Command.^create:
                :$pr,
                comment-id => $comment.id,
                comment-url => $comment.user-url,
                :$command,
                status => DB::COMMAND_NEW,
            ;
            $need-to-process = True;
        }
        else {
            $!github-interface.add-issue-comment:
                owner  => $proj-repo<project>,
                repo   => $proj-repo<repo>,
                number => $comment.pr-number,
                body   => "I didn't understand the command `" ~ $command-text ~ "`.";
        }
    }
    $!testset-manager.process-worklist if $need-to-process;
}

method !process-commit-task(CommitTask $commit) {
    my $ts = DB::CITestSet.^all.first({
        $_.event-type == DB::MAIN_BRANCH
        && $_.project == self!repo-to-db-project($commit.repo)
        && $_.commit-sha eq $commit.commit-sha
    });
    without $ts {
        info "GitHub: Adding commit: " ~ $commit.commit-sha;
        DB::CITestSet.^create:
            event-type => DB::MAIN_BRANCH,
            project    => self!repo-to-db-project($commit.repo),
            git-url    => $commit.git-url,
            commit-sha => $commit.commit-sha,
            user-url   => $commit.user-url,
            ;
        self.process-worklist;
    }
}

method poll-for-changes() is serial-dedup {
    trace "GitHub: Polling for changes";
    for DB::RAKUDO, config.projects.rakudo,
        DB::NQP,    config.projects.nqp,
        DB::MOAR,   config.projects.moar -> $db-project, $project {
        my $state = DB::GitHubPullState.^all.first({ $_.project == $db-project }) // DB::GitHubPullState.^create(project => $db-project);

        # PRs
        my %pull-data = $!github-interface.retrieve-pulls($project.project, $project.repo, |($state.last-pr-cursor ?? last-cursor => $state.last-pr-cursor !! ()));
        self.add-task($_) for %pull-data<prs><>;
        if %pull-data<last-cursor> {
            $state.last-pr-cursor = %pull-data<last-cursor>;
            $state.^save;
        }

        # Default branch commits
        my %commit-data = $!github-interface.retrieve-default-branch-commits($project.project, $project.repo, |($state.last-default-branch-cursor ?? last-cursor => $state.last-default-branch-cursor !! ()));
        self.add-task($_) for %commit-data<commits><>;
        if %commit-data<last-cursor> {
            $state.last-default-branch-cursor = %commit-data<last-cursor>;
            $state.^save;
        }
    }
    CATCH {
        default {
            error "GitHub: Polling for changes failed: " ~ .message ~ .backtrace.Str
        }
    }
}

method process-worklist() is serial-dedup {
    for DB::CITestSet.^all.grep(*.status == DB::NEW) -> $test-set {
        trace "GitHub: Processing NEW TestSet";
        my $source-spec = self!determine-source-spec(
            project => $test-set.project,
            git-url => $test-set.git-url,
            commit-sha => $test-set.commit-sha,
            # |($test-set.pr ?? (fetch-ref => "refs/pulls/" ~ $test-set.pr.number ~ "/head",) !! ()),
            );
        $!testset-manager.add-test-set(:$test-set, :$source-spec);

        CATCH {
            default {
                error "GitHub: Failure processing new test set: " ~ .message ~ .backtrace.Str
            }
        }
    }

    for DB::CITest.^all.grep({ .status != .status-pushed }) -> $test {
        trace "GitHub: Test status changed: " ~ $test.id ~ " from " ~ $test.status-pushed ~ " to " ~ $test.status;

        my $ts = $test.platform-test-set.test-set;

        my $gh-status = do given $test.status {
            when DB::NOT_STARTED { "queued" }
            when DB::IN_PROGRESS { "in_progress" }
            default { "completed" }
        };
        my $completed-at;
        my $conclusion;
        if $gh-status eq "completed" {
            $completed-at = DateTime.now;
            $conclusion = do given $test.status {
                when DB::NOT_STARTED { "queued" }
                when DB::IN_PROGRESS { "in_progress" }
                when DB::SUCCESS { "success" }
                when DB::FAILURE { "failure" }
                when DB::ABORTED { "cancelled" }
                when DB::UNKNOWN { "timed_out" }
            };
        }

        # Note, that in the PR case we are using the base url, i.e. the repo that the PR was opened on,
        # NOT the head (the repo where the new commits are).
        # Using the head repo will not work, as that's usually a different repo where the RCB is
        # not installed on and thus has no permissons to add check_runs.
        # One would think using the base repo can't work, because the commits are not part of that
        # repository. But there is some almost completely undocumented behavior in GitHub that copies
        # PR commits to the base repo and even creates merge commits (without the PR being merged!).
        # Those commit objects are by default not copied to clients, so they are usually invisible.
        # But they can actually be accessed when explicitly fetching the respective refs:
        # - refs/pull/<pr_number>/head points at the head commit of the PR
        # - refs/pull/<pr_number>/merge points at the merge commit of the PR
        # See https://gist.github.com/piscisaureus/3342247
        # See https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/reviewing-changes-in-pull-requests/checking-out-pull-requests-locally
        my $pr = self!get-pr($ts);
        my %project-and-repo = self!github-url-to-project-repo($pr ?? $pr.base-url
                                                                      !! $ts.git-url);

        if $test.status-pushed == DB::NOT_STARTED {
            trace "GitHub: Queueing test { $test.name } ({ $test.id }): { %project-and-repo<project> }/{ %project-and-repo<repo> } { $ts.commit-sha }, status: { $test.status }, { $completed-at // "" } { $conclusion // "" }";
            $test.github-id = $!github-interface.create-check-run(
                owner => %project-and-repo<project>,
                repo => %project-and-repo<repo>,
                name => $test.name,
                sha => $ts.commit-sha,
                url => "https://cibot.rakudo.org/test/" ~ $test.id,
                id => $test.id,
                started-at => DateTime.now,
                status => $gh-status,
                |($completed-at ?? :$completed-at !! {}),
                |($conclusion ?? :$conclusion !! {}),
                );
        }
        else {
            trace "GitHub: Updating test { $test.name } ({ $test.id }): { %project-and-repo<project> }/{ %project-and-repo<repo> } { $ts.commit-sha }, status: { $test.status-pushed } => { $test.status }, { $completed-at // "" } { $conclusion // "" }";
            $!github-interface.update-check-run(
                owner => %project-and-repo<project>,
                repo => %project-and-repo<repo>,
                check-run-id => $test.github-id,
                status => $gh-status,
                |($completed-at ?? :$completed-at !! {}),
                |($conclusion ?? :$conclusion !! {}),
                );
        }
        $test.status-pushed = $test.status;
        $test.^save;

        CATCH {
            default {
                error "GitHub: Failure processing status change: " ~ .message ~ .backtrace.Str
            }
        }
    }
}

method !get-pr($ts) {
    return $_ with $ts.pr;
    with $ts.command {
        return $_ with $ts.command.pr;
        return self!get-pr($_) with $ts.command.origin-test-set;
    }
    return Nil;
}

method !determine-source-spec(:$project!, :$git-url!, :$commit-sha! --> SourceSpec) {
    given $project {
        when DB::RAKUDO {
            return SourceSpec.new:
                rakudo-git-url => $git-url,
                rakudo-commit-sha => $commit-sha;
        }
        when DB::NQP {
            return SourceSpec.new:
                nqp-git-url => $git-url,
                nqp-commit-sha => $commit-sha;
        }
        when DB::MOAR {
            return SourceSpec.new:
                moar-git-url => $git-url,
                moar-commit-sha => $commit-sha;
        }
    }
}

method !github-url-to-project-repo($url) {
    if $url ~~ / 'https://github.com/' $<project>=( <-[ / ]>+ ) '/' $<repo>=( <-[ . ]>+ ) '.git' / {
        return {
            project => ~$<project>,
            repo    => ~$<repo>,
        }
    }
    die "GitHub URL couldn't be parsed: $url";
}

method !command-to-enum($text is copy) {
    $text .= lc;
    given $text {
        when "merge-on-success" | "mos" {
            DB::MERGE_ON_SUCCESS
        }
        when "re-test" | "rt" {
            DB::RE_TEST
        }
        default {
            Nil
        }
    }
}

method !repo-to-project-repo($repo) {
    given $repo.lc {
        when "rakudo" { { project => config.projects.rakudo.project, repo => config.projects.rakudo.repo, db-project => DB::RAKUDO } }
        when "nqp" { { project => config.projects.nqp.project, repo => config.projects.nqp.repo, db-project => DB::NQP } }
        when "moarvm" { { project => config.projects.moar.project, repo => config.projects.moar.repo, db-project => DB::MOAR } }
        default       { die "unknown project"; }
    }
}

method !db-project-to-project-repo($db-project) {
    my $repo = do given $db-project {
        when DB::RAKUDO { "rakudo" }
        when DB::NQP { "nqp" }
        when DB::MOAR { "moarvm" }
    }
    self!repo-to-project-repo($repo);
}

method !repo-to-db-project($repo) {
    self!repo-to-project-repo($repo)<db-project>;
}

method tests-queued(@tests) {
    self.process-worklist;
}

method test-status-changed($test) {
    self.process-worklist;
}

method test-set-done($test-set) {
    # GitHub has no concept of a completed check run suite.
    # So we don't need to tell GitHub, that we are done.
    # So there is nothing to do here.
    trace "GitHub: TestSet done: " ~ $test-set.id;
}

method command-accepted($command) {
    my $proj-repo = self!db-project-to-project-repo($command.pr.project);

    $!github-interface.add-issue-comment:
        owner  => $proj-repo<project>,
        repo   => $proj-repo<repo>,
        number => $command.pr.number,
        body   => ($command.command == DB::RE_TEST ?? "Re-testing of this PR started." !!
                   $command.command == DB::MERGE_ON_SUCCESS ?? "I'll merge this PR, should it succeeed." !!
                   "What? I confused myself!");
}
