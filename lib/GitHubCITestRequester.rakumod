unit class GitHubCITestRequester;

use DB;
use Red::Operators:api<2>;
use SerialDedup;
use SourceArchiveCreator;
use CITestSetManager;
use GitHubInterface;

has CITestSetManager $.testset-manager is required;
has GitHubInterface $.github-interface is required;

method new-pr(:$pr-number, :$user-url, :$body, :$from-repo, :$from-branch, :$to-repo, :$to-branch) {

}

method new-pr-comment(:$repo, :$pr-number, :$comment-id, :$comment-text, :$user-url) {

}

method new-pr-commit(:$repo, :$branch, :$project, :$pr-number, :$commit-sha, :$user-url) {
    my $pr = DB::PR.^load(number => $pr-number);
    return unless $pr; # If the PR object isn't there, we'll just pass. Polling will take care of it.

    my $test-set = DB::CITestSet.^create:
        event-type => DB::PR,
        :$project,
        :$repo,
        commit-sha => '0123456789012345678901234567890123456789',
        :$pr;
    self.process-worklist;
}

method new-main-commit(:$repo!, :$branch!, :$commit-sha!, :$user-url!) {
    my $test-set = DB::CITestSet.^create:
        event-type => DB::MAIN_BRANCH,
        project    => self!repo-to-project($repo),
        :$repo,
        commit-sha => '0123456789012345678901234567890123456789';
    self.process-worklist;
}

method new-commit-comment(:$repo, :$commit-sha, :$comment-id, :$comment-text, :$user-url) {

}

method new-retest-command(:$project, :$pr-number, :$comment-id, :$user-url) {

}

method !repo-to-project($repo) {
    return DB::RAKUDO if $repo eq 'rakudo/rakudo';
    return DB::MOAR   if $repo eq 'MoarVM/MoarVM';
    return DB::NQP if $repo eq 'Raku/nqp';
    die "Unknown repo $repo seen";
}

method process-worklist() is serial-dedup {
    for DB::CITestSet.^all.grep(*.status ⊂ [DB::NEW]) -> $test-set {
        my $source-spec = self!determine-source-spec(
            project => $test-set.project,
            repo    => $test-set.repo,
            commit-sha => $test-set.commit-sha,
        );
        $!testset-manager.add-test-set(:$test-set, :$source-spec);
    }
}

method !determine-source-spec(:$project, :$repo, :$commit-sha --> SourceSpec) {
    given $project {
        when DB::RAKUDO {
            SourceSpec.new:
                rakudo-repo => $repo,
                rakudo-commit => $commit-sha;
        }
        when DB::NQP {
            SourceSpec.new:
                nqp-repo => $repo,
                nqp-commit => $commit-sha;
        }
        when DB::MOAR {
            SourceSpec.new:
                moar-repo => $repo,
                moar-commit => $commit-sha;
        }
    }
}
