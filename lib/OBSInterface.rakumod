use v6.d;

use Log::Async;
use LibXML;
use Cro::HTTP::Client;
use Base64;

unit class OBSInterface;

has Cro::HTTP::Client $!cro;
has LibXML     $!xml-parser .= new;

has $.apiurl = 'https://api.opensuse.org';
has $.project = "home:patrickbkr:raku-ci";
has Str:D $.user is required;
has Str:D $.password is required;
has $!auth-str;

# API Docs can be found at:
# https://build.opensuse.org/apidocs/index
# For quick access:
# https://libxml-raku.github.io/LibXML-raku/Node


submethod TWEAK() {
    $!auth-str = 'Basic ' ~ encode-base64("$!user:$!password", :str);
    $!cro .= new:
        headers => [
            Accept => 'application/xml',
            Authorization => $!auth-str,
        ];
        #`[
        tls => {
            ssl-key-log-file => 'ssl-key-log-file',
        };
        ]
}

method !req-plain($method, $url-path, :$body-data, :%form-data) {
    my $res;
    if $body-data {
        $res = await $!cro.request: $method, $!apiurl ~ $url-path, body => $body-data;
    }
    elsif %form-data {
        $res = await $!cro.request: $method, $!apiurl ~ $url-path, content-type => 'application/x-www-form-urlencoded', body => %form-data;
    }
    else {
        $res = await $!cro.request: $method, $!apiurl ~ $url-path;
    }
    CATCH {
        when X::Cro::HTTP::Error {
            warn "Hit the X::Cro::HTTP::Error: HTTP request failed: $method $!apiurl$url-path " ~ $_;
            die "HTTP request failed: $method $!apiurl$url-path " ~ $_;
        }
        default {
            warn "Hit some other exception: $method $!apiurl$url-path " ~ $_;
            die "Hit some other exceptionX: $method $!apiurl$url-path " ~ $_;
        }
    }
    return await $res.body;
}

method !req-dom($method, $url-path, :$body-data, :%form-data) {
    my $content = self!req-plain($method, $url-path, :$body-data, :%form-data);
    my $d = $!xml-parser.parse: $content;
    $d;
}

method server-revision() {
    my $dom = self!req-dom: 'GET', '/about';
    $dom.findvalue('/about/revision/text()');
}

method upload-file($package, $filename, :$path, :$blob) {
    my $data = $path ?? $path.IO.slurp(:bin) !! $blob;
    self!req-dom: 'PUT', "/source/$!project/$package/$filename?rev=upload", body-data => $data;
}

method delete-file($package, $filename) {
    self!req-dom: 'DELETE', "/source/$!project/$package/$filename";
}

method commit($package) {
    self!req-dom: 'POST', "/source/$!project/$package?cmd=commit";
}

class OBSResult {
    has $.project;
    has $.repository;
    has $.arch;
    has $.code;
    has $.state;
    has %.status;
}
method builds($package?) {
    my $dom = self!req-dom: 'GET', "/build/$!project/_result" ~ ($package ?? "?package=$package" !! "");
    my @results;
    for $dom.findnodes("/resultlist/result") -> $res {
        @results.push: OBSResult.new(
            project    => $res.getAttribute("project"),
            repository => $res.getAttribute("repository"),
            arch       => $res.getAttribute("arch"),
            code       => $res.getAttribute("code"),
            state      => $res.getAttribute("state"),
            status     => %($res.findnodes("status").map({ $_.getAttribute("package") => $_.getAttribute("code") })),
        );
    }
    return @results;
}

method history($package?) {
    self!req-dom: 'GET', "/source/$!project/$package/_history";
}

class OBSSource {
    has $.name;
    has $.md5;
    has $.size;
    has $.mtime;
}
method sources($package) {
    my $dom = self!req-dom: 'GET', "/source/$!project/$package";
    my @sources;
    for $dom.findnodes('/directory/entry') -> $entr {
        @sources.push: OBSSource.new(
            name  => $entr.getAttribute("name"),
            md5   => $entr.getAttribute("md5"),
            size  => $entr.getAttribute("size"),
            mtime => $entr.getAttribute("mtime"),
        );
    }
    return @sources;
}

method build-log($package, $arch, $repository) {
    my $url = $!apiurl ~ "/build/$!project/$repository/$arch/$package/_log";
    my $res = await $!cro.get: $url;
    CATCH {
        when X::Cro::HTTP::Error {
			if .response.status == 404 {
                return Nil;
			}
			else {
				die "OBS build-log request failed: $url" ~ $_;
			}
        }
    }
    return await $res.body;
}

method set-test-disabled($package, $arch, $repository) {
    self!req-plain: 'POST', "/source/$!project/$package?cmd=set_flag", form-data => {
        flag => "build",
        status => "disable",
        :$repository,
        :$arch,
    }
}

method enable-all-tests($package) {
    #`[
    # This simpler implementation seems to have no effect on OBS.
    # So we'll have to go with the more complex approach below.
    self!req-plain: 'POST', "/source/$!project/$package?cmd=set_flag", form-data => {
        flag => "build",
        status => "enable",
    };
    ]
    my @builds = self.builds();
    for @builds -> $b {
        if $b.status{$package} eq "disabled" {
            self!req-plain: 'POST', "/source/$!project/$package?cmd=set_flag", form-data => {
                flag => "build",
                status => "enable",
                repository => $b.repository,
                arch => $b.arch,
            };
        }
    }
}

