unit class RakuCIBot;

use Config;
use Red::Operators:api<2>;
use GitHubInterface;
use GitHubCITestRequester;
use CITestSetManager;
use OBSInterface;
use OBS;
use SourceArchiveCreator;

has SourceArchiveCreator $!source-archive-creator;
has GitHubInterface $!github-interface;
has GitHubCITestRequester $!requester;
has CITestSetManager $!testset-manager;
has OBSInterface $!obs-interface;
has OBS $!obs;
has Promise $!running;

submethod TWEAK() {
    set-config($*PROGRAM.parent.add(%*ENV<CONFIG> // "config-prod.yml"));

    red-defaults('Pg', |%(
        config.db,
        host => config.db<host> || Str
    ));

    my $gh-pem = %*ENV<GITHUB_PEM> ?? %*ENV<GITHUB_PEM> !!
                 config.github-app-key-file ?? config.github-app-key-file.IO.slurp !!
                 die 'Neither GITHUB_PEM environment variable nor config entry github-app-key-file given.';

    $!source-archive-creator .= new:
        work-dir => config.sac-work-dir.IO,
        store-dir => config.sac-store-dir.IO,
    ;
    $!testset-manager .= new:
        :$!source-archive-creator,
    ;
    $!requester .= new:
        :$!testset-manager,
    ;
    $!github-interface .= new:
        app-id => config.github-app-id,
        pem => $gh-pem,
        processor => $!requester,
    ;
    $!requester.github-interface = $!github-interface;
    $!testset-manager.register-status-listener($!requester);
    $!obs-interface .= new:
        user     => config.obs-user,
        password => config.obs-password,
    ;
    $!obs .= new:
        :$!source-archive-creator,
        work-dir => config.obs-work-dir.IO,
        interface => $!obs-interface,
        :$!testset-manager,
    ;
    $!testset-manager.register-test-set-listener($!obs);
}

method start-ticking() {
    die "Already ticking" if $!running;

    $!running = Promise.new();
    start react {
        whenever Supply.interval(config.testset-manager-interval) {
            $!testset-manager.process-worklist;
        }
        whenever Supply.interval(config.github-requester-interval) {
            $!requester.process-worklist;
        }
        whenever Supply.interval(config.obs-interval) {
            $!obs.process-worklist;
        }
        whenever $!running {
            done()
        }
    }
}

method stop-ticking() {
    $!running.keep;
    $!running = Nil;
}
