unit class RakuCIBot;

use Config;
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

submethod TWEAK() {
    die 'set GITHUB_ACCESS_TOKEN environment variable' unless %*ENV<GITHUB_ACCESS_TOKEN>;
    die 'set OBS_USER environment variable'            unless %*ENV<OBS_USER>;
    die 'set OBS_PASSWORD environment variable'        unless %*ENV<OBS_PASSWORD>;

    $!source-archive-creator .= new:
        work-dir => $Config::sac-work-dir,
        store-dir => $Config::sac-store-dir,
    ;
    $!testset-manager .= new:
        :$!source-archive-creator,
    ;
    $!requester .= new:
        :$!testset-manager,
    ;
    $!github-interface .= new:
        pat => %*ENV<GITHUB_ACCESS_TOKEN>,
        processor => $!requester,
    ;
    $!requester.github-interface = $!github-interface;
    $!obs-interface .= new:
        user     => %*ENV<OBS_USER>,
        password => %*ENV<OBS_PASSWORD>,
    ;
    $!obs .= new:
        :$!source-archive-creator,
        work-dir => $Config::obs-work-dir,
        interface => $!obs-interface,
        :$!testset-manager,
    ;
}

method start-ticking() {
    Supply.interval($Config::testset-manager-interval).tap: {
        $!testset-manager.process-worklist;
    }
    Supply.interval($Config::github-requester-interval).tap: {
        $!github-interface.process-worklist;
    }
    Supply.interval($Config::obs-interval).tap: {
        $!obs.process-worklist;
    }
}
