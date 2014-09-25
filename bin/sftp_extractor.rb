require 'optparse'
require 'utils'

# We set default values here.
config_file = 'conf/default_config.yml'
environment = 'development'

$project_name = 'sftp-extractor'


OptionParser.new do |opts|
  opts.banner  = "Usage: ruby #{__FILE__} [options]:"
  opts.separator ''
  opts.separator 'Specific options:'

  opts.on('-e', '--environment [ENV]', "Select environment (see #{config_file}).") do |env|
		environment = env
  end

  opts.on('-c', '--config [config_file.yml]') do |cfg_fname|
		config_file = cfg_fname
  end

  opts.separator ''
  opts.separator 'Common options:'

  opts.on_tail('-h', '--help', 'Show this message') do
	puts opts
	exit
  end
end.parse!

#puts "Loading #{environment.upcase} configuration..."

# Load chosen environment from configuration file
require 'yaml'
raise ArgumentError, 'Invalid environment!' unless (env = YAML.load_file(config_file)[environment])


args = {
	:logger        => env['logger'],
	:retry_on_error   => env['retry_on_error'],
	:credentials   => env['credentials'],
	:folder     => env['folder'],
  :root       => env['root'],
  :env        => environment
}


# -------------
require './lib/sftp_extractor'
require './lib/sftp_extractor_exceptions'

cfg_file = config_file.split('.')[0].split('/').last

unless is_process_running?( $project_name, environment, cfg_file )
  begin
    process_running_pid( $project_name, environment, cfg_file )
    sleep 7
    runner = SftpExtractor::SftpExtractor.new(args)
    runner.run
  rescue SftpExtractor::NoFilesProcessedException => e
    exit(-1)
  rescue Exception => e
    puts e.message, e.backtrace
  ensure
    #puts [$project_name, environment, cfg_file].inspect
    remove_process_running_file( $project_name, environment, cfg_file )
  end

else  # => if the process is running

  body = "#{$project_name}<br/>Env: #{environment}<br/>Server: #{`hostname`}"

  if pid = get_running_process_pid($project_name, environment, cfg_file)
    begin
      Process.kill('KILL', pid) if pid > 1
      body << "<br/>Process killed: (#{pid})"
    rescue Exception => e
      body << "<br/>Process killed: (#{pid})"
      body << "<br/>#{e.message}"
    end
  end

  if args[:folder]['on_success'].key?('move_to')
    body << "<br/><br/>HINT: try to remove all files from #{File.join( args[:root], args[:folder]['on_success']['move_to'])}"
  end

  # sendmail(args[:retry_on_error]['mail_config']['to'], args[:retry_on_error]['mail_config']['subject'], body, "text/html")

  remove_process_running_file( $project_name, environment, cfg_file )
  exit(-1)
end
