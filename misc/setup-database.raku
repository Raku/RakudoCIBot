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
    DB::create-db();
    say "Database schema set up.";
}
