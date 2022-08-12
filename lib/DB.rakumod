use Red:api<2> <refreshable>;
use SourceArchiveCreator;

unit module DB;

enum CIPlatformIdentifier <
    AZURE
    OBS
    TEST_BACKEND
>;

enum CITestStatus <
    NOT_STARTED
    IN_PROGRESS
    SUCCESS
    FAILURE
    ABORTED
    UNKNOWN
>;

enum CIPlatformTestSetStatus <
    PLATFORM_IN_PROGRESS
    PLATFORM_DONE
>;

enum Project <
    MOAR
    NQP
    RAKUDO
>;

enum CITestSetStatus (
    "NEW",                      # As created by the GitHubCITestRequester. SourceSpec has not been created yet.
    "UNPROCESSED",              # SourceSpec has been created. Now to be processed by the CITestSetManager
    "SOURCE_ARCHIVE_CREATED",   # An archive file with the sources to test has been created.
    "WAITING_FOR_TEST_RESULTS", # CI platforms have been informed of new tests. Now waiting for results.
    "DONE",                     # All tests are done, completion has been signalled back to GitHub.
    "ERROR"                     # Some unrecoverable error has occurred.
);

enum CITestSetError (
    "SOURCE_IS_GONE" # Even after retries we failed to retrieve the sources of a test request.
);

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

model CITest { ... }
model CIPlatformTestSet { ... }
model CITestSet { ... }
model GitHubPullState { ... }
model GitHubPR { ... }
model Command { ... }

model CITest is rw is table<citest> {
    has UInt                  $.id                    is serial;
    has Str                   $.name                  is column;
    has DateTime              $.creation              is column .= now;
    has UInt                  $!fk-platform-test-set  is referencing( *.id, :model(DB::CIPlatformTestSet) );
    has DB::CIPlatformTestSet $.platform-test-set     is relationship( *.fk-platform-test-set );
    has DateTime              $.test-started-at       is column{ :nullable };
    has DateTime              $.test-finished-at      is column{ :nullable };
    has DB::CITestStatus      $.status                is column = NOT_STARTED;
    has Bool                  $.flapper-checked       is column = False;
    has Str                   $.flapper               is column{ :nullable };
    has Str                   $.log                   is column{ :nullable, :type<text> };
    has Str                   $.ci-url                is column{ :nullable };

    has UInt                  $!fk-successor          is referencing( *.id, :model(DB::CITest) );
    has CITest                $.successor             is relationship( *.fk-successor );

    has Str                   $.obs-arch              is column{ :nullable };
    has Str                   $.obs-repository        is column{ :nullable };
    has Bool                  $.obs-before-re-test    is column = False;

    # Responsibility of the GitHubCITestRequester
    has Str(Int)              $.github-id             is column{ :nullable };
    has DB::CITestStatus      $.status-pushed         is column = NOT_STARTED;
}

model CIPlatformTestSet is rw is table<ciplatform_test_set> {
    has UInt                $.id           is serial;
    has DateTime            $.creation     is column .= now;

    has DB::CIPlatformIdentifier    $.platform  is column{ :nullable };
    has DB::CIPlatformTestSetStatus $.status      is column = DB::PLATFORM_IN_PROGRESS;
    has Bool                        $.re-test     is column = False;
    has UInt                        $!fk-test-set is referencing( *.id, :model(DB::CITestSet) );
    has DB::CITestSet               $.test-set    is relationship( *.fk-test-set );

    has DB::CITest @.tests          is relationship( *.fk-platform-test-set );

    # Responsibility of OBS
    has DateTime $.obs-started-at      is column{ :nullable };
    has DateTime $.obs-finished-at     is column{ :nullable };
    has DateTime $.obs-last-check-time is column{ :nullable };
    has DateTime $.obs-hook-called-at  is column{ :nullable };
}

