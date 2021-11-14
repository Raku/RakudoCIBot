#!/usr/bin/env raku

use RakudoCIBot;

my RakudoCIBot $bot .= new;
$bot.start();

say 'Hello from the RakudoCIBot!';
say '';

react {
    whenever signal(SIGINT) {
        say "Shutting down...";
        $bot.stop;
        done;
    }
}
