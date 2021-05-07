unit class SourceArchiveCreator;

class SourceSpec {
    has $.rakudo-repo;
    has $.rakudo-commit-sha;
    has $.nqp-repo;
    has $.nqp-commit-sha;
    has $.moar-repo;
    has $.moar-commit-sha;
}

has IO::Path $.repo-store is required where *.d;
has $!rakudo-dir = $!repo-store.add('rakudo');
has $!nqp-dir    = $!repo-store.add('nqp');
has $!moar-dir   = $!repo-store.add('MoarVM');

submethod TWEAK() {
    shell "git clone http://github.com/rakudo/rakudo " ~ $!rakudo-dir
        if !$!rakudo-dir.e;
    shell "git clone http://github.com/Raku/nqp " ~ $!nqp-dir
        if !$!nqp-dir.e;
    shell "git clone http://github.com/MoarVM/MoarVM " ~ $!moar-dir
        if !$!moar-dir.e;
}

method create-archive(SourceSpec $source-spec --> Int) {

}
