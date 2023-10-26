unit class RakudoCIBot;

use Cro::HTTP::Log::File;
use Cro::HTTP::Server;
use Log::Async;

use Config;
use Red:api<2>;
use FlapperDetector;
use GitHubInterface;
use GitHubCITestRequester;
use CITestSetManager;
use OBSInterface;
use OBS;
use TestBackend;
use SourceArchiveCreator;
use Routes;
use DB;

has FlapperDetector $!flapper-detector;
has SourceArchiveCreator $!source-archive-creator;
has GitHubInterface $!github-interface;
has GitHubCITestRequester $!requester;
has CITestSetManager $!testset-manager;
has OBSInterface $!obs-interface;
has OBS $!obs;
has Promise $!running;
has TestBackend $!test-backend;

submethod TWEAK() {
    set-config($*PROGRAM.parent.add(%*ENV<CONFIG> // "config-prod.yml"));

    logger.send-to($*OUT, :level(* >= Loglevels::{config.log-level}));

    red-defaults('Pg', |%(
        config.db,
        host => config.db<host> || Str
    ));
    #red-defaults('SQLite', database => 'test.sqlite3');


    #DB::drop-schema;
    #DB::create-schema;

    my $gh-pem = %*ENV<GITHUB_PEM> ?? %*ENV<GITHUB_PEM> !!
                 config.github-app-key-file ?? config.github-app-key-file.IO.slurp !!
                 die 'Neither GITHUB_PEM environment variable nor config entry github-app-key-file given.';

    $!flapper-detector .= new;

    $!source-archive-creator .= new:
        work-dir => config.sac-work-dir.IO,
        store-dir => config.sac-store-dir.IO,
    ;
    $!testset-manager .= new:
        :$!source-archive-creator,
        :$!flapper-detector,
    ;
    $!requester .= new:
        :$!testset-manager,
    ;
    $!github-interface .= new:
        app-id => config.github-app-id,
        client-id => config.github-client-id,
        client-secret => config.github-client-secret,
        pem => $gh-pem,
        processor => $!requester,
        redirect-url => config.hook-url ~ "gh-oauth-callback",
    ;
    $!requester.github-interface = $!github-interface;
    $!testset-manager.register-status-listener($!requester);
    if %*ENV<TEST_BACKEND> {
        $!test-backend .= new:
            :$!testset-manager,
        ;
        $!testset-manager.register-test-set-listener($!test-backend);
    }
    else {
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
}

method start() {
    die "Already ticking" if $!running;

    $!running = Promise.new();
    start react {
        whenever Supply.interval(config.testset-manager-interval) {
            #my $*RED-DEBUG = True;
            $!testset-manager.process-worklist;
        }
        whenever Supply.interval(config.github-requester-interval) {
            #my $*RED-DEBUG = True;
            $!requester.poll-for-changes;
            $!requester.process-worklist;
        }
        if %*ENV<TEST_BACKEND> {
            whenever Supply.interval(5) {
                $!test-backend.process-worklist;
            }
        }
        else {
            whenever Supply.interval(config.obs-interval) {
                #my $*RED-DEBUG = True;
                $!obs.process-worklist;
            }
        }
        whenever Supply.interval(config.flapper-list-interval) {
            $!flapper-detector.refresh-flapper-list;
        }
        whenever Supply.interval(config.sac-cleanup-interval) {
            $!source-archive-creator.clean-old-archives;
        }
        whenever $!running {
            done()
        }
    }

    my Cro::Service $http = Cro::HTTP::Server.new(
        http => <1.1>,
        host => config.web-host,
        port => config.web-port,
        application => routes($!testset-manager, $!source-archive-creator, $!github-interface, $!obs),
        after => [
            Cro::HTTP::Log::File.new(logs => $*OUT, errors => $*ERR)
        ]
    );

    $http.start;

    say "Listening at http://{config.web-host}:{config.web-port}";
}

method stop() {
    $!running.keep;
    $!running = Nil;
}
