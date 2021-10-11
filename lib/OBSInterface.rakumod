use v6.d;

use LibXML;
use Cro::HTTP::Client;
use Base64;

unit class OBSInterface;

has Cro::HTTP::Client $!cro .= new:
    headers => [
        Accept => 'application/xml',
        Authorization => $!auth-str,
    ];
has LibXML     $!xml-parser .= new;

has $.apiurl = 'https://api.opensuse.org';
has $.project = "home:patrickbkr:raku-ci";
has Str:D $.user is required;
has Str:D $.password is required;
has $!auth-str;

submethod TWEAK() {
    $!auth-str = 'Basic ' ~ encode-base64("$!user:$!password", :str);
}

method !req-plain($method, $url-path, $body-data?) {
    my $res;
    if $body-data {
        $res = $!cro.request: $method, $!apiurl ~ $url-path, content => $body-data;
    }
    else {
        $res = $!cro.request: $method, $!apiurl ~ $url-path;
    }
    die 'HTTP request failed.' unless $res<success>;
    return $res<content>;
}

method !req-dom($method, $url-path, $body-data?) {
    my $content = self!req-plain($method, $url-path, $body-data);
    my $d = $!xml-parser.parse: $content;
    $d;
}

method server-revision() {
    my $dom = self!req-dom: 'GET', '/about';
    $dom.findvalue('/about/revision/text()');
}

method upload-file($package, $filename, :$path, :$blob) {
    my $data = $path ?? $path.IO.slurp(:bin) !! $blob;
    self!req-dom: 'PUT', "/source/$!project/$package/$filename?rev=upload", $data;
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
    my $dom = self!req-dom: 'GET', "/build/$!project/_result" ~ ($package ?? "package=$package" !! "");
    my @results;
    for $dom.findvalue("/resultlist/result") -> $res {
        @results.push: OBSResult.new(
            project    => $res.getAttribute("project"),
            repository => $res.getAttribute("repository"),
            arch       => $res.getAttribute("arch"),
            code       => $res.getAttribute("code"),
            state      => $res.getAttribute("state"),
            status     => %($res.findvalue("/status").map({ $_.getAttribute("package") => $_.getAttribute("code") })),
        );
    }
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
    for $dom.findvalue('/directory/entry') -> $entr {
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
    self!req-plain: 'GET', "/build/$!project/$repository/$arch/$package/_log";
}

#POST /source/<project>/<package>?cmd=commit

#POST /source/<project>/<package>?deleteuploadrev

#PUT /source/<project>/<package>/<filename>

#DELETE /source/<project>/<package>/<filename>

