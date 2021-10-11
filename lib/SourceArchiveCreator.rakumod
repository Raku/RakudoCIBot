use OO::Monitors;

class SourceSpec {
    # A Git SHA-1 is a length 40 hex number
    subset SHA1 of Str where m:i/ [ <[0..9a..f]> ** 40 ] | latest /;

    has Str $.rakudo-git-url = 'https://github.com/rakudo/rakudo.git';
    has SHA1 $.rakudo-commit-sha = 'latest';
    has Str $.nqp-git-url = 'https://github.com/Raku/nqp.git';
    has SHA1 $.nqp-commit-sha = 'latest';
    has Str $.moar-git-url = 'https://github.com/MoarVM/MoarVM.git';
    has SHA1 $.moar-commit-sha = 'latest';
    
    submethod TWEAK() {
        $!rakudo-commit-sha .= uc;
        $!nqp-commit-sha .= uc;
        $!moar-commit-sha .= uc;
    }
}

class X::ArchiveCreationException is Exception {
    has $.command;
    has $.exitcode;
    has $.output;

    multi method message() {
        "Command: '$!command' failed with code: $!exitcode. Output was: '$!output'";
    }

    method gist() {
        "Command: '$!command' failed with code: $!exitcode. Output was: '$!output'";
    }
}

monitor SourceArchiveCreator {

#`[
=head1 Compression algorithms

Some performance measurements for different compression algorithms.

Fresh checkouts of rakudo, nqp, MoarVM with

    tar -c --exclude-vcs --owner=0 --group=0 --numeric-owner -f out.tar MoarVM/ nqp rakudo/

So they don't contain the Git repos. Uncompressed size: 44 MB

=head1 zstd

comp   (zstd -19 zstd.tar)    18.6 s
decomp (zstd -d zstd.tar.zst)  0.09 s
size                           7.0 MB

=head1 xz

comp   (xz -9 xz.tar)    17.6  s
decomp (xz -d xz.tar.xz)  0.54 s
size                      6.3 MB

We'll go with xz for now.
]

has IO::Path $.work-dir  is required where *.d;
has IO::Path $.store-dir is required where *.d;
has $!rakudo-dir = $!work-dir.add('rakudo');
has $!nqp-dir    = $!work-dir.add('nqp');
has $!moar-dir   = $!work-dir.add('MoarVM');

submethod TWEAK() {
    run qw|git clone http://github.com/rakudo/rakudo|, $!rakudo-dir
        if !$!rakudo-dir.e;
    run qw|git clone http://github.com/Raku/nqp|, $!nqp-dir
        if !$!nqp-dir.e;
    run qw|git clone http://github.com/MoarVM/MoarVM|, $!moar-dir
        if !$!moar-dir.e;
}

method !get-path-for-name($name) {
    my $lvl1 = $name.substr(0, 2);
    my $lvl2 = $name.substr(0, 4);
    my $dir = $!store-dir.add($lvl1).add($lvl2);
    $dir.mkdir;
    return $dir.add($name);
}

method create-archive(SourceSpec $source-spec --> Str) {
    sub validate($proc) {
        if $proc.exitcode != 0 {
            X::ArchiveCreationException.new(
                command => $proc.command.join(' '),
                exitcode => $proc.exitcode,
                output   => $proc.out.slurp: :close).throw;
        }
    }

    for $!rakudo-dir, $source-spec.rakudo-git-url, $source-spec.rakudo-commit-sha,
        $!nqp-dir,    $source-spec.nqp-git-url, $source-spec.nqp-commit-sha,
        $!moar-dir,   $source-spec.moar-git-url, $source-spec.moar-commit-sha
        -> $repo-dir, $remote, $commit {

        run(qw|git remote rm foobar|,
            :cwd($repo-dir), :merge).so;

        validate run qw|git remote add foobar|, $remote,
            :cwd($repo-dir), :merge;

        validate run qw|git fetch foobar|,
            :cwd($repo-dir), :merge;

        # TODO no hard coded master branch.
        my $to-use = $commit eq 'latest' ?? 'origin/master' !! $commit;

        validate run qw|git reset --hard|, $to-use,
            :cwd($repo-dir), :merge;
    }

    my $id = $source-spec.rakudo-commit-sha ~ '_' ~
             $source-spec.nqp-commit-sha    ~ '_' ~
             $source-spec.moar-commit-sha;
    my $filepath = self!get-path-for-name: $id ~ '.tar';

    validate run qw|tar -c --exclude-vcs --owner=0 --group=0 --numeric-owner -f|,
        $filepath,
        $!rakudo-dir.relative($!work-dir),
        $!nqp-dir.relative($!work-dir),
        $!moar-dir.relative($!work-dir),
        :cwd($!work-dir), :merge;

    validate run qw|xz -9|, $filepath;

    # OBS needs three separate archives, so prepare those as well.
    my $filepath-base = self!get-path-for-name: $id;

    my $filepath-moar = $filepath-base ~ '-moar.tar';
    validate run qw|tar -c --exclude-vcs --owner=0 --group=0 --numeric-owner -f|,
        $filepath-moar,
        $!moar-dir.relative($!work-dir),
        :cwd($!work-dir), :merge;
    validate run qw|xz -9|, $filepath-moar;

    my $filepath-nqp = $filepath-base ~ '-nqp.tar';
    validate run qw|tar -c --exclude-vcs --owner=0 --group=0 --numeric-owner -f|,
        $filepath-nqp,
        $!nqp-dir.relative($!work-dir),
        :cwd($!work-dir), :merge;
    validate run qw|xz -9|, $filepath-nqp;

    my $filepath-rakudo = $filepath-base ~ '-rakuod.tar';
    validate run qw|tar -c --exclude-vcs --owner=0 --group=0 --numeric-owner -f|,
        $filepath-rakudo,
        $!rakudo-dir.relative($!work-dir),
        :cwd($!work-dir), :merge;
    validate run qw|xz -9|, $filepath-rakudo;


    return $id;
}

multi method get-archive-path($id           --> IO::Path) { self!get-path-for-name: $id ~ '.tar.xz' }
multi method get-archive-path($id, 'moar'   --> IO::Path) { self!get-path-for-name: $id ~ '-moar.tar.xz' }
multi method get-archive-path($id, 'nqp'    --> IO::Path) { self!get-path-for-name: $id ~ '-nqp.tar.xz' }
multi method get-archive-path($id, 'rakudo' --> IO::Path) { self!get-path-for-name: $id ~ '-rakudo.tar.xz' }

}
