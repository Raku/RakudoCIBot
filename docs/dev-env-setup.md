How to set up a development environment
=======================================

Install and set up Postgres
---------------------------

    sudo dnf install postgresql postgresql-server libpq-devel
    sudo /usr/bin/postgresql-setup --initdb
    sudo systemctl start postgresql

    sudo -u postgres psql
        CREATE USER your-user WITH CREATEDB
        CREATE DATABASE rcb_dev OWNER your-user
        \q


Fork the Rakudo repos
---------------------

Visit <https://github.com/rakudo/rakudo>, <https://github.com/Raku/nqp/> and <https://github.com/MoarVM/MoarVM>. For each click on "Fork" at the top right. Those repos now cloned into your GitHub user will be the ones your dev environments will work off of.


Create a GitHub App
-------------------

To be able to receive push notifications from GitHub you need to set up a GitHub App. To do so open the settings of your GitHub account (dropdown menu at the top left), then "Settings", then select "Developer Settings" in the left menu. There make sure you have "GitHub Apps" selected at the left and then click the "New GitHub App" button at the top right. Give it a name and make sure the Webhooks "Active" tickbox is selected. For the following permissions select "Access: read & write":

- RW Pull Requests: To be notified of new PRs and to comment on PRs
- RW Contents: To merge PRs
- RW Check Runs: To add test runs
- R Members: To check whether a user can merge a PR (So RCB doesn't merge a PR on request of a user that's not allowed to do so.)

Select the following events to subscribe to:

- Check suite: To be notified when a new test run should be done
- Issue comment: To be notified of PR comments which might contain RCB commands
- Pull Request: To be notified about new PRs to start a test run (PRs don't trigger Check suite events.)

Verify that "Only on this account" the App can be installed, as it's only used for development.

Finally click on "Create GitHub App".

Note the "Client ID" of your newly created App, you'll need it later.

Create and download a Private Key. Select "General" on the left of your App settings. At the bottom is an area that allows to "Generate a private key". Generate and then download that key. It should be a file with a ".pem" ending.

Now install the App into your own GitHub account. Again navigate to your Profile Settings and select "Developer Settings", "GitHub Apps" and click "Edit" next to your freshly created application. Select "Install App" on the left and install the app into your personal account. Make sure to grant it access to the three repos you forked above ("rakudo", "nqp" and "MoarVM").


Clone the RakudoCIBot repo
------------------------

In some folder where you want the RakudoCIBot repo to reside, call

    git clone https://github.com/Raku/RakudoCIBot/
    cd RakudoCIBot
    zef install --deps-only .


Create a config file
--------------------

Copy `config-prod.yml` to `config-dev.yml`. Adapt the following keys to match your setup:

- github-app-id: The client ID of the app you created in a previous step.
- github-app-key-file: Path to your `.pem` key file.
- projects/[rakudo,nqp,moar]/[project,slug]: Substitute the project with your GitHub account name. The slugs should then read: `[your_account]/rakudo`, `[your_account]/nqp` and `[your_account]/MoarVM`.

Then call the following script to determine your installation ID:

     raku -I. misc/list-installations.raku config-dev.yml

Edit the `config-dev.yml` file again and replace the `installation-id` for all three projects with the ID determined above.


Setup the database
------------------

    raku -I. misc/setup-database.raku config-dev.yml


Setup OBS
---------

- register
- set up projects


Download ngrok
--------------

- download and start
- fill in hook URL on GitHub

