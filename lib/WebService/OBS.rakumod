use v6.d;

use LibXML;
use HTTP::Tiny;
use Base64;

unit class WebService::OBS;

has HTTP::Tiny $!ht         .= new;
has LibXML     $!xml-parser .= new;

has $.apiurl = 'https://api.opensuse.org';
has Str:D $.user is required;
has Str:D $.password is required;
has $!auth-str;

submethod TWEAK() {
    $!auth-str = 'Basic ' ~ encode-base64("$!user:$!password", :str);
}

method !req-dom($url-path) {
    my $res = $!ht.get: $!apiurl ~ $url-path, headers => {
        Accept => 'application/xml',
        Authorization => $!auth-str,
    };
    die 'HTTP request failed.' unless $res<success>;
    $!xml-parser.parse: $res<content>;
}

method server-revision() {
    my $dom = self!req-dom: '/about';
    $dom.findvalue('/about/revision/text()');
}

#POST /source/<project>/<package>?cmd=commit

#POST /source/<project>/<package>?deleteuploadrev

#PUT /source/<project>/<package>/<filename>

#DELETE /source/<project>/<package>/<filename>


