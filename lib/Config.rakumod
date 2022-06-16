use YAMLish;

class ConfigProject {
    has $.project;
    has $.repo;
    has $.slug;
    has $.repo-url;
    has $.install-id;

    method from-config(%config) {
        ConfigProject.new:
            project    => %config<project>,
            repo       => %config<repo>,
            slug       => %config<project> ~ "/" ~ %config<repo>,
            repo-url   => %config<repo-url>,
            install-id => %config<install-id>,
        ;
    }
}

class ConfigProjects {
    has $.rakudo is required;
    has $.nqp is required;
    has $.moar is required;
}

class Config {
    has %.db;

    has $.github-app-id;
    has $.github-app-key-file;
    has $.projects;

    has $.obs-user;
    has $.obs-password;

    has $.obs-check-duration;
    has $.obs-min-run-duration;
    has @.obs-packages;

    #| How many latest-changes-PullRequests the GitHub polling logic should retrieve.
    has $.github-check-batch-count;
    has $.github-max-source-retrieval-retries;

    has $.sac-work-dir;
    has $.sac-store-dir;
    has $.obs-work-dir;

    has $.flapper-list-url;

    has $.testset-manager-interval;
    has $.github-requester-interval;
    has $.obs-interval;
    has $.flapper-list-interval;

    has $.web-host;
    has $.web-port;

    has $.log-level;

    method from-config(%config) {
        Config.new:
            db => %config<db>,

            github-app-id       => %config<github-app-id>,
            github-app-key-file => %config<github-app-key-file>,
            projects            => ConfigProjects.new(
                                       rakudo => ConfigProject.from-config(%config<projects><rakudo>),
                                       nqp    => ConfigProject.from-config(%config<projects><nqp>),
                                       moar   => ConfigProject.from-config(%config<projects><moar>),
                                   ),

            obs-user     => %config<obs-user>,
            obs-password => %config<obs-password>,

            obs-check-duration   => %config<obs-check-duration>,
            obs-min-run-duration => %config<obs-min-run-duration>,
            obs-packages         => |%config<obs-packages>,

            github-check-batch-count            => %config<github-check-batch-count>,
            github-max-source-retrieval-retries => %config<github-max-source-retrieval-retries>,

            sac-work-dir  => %config<sac-work-dir>,
            sac-store-dir => %config<sac-store-dir>,
            obs-work-dir  => %config<obs-work-dir>,

            flapper-list-url => %config<flapper-list-url>,

            testset-manager-interval  => %config<testset-manager-interval>,
            github-requester-interval => %config<github-requester-interval>,
            obs-interval              => %config<obs-interval>,
            flapper-list-interval => %config<flapper-list-interval>,

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
