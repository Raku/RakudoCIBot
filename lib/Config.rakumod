unit module Config;

our %projects =
    rakudo => {
        project => "rakudo",
        repo    => "rakudo",
        slug    => "rakudo/rakudo",
    },
    nqp => {
        project => "Raku",
        repo => "nqp",
        slug => "Raku/nqp",
    },
    moar => {
        project => "MoarVM",
        repo    => "MoarVM",
        slug    => "MoarVM/MoarVM",
    },
;

our $obs-check-duration = 5 * 60;
our $obs-min-run-duration = 5 * 60;
our @obs-packages = < moarvm nqp-moarvm rakudo-moarvm >;

#| How many latest-changes-PullRequests the GitHub polling logic should retrieve.
our $github-pullrequest-check-count = 15;

our $sac-work-dir = $*PROGRAM.parent.add("work/sac-work").IO;
our $sac-store-dir = $*PROGRAM.parent.add("work/sac-store").IO;
our $obs-work-dir = $*PROGRAM.parent.add("work/obs-work").IO;

our $testset-manager-interval = 5 * 60;
our $github-requester-interval = 5 * 60;
our $obs-interval = 5 * 60;

