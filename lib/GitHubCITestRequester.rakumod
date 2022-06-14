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
    if DB::GitHubPR.^all.grep({
                $_.number eq $pr.number
            }).elems == 0
            && $pr.state == PR_OPEN {
        # Unknown PR, add it!
        info "GitHub: Adding PR: " ~ $pr.number;
        my $db-pr = DB::GitHubPR.^create:
            project      => self!repo-to-db-project($pr.repo),
            number       => $pr.number,
            base-url      => $pr.base-url,
            head-url      => $pr.head-url,
            head-branch  => $pr.head-branch,
            user-url     => $pr.user-url,
            status       => DB::OPEN,
        ;
    }

    self!process-pr-commit-task($pr.commit-task);
    self!process-pr-comment-task($_) for $pr.comments;
}

method !repo-to-db-project($project) {
    $project eq "rakudo"    ?? DB::RAKUDO
    !! $project eq "nqp"    ?? DB::NQP
    !! $project eq "MoarVM" ?? DB::MOAR
    !! die "unknown project";
}

method !process-pr-commit-task(PRCommitTask $commit) {
    my $pr = DB::GitHubPR.^all.first({
                $_.number == $commit.pr-number
                && $_.project == self!repo-to-db-project($commit.repo)
            });
    return unless $pr; # If the PR object isn't there, we'll just pass. Polling will take care of it.

    my $ts = DB::CITestSet.^all.first({
            $_.event-type == DB::PR
            && $_.pr.number == $commit.pr-number
            && $_.project == self!repo-to-db-project($commit.repo)
            && $_.commit-sha eq $commit.commit-sha
    });
    without $ts {
        info "GitHub: Adding PR commit: " ~ $commit.commit-sha;
        DB::CITestSet.^create:
            event-type => DB::PR,
            project    => self!repo-to-db-project($commit.repo),
            git-url    => $pr.head-url,
            commit-sha => $commit.commit-sha,
            user-url   => $commit.user-url,
            :$pr,
            ;
        self.process-worklist;
    }
}

method !process-pr-comment-task(PRCommentTask $comment) {
    # TODO
    info "Adding PR comment: " ~ $comment.created-at;
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

#`[
method new-main-commit(:$git-url!, :$branch!, :$commit-sha!, :$user-url!) {
    my $test-set = DB::CITestSet.^create:
        event-type => DB::MAIN_BRANCH,
        project    => self!url-to-project($git-url),
        :$git-url,
        commit-sha => '0123456789012345678901234567890123456789';
    self.process-worklist;
}

method new-commit-comment(:$repo, :$commit-sha, :$comment-id, :$comment-text, :$user-url) {

}

method new-retest-command(:$project, :$pr-number, :$comment-id, :$user-url) {

}

method !url-to-project($url) {
    return DB::RAKUDO if $url eq 'https://github.com/rakudo/rakudo.git';
    return DB::MOAR   if $url eq 'https://github.com/MoarVM/MoarVM.git';
    return DB::NQP if $url eq 'https://github.com/Raku/nqp.git';
    die "Unknown URL $url seen";
}
]

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
        my %project-and-repo = self!github-url-to-project-repo($ts.pr ?? $ts.pr.base-url
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
