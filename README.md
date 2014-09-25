# SftpExtractor

## 1) Installation

Add this line to your application's Gemfile:

```ruby
gem 'sftp_extractor'
```

### Development and Testing

To test the `sftp-extractor` you'll need to have a SFTP server running your machine. To do that on Mac OS X follow [this instructions](http://www.gooze.eu/howto/using-openssh-with-smartcards/openssh-server-on-mac-os-x).

Where it says 'Allow access for:' by default is `Administrators` which I changed for my username.

Test your port 22 is now opened:

```bash
$ nc -zv localhost 22

# => Connection to localhost port 22 [tcp/ssh] succeeded!
```

or simply

```bash
$ sftp nunocosta@127.0.0.1
Password:
Connected to 127.0.0.1.
sftp> dir
Applications  Desktop       Documents     Downloads     Google Drive  Library       Movies        Music         Pictures      Public
```

## 2) Usage

```bash
source /srv/rails-env/env.sh && cd /srv/sftp-extractor && time ruby bin/sftp_extractor.rb -c conf/campaign_cosy.yml -e $rails_env
```

### Development:

```bash
ruby bin/sftp_extractor.rb -c conf/template.yml -e development
```

## 3) Settings

__TO BE TRANSLATED__

| *chave* | *descrição* | *opcional?* |
| ------------- |-------------|:-----:|
| credentials[:server] | IP / hostname do servidor SFTP | |
| credentials[:user] | username | |
| credentials[:pwd] | password | |
| credentials[:timeout] | parametro aceite pela classe Net::SSH (funciona apenas no CONNECT) | |
| root | pasta relativa à home, onde estão os ficheiros que queremos extrair | |
| folder[:in] | lista de patterns que filtram os ficheiros que se pretendem extrair | |
| folder[:local_out] | pasta relativa onde vão ser gravados os ficheiros depois de extraidos  | |
| folder[:on_success] | depois de extrair os ficheiros move-os para esta pasta no SFTP | |
| folder[:on_success][:move_to] | pasta para onde serão movidos os ficheiros que foram copiados | X |
| folder[:on_success][:cleanup] | período ao fim do qual remove os ficheiros da pasta definida em folder[:on_success][:move_to]. Exemplo: '6 hours' | X |
| folder[:extraction_mode] | Opções: *'last'*: extrai o ficheiro mais recente com o PATTERN;  *'full'*: extrai todos os ficheiros existentes com o PATTERN) | X |
| retry_on_error[:max_times] | quantas vezes espera 'period' até que todos os ficheiros dos patterns tenham sido extraidos | X |
| retry_on_error[:period] | se pelo menos um dos ficheiros não tiver sido bem extraido, espera esta quantidade de tempo | X |


```yaml
# conf/campaign_cosy.yml

production:
  credentials:
    server: xx.xxx.xxx.xxx
    user: xXxXxXx
    pwd: xXxXxXx
    timeout: 20
  root: "."
  folder:
    in: { patterns: ["*customers.csv"] }
    local_out: incoming/campaign_cosy
    on_success:
      move_to: PROCESSED
      cleanup: 6 hours
    extraction_mode: full
  logger:
    path: /var/log/sftp-extractor/campaign_cosy.log
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
