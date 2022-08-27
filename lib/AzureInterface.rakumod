use v6.d;

use Log::Async;
use Cro::HTTP::Client;
use Base64;

unit class AzureInterface;

has Cro::HTTP::Client $!cro;

#TODO put into the configuration.
#TODO Invalidates on 18.8.2022, maybe change to OAuth?
constant $pat = 'nfq2ua64vjfimvrchh7rtzurfiutep5wmmkqftojz6fgxqeyfboq';
constant $rakudo-pipeline = 1;
constant $nqp-pipeline = 2;
constant $moar-pipeline = 3;
has $!auth-str;


# API Docs can be found at:
# https://docs.microsoft.com/en-us/rest/api/azure/devops/?view=azure-devops-rest-7.1


submethod TWEAK() {
    $!auth-str = 'Basic ' ~ encode-base64(":$pat", :str);
    $!cro .= new:
        headers => [
            Accept => 'application/json',
            Authorization => $!auth-str,
        ],
        tls => {
            ssl-key-log-file => 'ssl-key-log-file',
        };
}

method !create-req-uri($fragment) {
    # TODO put this in Config
    my $api-sep = $fragment.contains('?') ?? '&' !! '?';
    return 'https://dev.azure.com/patrickboeker/Precomp-Builds/_apis/' ~ $fragment ~ $api-sep ~ 'api-version=7.1-preview.1';
}

method !req($method, $url-path, :$body-blob, :%body-data) {
    say self!create-req-uri($url-path);
    my $res;
    if $body-blob {
        $res = await $!cro.request: $method, self!create-req-uri($url-path), body => $body-blob;
    }
    elsif %body-data {
        $res = await $!cro.request: $method, self!create-req-uri($url-path), content-type => 'application/json', body => %body-data;
    }
    else {
        $res = await $!cro.request: $method, self!create-req-uri($url-path);
    }
    CATCH {
        when X::Cro::HTTP::Error {
                die "HTTP request failed: $method " ~ self!create-req-uri($url-path) ~ " " ~ $_;
        }
    }
    return await $res.body;
}

method !proj-to-pipeline(Str:D $proj) {
    given $proj {
        when 'rakudo' { return $rakudo-pipeline }
        when 'nqp'    { return $nqp-pipeline }
        when 'moar'   { return $moar-pipeline }
        default       { die "Unknown project given: " ~ $proj }
    }
}

method get-pipeline-runs($project) {
    self!req: 'GET', 'pipelines/' ~ self!proj-to-pipeline($project) ~ '/runs';
}

method run-pipeline($source-url, $project) {
    my $data = self!req: 'POST', 'pipelines/' ~ self!proj-to-pipeline($project) ~ '/runs', body-data => {
        variables => {
            SOURCES_URL => {
                :!is_secret,
                value => $source-url,
            }
        },
    };
    return $data<id>;
}
