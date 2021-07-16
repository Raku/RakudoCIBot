use Red:api<2>;
use SourceArchiveCreator;

unit module DB;

enum CIPlatformIdentifier <
    AZURE
    OBS
>;

enum CITestStatus <
    NOT_STARTED
    IN_PROGRESS
    SUCCESS
    FAILURE
    ABORTED
>;

enum Project <
    MOAR
    NQP
    RAKUDO
>;

enum CITestSetStatus <
    GITHUB
    NEW
    SOURCE_ARCHIVE_CREATED
    WAITING_FOR_TEST_RESULTS
    DONE
    ERROR
>;

enum CITestSetError <
    SOURCE_IS_GONE
>;

enum GitHubEventType <
    PR
    COMMAND
    MAIN_BRANCH
>;

enum PRStatus <
    OPEN
    CLOSED
>;

enum CommandEnum <
    RE_TEST
    MERGE_ON_SUCCESS
>;

enum CommandStatus <
    COMMAND_NEW
    COMMAND_DONE
>;

model CITestSet { ... }
model CITest { ... }
model GitHubPR { ... }
model Command { ... }

model CITest is rw is table<citest> {
    has UInt                     $.id                    is serial;
    has DateTime                 $.creation              is column .= now;
    has UInt                     $!fk-test-set           is referencing( *.id, :model(DB::CITestSet) );
    has DB::CITestSet            $.test-set              is relationship( *.fk-test-set );
    has DateTime                 $.test-started          is column{ :nullable };
    has DateTime                 $.test-finished         is column{ :nullable };
    has DB::CIPlatformIdentifier $.ciplatform            is column{ :nullable };
    has DB::CITestStatus         $.status                is column = NOT_STARTED;
    has Str                      $.log                   is column{ :type<text> };
}

model CITestSet is rw is table<citest_set> {
    has UInt                $.id           is serial;
    has DateTime            $.creation     is column .= now;

    # Responsibility of the GitHubCITestRequester
        has DB::GitHubEventType $.event-type               is column;

        has DB::Project         $.project                  is column;
        has Str                 $.commit-sha               is column;

        # If this test request was caused by a PR or new commit therein.
        has UInt                $!fk-pr                    is referencing( :nullable, *.id, :model(DB::GitHubPR) );
        has DB::GitHubPR        $.pr                       is relationship( *.fk-pr );

        # If this test request was caused by a command.
        has UInt                $!fk-command               is referencing( :nullable, *.id, :model(DB::Command) );
        has DB::Command         $.command                  is relationship( *.fk-command );

    # Responsibility of the CITestSetManager
        has DB::CITestSetStatus $.status                   is column = GITHUB;
        has DB::CITestSetError  $.error                    is column{ :nullable };

        has Str                 $!rakudo-repo              is column{ :nullable }; # e.g. 'rakudo/rakudo'
        has Str                 $!rakudo-commit-sha        is column{ :nullable };
        has Str                 $!nqp-repo                 is column{ :nullable };
        has Str                 $!nqp-commit-sha           is column{ :nullable };
        has Str                 $!moar-repo                is column{ :nullable };
        has Str                 $!moar-commit-sha          is column{ :nullable };

        has Str                 $.source-archive-id        is column{ :nullable, :type<text> };
        has UInt                $.source-retrieval-retries is column = 0;

        has DB::CITest          @.tests                    is relationship( *.fk-test-set );

        method source-spec() is rw {
            return-rw Proxy.new(
                FETCH => sub ($) {
                    SourceSpec.new(
                        :$!rakudo-repo,
                        :$!rakudo-commit-sha,
                        :$!nqp-repo,
                        :$!nqp-commit-sha,
                        :$!moar-repo,
                        :$!moar-commit-sha,
                    )
                },
                STORE => sub ($, $spec) {
                    $!rakudo-repo       = $spec.rakudo-repo;
                    $!rakudo-commit-sha = $spec.rakudo-commit-sha;
                    $!nqp-repo          = $spec.nqp-repo;
                    $!nqp-commit-sha    = $spec.nqp-commit-sha;
                    $!moar-repo         = $spec.moar-repo;
                    $!moar-commit-sha   = $spec.moar-commit-sha;
                },
            )
        }
}

model GitHubPR is rw is table<github_pr> {
    has UInt          $.id        is serial;
    has DateTime      $.creation  is column .= now;
    has UInt          $.number    is column;
    has DB::Project   $.project   is column;
    has Str           $.web-url   is column;
    has Str           $.repo      is column;
    has DB::PRStatus  $.status    is column;

    has DB::CITestSet @.test-sets is relationship( *.fk-pr );
}

#`[
    A command. Either triggered via a comment in a GitHub PR or via the
    website.
  ]
model Command is rw is table<command> {
    has UInt              $.id             is serial;
    has DateTime          $.creation       is column .= now;

    # If triggered via a GitHub PR
    has UInt              $!fk-pr          is referencing( *.id, :model(DB::GitHubPR) );
    has DB::GitHubPR      $.pr             is relationship( *.fk-pr );
    has Str               $.comment-number is column;
    has Str               $.comment-url    is column;

    # If triggered via the Website the test set on whose web page the command was issued.
    has UInt              $!fk-origin-test-set     is referencing( *.id, :model(DB::CITestSet) );
    has DB::CITestSet     $.origin-test-set is relationship( *.fk-origin-test-set );

    has DB::CommandEnum   $.command        is column;
    has DB::CommandStatus $.status         is column;

    # Should only ever be one.
    has DB::CITestSet     @.test-sets  is relationship( *.fk-command );
}

our sub create-db() {
    schema(DB::CITest, DB::CITestSet, DB::GitHubPR, DB::Command).create;
}
