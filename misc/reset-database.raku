#!/usr/bin/env raku

use Config;
use Red:api<2>;
use DB;

sub MAIN($config) {
    set-config $config.IO;

    red-defaults('Pg', |%(
        config.db,
        host => config.db<host> || Str
    ));

    DB::CITest.^delete;
    DB::CIPlatformTestSet.^delete;
    DB::CITestSet.^delete;
    DB::GitHubPR.^delete;
    DB::Command.^delete;
    DB::GitHubPullState.^delete;

    #`[
    for DB::GitHubPullState.^all {
        $_.last-default-branch-cursor = Str;
        $_.last-pr-cursor = Str;
        $_.^save;
    }
    ]
    say "Database is now reset.";
}
