use v6.d;

use Log::Async;
use Cro::HTTP::Client;
use Base64;

unit class AzureInterface;

has Cro::HTTP::Client $!cro;
has Cro::HTTP::Client $!cro-log;

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
    $!cro-log .= new:
        headers => [
            Accept => 'text/plain',
        ];
}

method !create-req-uri($fragment) {
    # TODO put this in Config
    my $api-sep = $fragment.contains('?') ?? '&' !! '?';
    return 'https://dev.azure.com/patrickboeker/Precomp-Builds/_apis/' ~ $fragment ~ $api-sep ~ 'api-version=7.0';
}

method !req($method, $url-path, :$body-blob, :%body-data) {
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

method !proj-to-pipeline(DB::Project $proj) {
    given $proj {
        when DB::RAKUDO { return $rakudo-pipeline }
        when DB::NQP    { return $nqp-pipeline }
        when DB::MOAR   { return $moar-pipeline }
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
    return $data<id>.Int;
}

enum Result <abandoned canceled failed skipped succeeded succeededWithIssues>;
enum State <completed inProgress pending>;

class Job {
    has $.id;
    has $.name;
    has $.start-time;
    has $.finish-time;
    has $.state;
    has $.result;
    has $.log-url;
}

method get-run-data($run-id) {
    #https://docs.microsoft.com/en-us/rest/api/azure/devops/build/timeline/get?view=azure-devops-rest-7.1
    # The following call (without a trailing timelineId is undocumented, but seems to be the only
    # way to reach the individual Jobs of a run.
    my $data = self!req: 'GET', 'build/builds/' ~ $run-id ~ '/timeline';
    my @jobs = $data<records><>.grep(*<type> eq "Job");
    @jobs .= map: {
        Job.new:
            id => $_<id>,
            name => $_<name>,
            start-time => $_<startTime>,
            finish-time => $_<finishTime>,
            state => State::{$_<state>},
            result => Result::{$_<result>},
            log-url => $_<log><url>,
    };
    return @jobs;
}

method get-log($job) {
    CATCH {
        when X::Cro::HTTP::Error {
            die "Retrieving log failed: " ~ $_<log><url> ~ " " ~ $_;
        }
    }
    my $log-req = await $!cro-log.get: $job.log-url;
    return await $log-req.body;
}
