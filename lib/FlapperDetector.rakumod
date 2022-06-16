use Log::Async;
use SerialDedup;
use Config;
use Cro::HTTP::Client;
use YAMLish;

unit class FlapperDetector;

my class Flapper {
    has $.name;
    has $.matcher;
}

has @!flappers;
has Cro::HTTP::Client $!cro;

submethod TWEAK() {
    $!cro .= new;
}

# Returns flapper name if flapper is found,
# Str otherwise
# TODO: Log the flapper count
method is-flapper($log --> Str) {
    for @!flappers -> $flapper {
        if $log ~~ m:g/ <{$flapper.matcher}> / {
            return $flapper.name;
        }
    }
}

method refresh-flapper-list() is serial-dedup {
    trace "Refreshing flapper list";
    CATCH {
        when X::Cro::HTTP::Error {
            error "FlapperDetector: Failed to retrieve flapper list: " ~ config.flapper-list-url ~ ". HTTP failure: " ~ $_;
        }
        default {
            error "FlapperDetector: Failed to process flapper list: " ~ config.flapper-list-url ~ ". Failure: " ~ $_;
        }
    }
    my $res = await $!cro.get: config.flapper-list-url;
    my $body = await $res.body-text;
    my @yml-list = load-yaml($body);
    my @flappers = @yml-list.map: {
        Flapper.new:
            name => $_<name>,
            matcher => $_<matcher>;
    };
    @!flappers = @flappers;
}
