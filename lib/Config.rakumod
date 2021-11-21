use YAMLish;

class Config {
    has %.db;

    has $.github-app-id;
    has $.github-app-key-file;
    has %.projects;

    has $.obs-user;
    has $.obs-password;

    has $.obs-check-duration;
    has $.obs-min-run-duration;
    has @.obs-packages;

    #| How many latest-changes-PullRequests the GitHub polling logic should retrieve.
    has $.github-pullrequest-check-count;

    has $.sac-work-dir;
    has $.sac-store-dir;
    has $.obs-work-dir;

    has $.testset-manager-interval;
    has $.github-requester-interval;
    has $.obs-interval;

    has $.web-host;
    has $.web-port;

    has $.log-level;

    method from-config(%config) {
        Config.new:
            db => %config<db>,

            github-app-id       => %config<github-app-id>,
            github-app-key-file => %config<github-app-key-file>,
            projects            => %config<projects>,

            obs-user     => %config<obs-user>,
            obs-password => %config<obs-password>,

            obs-check-duration   => %config<obs-check-duration>,
            obs-min-run-duration => %config<obs-min-run-duration>,
            obs-packages         => |%config<obs-packages>,

            github-pullrequest-check-count => %config<github-pullrequest-check-count>,

            sac-work-dir  => %config<sac-work-dir>,
            sac-store-dir => %config<sac-store-dir>,
            obs-work-dir  => %config<obs-work-dir>,

            testset-manager-interval  => %config<testset-manager-interval>,
            github-requester-interval => %config<github-requester-interval>,
            obs-interval              => %config<obs-interval>,

            web-host => %config<web-host>,
            web-port => %config<web-port>,

            log-level => %config<log-level>,
        ;
    }
}

my Config $config;
multi set-config(Config $c) is export {
    $config = $c
}

multi set-config(IO::Path $yaml-file) is export {
    set-config(Config.from-config(load-yaml($yaml-file.slurp)));
}

sub config(--> Config) is export {
    $config;
}
