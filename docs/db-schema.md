test
====

The smallest unit a status is reported for.
A `test` is a single test in a test suite on a CI platform for a specific test set.

id
fk-test-set-id
creation As Timestamp
test-started-at As Timestamp
test-finished-at As Timestamp
ciplatform-identifier
    - azure
    - OBS
status
    - not-started
    - in-progress
    - success
    - failure
    - aborted
log as text


test-set
========

A test request. Usually corresponds to a commit in the source provider.

id
creation As Timestamp

project         'moar', 'nqp', 'rakudo'
git-repo-url    https repo url
commit-sha

status
    - new
    - source-archive-created
    - waiting-for-test-results
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
test-set-id


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
fk-github-pr-id
comment-number
comment-url    comment url
command     're-test', 'merge-on-success'
status      'new', 'done'


website-command
===============

id
fk-github-pr-id
command     're-test'
status      'new', 'done'


