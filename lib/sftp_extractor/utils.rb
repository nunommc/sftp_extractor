require 'active_support/core_ext/numeric/time'

def save_log_to_file(error_output, filename)
	if !error_output.empty?
		puts "\n ** WITH ERRORS **\n"
		file_log = File.new(filename, "w+")
		error_output.each { |line|
			file_log << line + "\n"
		}
		file_log.close
		
		system "zip -9 -m -q #{filename}.zip #{filename}"
		begin
			File.delete filename
		rescue
			puts exception_info($!)
		end

		host = `hostname`.chop
		
		system "uuencode #{filename}.zip #{filename}.zip | mail -s '[SFA-SIREL@#{host}] *** ERRO ***' #{RECIPIENTS_IN_CASE_OF_ERROR.join ' '}" if !RECIPIENTS_IN_CASE_OF_ERROR.empty?
		begin
			File.delete("#{filename}.zip")
		rescue
			puts exception_info($!)
		end
	end
end

def exception_info(o)
    message="Exception '"+o.class.to_s+"'"
    if o.respond_to? :backtrace then message << " at #{o.backtrace[0].to_s}" end
    if o.respond_to? :message   then message << " - #{o.message.to_s}" end
    #if o.respond_to? :backtrace then message << "\nBacktrace: "+o.backtrace.join("\n") end
    
    message
end

def exception_less_info(o)
    message="Exception '"+o.class.to_s+"'"
    if o.respond_to? :message   then message << " - #{o.message.to_s}" end
    #if o.respond_to? :backtrace then message << "\nBacktrace: "+o.backtrace.join("\n") end
    
    message
end

def time_parse_us_format date_str
  months = ['jan','feb','mar', 'apr','may','jun',  
    'jul','aug','sep','oct','nov','dec']
  date_str =~ /(\d{2})-(\d{1,2})-(\d{4}) (\d+):(\d\d):(\d\d)/
  Time.local($3.to_i, months[$2.to_i - 1], $1.to_i, $4.to_i, $5.to_i, $6.to_i)
end

def get_email_subject(subject, env)
  if env != 'production'
    env_short = {'development' => 'DEV'}[ env ]
    env_short ||= env
    subject << " @ #{env_short}"
  end
  subject
end

# @input: '2 minutes'
# @output: 120
# 
# @input: 120
# @output: 120
def time_to_secs(time)
  eval(time.to_s.gsub(' ', '.')).to_i
end

def get_log_filename(dir_path, only_today=true)
	filename = Dir.glob(dir_path).sort.last #Dir.entries(path).sort.last
	today = Time.now

	return nil if only_today && (File.ctime(filename) < Time.local(today.year, today.mon, today.day))
	
	puts "\n" , filename
	filename
end

def init_logger(progname, level, file=$stderr)
  require 'logger'
  ffile = file ? file : $stderr
  logger = Logger.new( ffile )
  logger.level = Logger.const_get(level.to_s.upcase)
  logger.formatter = Logger::Formatter.new
  logger.formatter.datetime_format = "%Y-%m-%d %H:%M:%S"
  logger.progname = progname

  logger.warn "If you need place the output log in a file fill logger['path']" unless file
  logger
end

# => env => production, development_test
# => handler => ivr, crma, tephra
def process_running_filename(prog_name, env, handler)
    fname = prog_name.dup
    fname << "-#{handler}" if handler
    fname << "-#{env}" if env
    fname << '.pid'

    File.join('/tmp', fname)
end


def is_process_running?(prog_name, env, handler)
    return File.exist?( process_running_filename(prog_name, env, handler) )
end

def process_running_pid(prog_name, env, handler)
    fname = process_running_filename(prog_name, env, handler)
    File.open( fname, 'w' ){|f| f.puts Process.pid }
    #sleep(rand 20)
end

def remove_process_running_file(prog_name, env, handler)
    File.delete( process_running_filename(prog_name, env, handler) )
end

def get_running_process_pid(prog_name, env, handler)
  begin
      file = File.new( process_running_filename(prog_name, env, handler), 'r')
      pid = file.gets
      file.close
      unless /^([\d]+)$/ === pid
        raise "pid is not a number"
      end
      pid = pid.to_i
      return pid
  rescue => err
      puts "Exception: #{err}"
  end
  return nil
end
