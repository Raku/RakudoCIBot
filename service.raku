#!/usr/bin/env raku

use Cro::HTTP::Log::File;
use Cro::HTTP::Server;
use Routes;
use RakuCIBot;

my RakuCIBot $bot .= new;
$bot.start-ticking();

say 'Hello from the RakuCIBot!';
say '';

#`{
my $hook-host = %*ENV<RCB_HOOK_HOST> || '0.0.0.0';
my $hook-port = %*ENV<RCB_HOOK_PORT> || 12345;
my $github-pat = %*ENV<RCB_GITHUB_PAT> || '';


my Cro::Service $http = Cro::HTTP::Server.new(
    http => <1.1>,
    host => $hook-host,
    port => $hook-port,
    application => routes(),
    after => [
        Cro::HTTP::Log::File.new(logs => $*OUT, errors => $*ERR)
    ]
);

$http.start;

say "Hook listener is listening at http://$hook-host:$hook-port";
}

react {
    whenever signal(SIGINT) {
        say "Shutting down...";
        #$http.stop;
        done;
    }
}
