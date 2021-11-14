#!/usr/bin/env raku

use WebService::GitHub::AppAuth;
use Config;

sub MAIN($config) {
    set-config $config.IO;

    my WebService::GitHub::AppAuth $ghaa .= new(app-id => config.github-app-id, pem-file => config.github-app-key-file.IO);

    my @installs = $ghaa.list-installations();
    for @installs {
        say qq:to/END/;
            ID: $_<id>
                login: $_<account><login>
                created at: $_<created_at>
            END
    }
}

