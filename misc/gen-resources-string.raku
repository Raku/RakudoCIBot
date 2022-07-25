#!/usr/bin/env raku

my @entries;
my @ignore = <.swp>;

sub MAIN($indent = 0) {
    my $base = $*PROGRAM.parent.parent.add("resources");
    my @stack = $base;
    my @entries = gather while @stack {
        with @stack.pop {
            when :d { @stack.append: .dir }
            when :f {
                my $entry = $_;
                if [&&] @ignore.map({!$entry.ends-with($_)}) {
                    take "\"{$_.relative($base)}\""
                }
            }
        }
    }
    say @entries.join(",\n" ~ " " x $indent);
}
