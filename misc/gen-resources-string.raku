#!/usr/bin/env raku

my @entries;

sub MAIN($indent = 8) {
    my $base = $*PROGRAM.parent.parent.add("resources");
    my @stack = $base;
    my @entries = gather while @stack {
        with @stack.pop {
            when :d { @stack.append: .dir }
            when :f { take "\"{$_.relative($base)}\"" }
        }
    }
    say @entries.join(",\n" ~ " " x $indent);
}
