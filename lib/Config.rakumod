unit module Config;

our $github-app-id = "87729";
#`[
our %projects =
    rakudo => {
        project => "rakudo",
        repo    => "rakudo",
        slug    => "rakudo/rakudo",
        install-id => 20243470,
    },
    nqp => {
        project => "Raku",
        repo => "nqp",
        slug => "Raku/nqp",
        install-id => 20243470,
    },
    moar => {
        project => "MoarVM",
        repo    => "MoarVM",
        slug    => "MoarVM/MoarVM",
        install-id => 20243470,
    },
;
]
our %projects =
    rakudo => {
        project => "patrickbkr",
        repo    => "rakudo",
        slug    => "patrickbkr/rakudo",
        install-id => 20243470,
    },
    nqp => {
        project => "patrickbkr",
        repo => "nqp",
        slug => "patrickbkr/nqp",
        install-id => 20243470,
    },
    moar => {
        project => "patrickbkr",
        repo    => "MoarVM",
        slug    => "patrickbkr/MoarVM",
        install-id => 20243470,
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

