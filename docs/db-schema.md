test-task-unit
==============

The smallest unit a status is reported for.
A `test` is a single test unit in a test suite on a CI platform for a specific test task.

id
fk-test-task-id
ciplatform-identifier
    - azure
    - OBS
status
    - not-started
    - in-progess
    - success
    - failure
    - aborted
started-timestamp
finished-timestamp


test-task
=========

A test request. Usually corresponds to a commit in the source provider.

id
creation-timestamp

project         'moar', 'nqp', 'rakudo'
git-repo-url    https repo url
commit-sha

status
    - new
    - source-archive-created
    - waiting-for-test
    - done
    - error

error
    - source-is-gone

rakudo-repo     e.g. 'rakudo/rakudo' or /patrickbkr/rakudo'
rakudo-commit-sha
nqp-repo
nqp-commit-sha
moar-repo
moar-commit-sha

source-archive-id
source-retrieval-retries


github-test-event
=================

id
event-type         'pr', 'command', 'main-branch'
fk-github-prs-id
fk-github-command-id
commit-url
test-task-id


github-pr
=========

id
pr-number
project     'moar', 'nqp', 'rakudo'
pr-url
repo
status      'open', 'closed'


github-command
==============

id
fk-github-prs-id
comment-number
comment-url    comment url
command     're-test', 'merge-on-success'
status      'new', 'done'


website-command
===============

id
fk-github-prs-id
command     're-test'
status      'new', 'done'