model CITestSet is rw is table<citest_set> {
    has UInt                      $.id                       is serial;
    has DateTime                  $.creation                 is column .= now;
    has DateTime                  $.finished-at              is column{ :nullable };

    # Responsibility of the GitHubCITestRequester
        has DB::GitHubEventType   $.event-type               is column;

        has DB::Project           $.project                  is column;
        has Str                   $.git-url                  is column;
        has Str                   $.commit-sha               is column;
        has Str                   $.user-url                 is column;

        # If this test request was caused by a PR or new commit therein.
        has UInt                  $!fk-pr                    is referencing( :nullable, *.id, :model(DB::GitHubPR) );
        has DB::GitHubPR          $.pr                       is relationship( *.fk-pr );

    # Responsibility of the CITestSetManager
        has DB::CITestSetStatus   $.status                   is column = NEW;
        has DB::CITestSetError    $.error                    is column{ :nullable };

        has Str                   $!rakudo-git-url           is column{ :nullable };
        has Str                   $!rakudo-commit-sha        is column{ :nullable };
        has Str                   $!nqp-git-url              is column{ :nullable };
        has Str                   $!nqp-commit-sha           is column{ :nullable };
        has Str                   $!moar-git-url             is column{ :nullable };
        has Str                   $!moar-commit-sha          is column{ :nullable };

        has Str                   $.source-archive-id        is column{ :nullable, :type<text> };
        has UInt                  $.source-retrieval-retries is column = 0;

        has DB::CIPlatformTestSet @.platform-test-sets       is relationship( *.fk-test-set );

    multi method source-spec($spec) {
        $!rakudo-git-url = $spec.rakudo-git-url;
        $!rakudo-commit-sha = $spec.rakudo-commit-sha;
        $!nqp-git-url = $spec.nqp-git-url;
        $!nqp-commit-sha = $spec.nqp-commit-sha;
        $!moar-git-url = $spec.moar-git-url;
        $!moar-commit-sha = $spec.moar-commit-sha;
    }
    multi method source-spec() {
        SourceSpec.new(
            rakudo-git-url    => $!rakudo-git-url // "",
            rakudo-commit-sha => $!rakudo-commit-sha // "",
            nqp-git-url       => $!nqp-git-url // "",
            nqp-commit-sha    => $!nqp-commit-sha // "",
            moar-git-url      => $!moar-git-url // "",
            moar-commit-sha   => $!moar-commit-sha // "",
        )
    }
}

model GitHubPullState is rw is table<github_pull_state> {
    has UInt          $.id                         is serial;
    has DateTime      $.creation                   is column .= now;
    has DB::Project   $.project                    is column;

    has Str           $.last-default-branch-cursor is column{ :nullable };
    has Str           $.last-pr-cursor             is column{ :nullable };
}

model GitHubPR is rw is table<github_pr> {
    has UInt          $.id            is serial;
    has DateTime      $.creation      is column .= now;
    has UInt          $.number        is column;
    has DB::Project   $.project       is column;
    has Str           $.base-url      is column;
    has Str           $.head-url      is column;
    has Str           $.head-branch   is column;
    has Str           $.user-url      is column;
    has DB::PRStatus  $.status        is column;

    has DB::CITestSet @.test-sets is relationship( *.fk-pr );
}

#`[
    A command. Either triggered via a comment in a GitHub PR or via the
    website.
  ]
model Command is rw is table<command> {
    has UInt              $.id       is serial;
    has DateTime          $.creation is column .= now;

    # If triggered via a GitHub PR comment
    has UInt              $!fk-pr          is referencing( *.id, :model(DB::GitHubPR) );
    has DB::GitHubPR      $.pr             is relationship( *.fk-pr );
    has Str               $.comment-author is column;
    has Str               $.comment-id     is column;
    has Str               $.comment-url    is column;

    has DB::CommandStatus $.status  is column;
    has DB::CommandEnum   $.command is column;

    # If it's a re-test command, the test set we should re test
    has UInt              $!fk-test-set is referencing( *.id, :model(DB::CITestSet) );
    has DB::CITestSet     $.test-set    is relationship( *.fk-test-set );
}

our sub drop-db() {
    schema(DB::CITest, CIPlatformTestSet, DB::CITestSet, DB::GitHubPullState, DB::GitHubPR, DB::Command).drop;
}

our sub create-db() {
    schema(DB::CITest, CIPlatformTestSet, DB::CITestSet, DB::GitHubPullState, DB::GitHubPR, DB::Command).create;
}
