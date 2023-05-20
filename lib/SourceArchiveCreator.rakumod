use Log::Async;
use OO::Monitors;
use Log::Async;
use DB;
use Config;

class X::ArchiveCreationException is Exception {
}

class X::ArchiveTextCreationException is X::ArchiveCreationException {
    has $.text;

    multi method message() {
        $!text;
    }

    method gist() {
        $!text;
    }
}

class X::ArchiveCommandCreationException is X::ArchiveCreationException {
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

class SourceArchiveCreator {

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

constant $ext = '.tar.xz';

has IO::Path $.work-dir  is required where *.d;
has IO::Path $.store-dir is required where *.d;
has $!rakudo-dir = $!work-dir.add('rakudo');
has $!nqp-dir    = $!work-dir.add('nqp');
has $!moar-dir   = $!work-dir.add('MoarVM');
has $!ref-dir    = $!work-dir.add('references');

has Lock $!store-lock .= new;

submethod TWEAK() {
    run qw|git clone|, config.projects.rakudo.repo-url, $!rakudo-dir
        if !$!rakudo-dir.e;
    run qw|git clone|, config.projects.nqp.repo-url, $!nqp-dir
        if !$!nqp-dir.e;
    run qw|git clone|, config.projects.moar.repo-url, $!moar-dir
        if !$!moar-dir.e;
    $!ref-dir.mkdir unless $!ref-dir.d;
}

method !get-path-for-name($name, :$create-dirs) {
    my $lvl1 = $name.substr(0, 2);
    my $lvl2 = $name.substr(0, 4);
    my $dir = $!store-dir.add($lvl1).add($lvl2);
    $dir.mkdir;
    return $dir.add($name);
}

method create-archive(DB::CITestSet $test-set) {
    my SourceSpec $source-spec = $test-set.source-spec;

    debug "SourceArchiveCreator: starting creation: " ~ $source-spec.raku;

    $!store-lock.protect: {
        sub validate($proc) {
            if $proc.exitcode != 0 {
                X::ArchiveCommandCreationException.new(
                    command => $proc.command.join(' '),
                    exitcode => $proc.exitcode,
                    output   => $proc.out.slurp: :close).throw;
            }
            $proc
        }

        my @shas;
        for $!rakudo-dir, $source-spec.rakudo-git-url, $source-spec.rakudo-commit-sha, config.projects.rakudo.main,
                $!nqp-dir,    $source-spec.nqp-git-url, $source-spec.nqp-commit-sha, config.projects.nqp.main,
                $!moar-dir,   $source-spec.moar-git-url, $source-spec.moar-commit-sha, config.projects.moar.main
                -> $repo-dir, $remote, $commit, $main {
            debug "SourceArchiveCreator: working on " ~ $remote ~ " " ~ $commit;
            my $tmp-branch = 'tmp-branch';

            run(qw|git remote rm|, $tmp-branch,
                :cwd($repo-dir), :merge).so;

            validate run qw|git remote add|, $tmp-branch, $remote,
                :cwd($repo-dir), :merge;

            #validate run qw|git fetch|, $tmp-branch, |($.fetch-ref ?? ("+refs/" ~ $.fetch-ref ~ ":refs/remotes/" ~ $.fetch-ref,) !! ()),
            validate run qw|git fetch|, $tmp-branch,
                :cwd($repo-dir), :merge;

            my $ref = $commit eq 'LATEST' ?? "$tmp-branch/$main" !! $commit;

            validate run qw|git reset --hard|, $ref,
                :cwd($repo-dir), :merge;

            # updating submodules
            {
                validate run qw|git submodule sync --quiet|, :cwd($repo-dir), :merge;

                validate run qw|git submodule --quiet init|, :cwd($repo-dir), :merge;

                my $submod-status = validate(run(qw|git submodule status|, :cwd($repo-dir), :out)).out.slurp: :close;

                for $submod-status.lines -> $line {
                    unless $line ~~ / ^ . <[ 0..9 a..f ]>+ ' ' (\H+) [$ | ' '] / {
                        X::ArchiveTextCreationException.new(
                                text => "Failed to extract submodules. Output was: " ~ $submod-status;
                            ).throw;
                    }
                    my $path = $0;
                    my $name = $path.IO.basename;
                    my $mod-ref-dir = $!ref-dir.add($name).absolute.IO;
                    my $url = validate(run(qw|git config|, "submodule.$path.url", :cwd($repo-dir), :out)).out.slurp: :close;
                    $url .= trim;
                    unless ($url) {
                        X::ArchiveTextCreationException.new(text => "Failed to extract submodule url.").throw;
                    }

                    if $mod-ref-dir.e {
                        validate run qw|git fetch --quiet --all|, :cwd($mod-ref-dir), :merge;
                    }
                    else {
                        validate run qw|git clone --quiet --bare|, $url, $mod-ref-dir, :merge;
                    }

                    validate run qw|git submodule --quiet update --reference|, $mod-ref-dir, $path, :cwd($repo-dir), :merge;
                }
            }

            @shas.push: do if $commit eq "LATEST" {
                my $proc = validate run qw|git rev-parse HEAD|, :cwd($repo-dir), :out;
                my $rev = $proc.out.slurp: :close;
                $rev.uc.trim;
            }
            else {
                $commit;
            };
        }

        my $id = @shas.join: "_";
        my $filepath = self!get-path-for-name: $id ~ '.tar', :create-dirs;

        debug "SourceArchiveCreator: now archiving to " ~ $filepath;

        run("rm", $filepath.relative($!work-dir), :cwd($!work-dir), :merge).so;
        validate run qw|tar -c --exclude-vcs --owner=0 --group=0 --numeric-owner -f|,
            $filepath.relative($!work-dir),
            $!rakudo-dir.relative($!work-dir),
            $!nqp-dir.relative($!work-dir),
            $!moar-dir.relative($!work-dir),
            :cwd($!work-dir), :merge;

        run("rm", $filepath.relative($!work-dir) ~ ".xz", :cwd($!work-dir), :merge).so;
        validate run qw|xz -9|, $filepath.relative($!work-dir), :cwd($!work-dir), :merge;

        # OBS needs three separate archives, so prepare those as well.
        my $filepath-base = self!get-path-for-name($id, :create-dirs).relative($!work-dir);

        my $filepath-moar = $filepath-base ~ '-moar';
        run("rm", $filepath-moar ~ ".tar", :cwd($!work-dir), :merge).so;
        validate run qw|tar -c --exclude-vcs --owner=0 --group=0 --numeric-owner|,
            "--transform=s,^MoarVM,{$id}-moar,",
            "-f", $filepath-moar ~ ".tar",
            $!moar-dir.relative($!work-dir),
            :cwd($!work-dir), :merge;
        run("rm", $filepath-moar ~ $ext, :cwd($!work-dir), :merge).so;
        validate run qw|xz -9|, $filepath-moar ~ ".tar", :cwd($!work-dir), :merge;

        my $filepath-nqp = $filepath-base ~ '-nqp';
        run("rm", $filepath-nqp ~ ".tar", :cwd($!work-dir), :merge).so;
        validate run qw|tar -c --exclude-vcs --owner=0 --group=0 --numeric-owner|,
            "--transform=s,^nqp,{$id}-nqp,",
            "-f", $filepath-nqp ~ ".tar",
            $!nqp-dir.relative($!work-dir),
            :cwd($!work-dir), :merge;
        run("rm", $filepath-nqp ~ $ext, :cwd($!work-dir), :merge).so;
        validate run qw|xz -9|, $filepath-nqp ~ ".tar", :cwd($!work-dir), :merge;

        my $filepath-rakudo = $filepath-base ~ '-rakudo';
        run("rm", $filepath-rakudo ~ ".tar", :cwd($!work-dir), :merge).so;
        validate run qw|tar -c --exclude-vcs --owner=0 --group=0 --numeric-owner|,
            "--transform=s,^rakudo,{$id}-rakudo,",
            "-f", $filepath-rakudo ~ ".tar",
            $!rakudo-dir.relative($!work-dir),
            :cwd($!work-dir), :merge;
        run("rm", $filepath-rakudo ~ $ext, :cwd($!work-dir), :merge).so;
        validate run qw|xz -9|, $filepath-rakudo ~ ".tar", :cwd($!work-dir), :merge;

        $test-set.source-archive-exists = True;
        $test-set.source-archive-id = $id;
        $test-set.^save;
    }
}

method clean-old-archives() {
    for DB::CITestSet.^all.grep({
            $_.source-archive-exists == True &&
            $_.finished-at.defined &&
            $_.finished-at < DateTime.now - config.source-archive-retain-days * 24 * 60 * 60
    }) -> $test-set {
        trace "Removing archives for " ~ $test-set.id ~ " finished at " ~ $test-set.finished-at;
        my $filepath-base = self!get-path-for-name($test-set.source-archive-id, :create-dirs).relative($!work-dir);

        run("rm", $filepath-base ~ ".tar.xz",        :cwd($!work-dir), :merge).so;
        run("rm", $filepath-base ~ "-moar.tar.xz",   :cwd($!work-dir), :merge).so;
        run("rm", $filepath-base ~ "-nqp.tar.xz",    :cwd($!work-dir), :merge).so;
        run("rm", $filepath-base ~ "-rakudo.tar.xz", :cwd($!work-dir), :merge).so;

        $test-set.source-archive-exists = False;
        $test-set.^save;
    }
}

method get-id-for-filename($filename --> Str) { $filename.subst(/ $ext $ /, '') }
method get-filename($id --> Str) { $id ~ $ext }

multi method get-archive-path($id           --> IO::Path) { self!get-path-for-name: $id ~ $ext }
multi method get-archive-path($id, 'moar'   --> IO::Path) { self!get-path-for-name: $id ~ '-moar' ~ $ext }
multi method get-archive-path($id, 'nqp'    --> IO::Path) { self!get-path-for-name: $id ~ '-nqp' ~ $ext }
multi method get-archive-path($id, 'rakudo' --> IO::Path) { self!get-path-for-name: $id ~ '-rakudo' ~ $ext }

}
