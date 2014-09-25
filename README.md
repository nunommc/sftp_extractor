# SftpExtractor

This gem allows you to setup regular extractions from a SFTP server.
It's expected that the server you're connecting to has file structure like shown below and that your user has privileges to copy and delete files from it's home directory:

    <USER'S DEFAULT DIR>
    `-- some_folder
        |-- PENDING
        |   |-- 2014_09_24_customers.csv
        |   `-- 2014_09_25_customers.csv
        `-- PROCESSED
            |-- ...
            |-- 2014_09_20_customers.csv
            |-- 2014_09_21_customers.csv
            |-- 2014_09_22_customers.csv
            `-- 2014_09_23_customers.csv

It's suggested you use the commands as shown [here](#2-usage) to setup your crontab or [whenever](https://github.com/javan/whenever) gem.

## 1) Installation

Add this line to your application's Gemfile:

```ruby
gem 'sftp_extractor'
```

### Before you start...

To test the `sftp-extractor` you'll need to have a SFTP server running your machine. To do that on Mac OS X follow [this instructions](http://www.gooze.eu/howto/using-openssh-with-smartcards/openssh-server-on-mac-os-x).

Where it says 'Allow access for:' by default is `Administrators` which I changed for my username.

Test your port 22 is now opened:
```bash
$ nc -zv localhost 22
# => Connection to localhost port 22 [tcp/ssh] succeeded!
```

or simply,
```bash
$ sftp nunommc@127.0.0.1
Password:
Connected to 127.0.0.1.
sftp> dir
Applications  Desktop       Documents     Downloads     Google Drive  Library       Movies        Music         Pictures      Public
```

## 2) Usage

```bash
source /srv/rails-env/env.sh && cd /srv/sftp-extractor && time ruby bin/sftp_extractor.rb -c conf/campaign.yml -e $rails_env
```

### Development:

```bash
ruby bin/sftp_extractor.rb -c conf/template.yml -e development
```

## 3) Settings


| *key*       |             | *description* | *optional* |
| ----------- | ----------- | ------------- | :--------: |
| **credentials** | :server     | SFTP server hostname/IP | |
|               | :user       | username | |
|               | :pwd        | password | |
|               | :timeout    | parameter accepted by Net::SSH constructor (applied only during the CONNECT) | |
|  **root**  | relative path to the default user's home, where are stored the files you want to extract | |
| **folder** | :in | list of patterns to filter the files you want to extract | |
|            | :local_out | relative path where the extracted files are should be saved  | |
|            | :on_success[:move_to] | after successfully extracting the files they'll be moved into this folder on the SFTP server | X |
|            | :on_success[:cleanup] | period of time after which files are going to be deleted from `folder[:on_success][:move_to]`. Example: `6 hours` | X |
|            | :extraction_mode | Options:<BR/> - **last**: extracts the most recent file matching the PATTERN;<BR/> - **full**: extracts every file matching the PATTERN | X |
| **retry_on_error** | :period | if at least one of the files wasn't successfully extracted, waits this amount of time | X |
|                    | :max_times | no. of times is going to wait  `period` time to retry the missing patterns | X |


```yaml
# conf/campaign.yml
production:
  credentials:
    server: xx.xxx.xxx.xxx
    user: xXxXxXx
    pwd: xXxXxXx
    timeout: 20
  root: "."
  folder:
    in: { root: PENDING, patterns: ["*customers.csv"] }
    local_out: incoming/campaign
    on_success:
      move_to: PROCESSED
      cleanup: 6 hours
    extraction_mode: full
  logger:
    path: /var/log/sftp-extractor/campaign.log
    level: info
  retry_on_error:
    mail_config:
      to:
        - admin@example.com
        - tech-admin@example.com
      subject: "Extraction from SFTP failed (CUSTOMERS LIST)"
      body: "Execution Log:"
```

## Contributing

1. [Fork it]( https://github.com/nunommc/sftp_extractor/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
