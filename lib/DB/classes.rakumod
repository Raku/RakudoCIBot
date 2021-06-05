use Red:api<2>;

enum DB::CIPlatformIdentifier <
    AZURE
    OBS
>;

enum DB::TestStatus <
    NOT_STARTED
    IN_PROGRESS
    SUCCESS
    FAILURE
    ABORTED
>;

enum DB::Project <
    MOAR
    NQP
    RAKUDO
>;

enum DB::TestSetStatus <
    NEW
    SOURCE_ARCHIVE_CREATED
    WAITING_FOR_TEST_RESULTS
    DONE
    ERROR
>;

enum DB::TestSetError <
    SOURCE_IS_GONE
>;

enum DB::GithubEventType <
    PR
    COMMAND
    MAIN_BRANCH
>;

enum DB::PRStatus <
    OPEN
    CLOSED
>;

enum DB::CommandEnum <
    RE_TEST
    MERGE_ON_SUCCESS
>;

enum DB::CommandStatus <
    COMMAND_NEW
    COMMAND_DONE
>;

model DB::TestSet { ... }
model DB::Test { ... }
model DB::GithubPR { ... }
model DB::Command { ... }

model DB::Test is rw is table<test> {
    has UInt                     $.id                    is serial;
    has DateTime                 $.creation              is column = now;
    has UInt                     $!fk-test-set           is referencing( *.id, :model(DB::TestSet) );
    has DB::TestSet              $.test-set              is relationship( *.fk-test-set );
    has DateTime                 $.test-started          is column;
    has DateTime                 $.test-finished         is column;
    has DB::CIPlatformIdentifier $.ciplatform            is column;
    has Str                      $.ciplatform-identifier is column;
    has DB::TestStatus           $.status                is column;
    has Str                      $.log                   is column{ :type<text> };
}

model DB::TestSet is rw is table<test_set> {
    has UInt                $.id           is serial;
    has DateTime            $.creation     is column = now;

    # Responsibility of the GithubTestRequester
        has DB::GithubEventType $.event-type               is column;

        has DB::Project         $.project                  is column;
        has Str                 $.git-repo-url             is column;
        has Str                 $.commit-sha               is column;

        # If this test request was caused by a PR or new commit therein.
        has UInt                $!fk-pr                    is referencing( *.id, :model(DB::GithubPR) );
        has DB::GithubPR        $.pr                       is relationship( *.fk-pr );

        # If this test request was caused by a command.
        has UInt                $!fk-command               is referencing( *.id, :model(DB::Command) );
        has DB::Command         $.command                  is relationship( *.fk-command );

    # Responsibility of the TestSetManager
        has DB::TestSetStatus   $.status                   is column;
        has DB::TestSetError    $.error                    is column;

        has Str                 $.rakudo-repo              is column;      # e.g. 'rakudo/rakudo' or /patrickbkr/rakudo'
        has Str                 $.rakudo-commit-sha        is column;
        has Str                 $.nqp-repo                 is column;
        has Str                 $.nqp-commit-sha           is column;
        has Str                 $.moar-repo                is column;
        has Str                 $.moar-commit-sha          is column;

        has Str                 $.source-archive-id        is column{ :type<text> };
        has UInt                $.source-retrieval-retries is column;

        has DB::Test            @.tests                    is relationship( *.fk-test-set );
}

model DB::GithubPR is rw is table<github_pr> {
    has UInt         $.id        is serial;
    has DateTime     $.creation  is column = now;
    has UInt         $.number    is column;
    has DB::Project  $.project   is column;
    has Str          $.web-url   is column;
    has Str          $.repo      is column;
    has DB::PRStatus $.status    is column;

    has DB::TestSet  @.test-sets is relationship( *.fk-pr );
}

#`[
    A command. Either triggered via a comment in a Github PR or via the
    website.
  ]
model DB::Command is rw is table<command> {
    has UInt              $.id             is serial;
    has DateTime          $.creation       is column = now;

    # If triggered via a Github PR
    has UInt              $!fk-pr          is referencing( *.id, :model(DB::GithubPR) );
    has DB::GithubPR      $.pr             is relationship( *.fk-pr );
    has Str               $.comment-number is column;
    has Str               $.comment-url    is column;

    # If triggered via the Website the test set on whose web page the command was issued.
    has UInt              $!fk-origin-test-set     is referencing( *.id, :model(DB::TestSet) );
    has DB::TestSet       $.origin-test-set is relationship( *.fk-origin-test-set );

    has DB::CommandEnum   $.command        is column;
    has DB::CommandStatus $.status         is column;

    # Should only ever be one.
    has DB::TestSet       @.test-sets  is relationship( *.fk-command );
}

