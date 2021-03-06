require 'net/sftp'
require 'sftp_extractor/net-sftp-patch'
require 'active_support/core_ext/array/conversions'

# http://net-ssh.github.com/sftp/v2/api/index.html

module SftpExtractor
  class Downloader

    def initialize args={}
      @options	  = args.dup

      @logger     = init_logger('sftp_extractor', @options[:logger]['level'], @options[:logger]['path'])
      @logger.debug { "configs: #{@options.inspect}" }
      @patterns_processed = []

      validate_configurations!
    end
    # --  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
    def run
      @logger.info { 'Starting...' }
      @errors_found  = false
      @error_output  = []

      max_retries = @options[:retry_on_error]['max_times'] || 0

      process_entry = Proc.new do |sftp, root, entry, pattern|
        if entry
          process_file(sftp, root, entry.name)
          @patterns_processed << pattern
        else
          raise "No files on '#{root}' with the pattern '#{pattern}*'"
        end
      end

      (0..max_retries).each{ |retry_idx|
        @errors_found = false

        @logger.info { "Getting Files from SFTP server @ #{@options[:credentials]['server']}" }

        res = Net::SFTP.start( *sftp_credentials ){ |sftp|

          (@options[:folder]['in']['patterns'] - @patterns_processed).each{ |pattern|
            begin

              if @extraction_full_mode
                get_files_ordered_by_date(sftp, pattern).each{ |entry|
                  process_entry[ sftp, root, entry, pattern ]
                }
              else
                entry = get_files_ordered_by_date(sftp, pattern).last
                process_entry[ sftp, root, entry, pattern ]
              end

            rescue
              @errors_found = true
              @error_output << "[#{Time.now.strftime('%H:%M:%S')}] Failed to get file(#{retry_idx+1}): #{$!.message}"
              @logger.warn { "Failed to get file(#{retry_idx+1}). #{$!.message}. Skipping this pattern..." }
              next

            end
          }

        } ; @logger.debug { "Closed connection" }
        
        if @errors_found
          if retry_idx < max_retries
            @logger.info { "Will retry in #{@options[:retry_on_error]['period'].to_i.to_s}" }
            sleep( time_to_secs(@options[:retry_on_error]['period']) )
            next
          else
            break # On success breaks the main loop
          end
        end

      }

      cleanup_folder_moving_to_done()

      if @patterns_processed.empty?
        raise SftpExtractor::NoFilesProcessedException
      end

    ensure
      if @errors_found
        mail_config = @options[:retry_on_error]['mail_config']
        send_email_with_error_log(
          mailto:   mail_config['to'],
          subject:  get_email_subject(mail_config['subject'], @options[:env]),
          body:     mail_config['body']
        )
      end
    end


    private
      def validate_credentials(credentials)
        credentials_options = ['server', 'user']
        unless credentials
          raise ArgumentError, "Please fill all the following fields of SFTP credentials: #{credentials_options.join(',')}, ['pwd'] and ['port']"
        end
        
        credentials_options.each{|not_null|
          unless credentials.has_key?(not_null)
            raise ArgumentError, "Please fill all the following fields of SFTP credentials: #{credentials_options.join(',')}, ['pwd'] and ['port']. Missing #{not_null}"
          end
        }
      end
      # --  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
      def validate_configurations!
        validate_credentials(@options[:credentials])

        folder_options = ['in', 'on_success', 'local_out']
        folder_options.each{|not_null|
          unless @options[:folder][not_null]
            raise ArgumentError, "Please fill all the following fields of folder options: #{folder_options.to_sentence}. Missing #{not_null}"
          end
        }

        @cleanup_period = time_to_secs(@options[:folder]['on_success']['cleanup'])
        raise TypeError, "cleanup_period must be an integer (in seconds) or a 'date helper' like '3 days'" unless @cleanup_period.is_a?(Fixnum)

        unless @options[:folder].has_key?('extraction_mode')
          @logger.info { "Extraction Mode not defined on Folder Options. Options: 'last', 'full'" }
          @extraction_full_mode = false
        else
          unless ['last', 'full'].include?(@options[:folder]['extraction_mode'])
            @logger.info { "Invalid Extraction Mode on Folder Options. Options: 'last', 'full'" }
            @extraction_full_mode = false
          else
            @extraction_full_mode = (@options[:folder]['extraction_mode'] === 'full')
          end
        end

        unless @options.has_key?(:root)
          raise ArgumentError, "Please fill all the :root"
        end
      end
      # --  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
      def send_email_with_error_log(mailto: [], subject: 'Errors Log', body: '')
        if mailto
          body << "<BR/><BR/>" unless body.empty?
          body << @error_output.join("<BR/>")

          patterns_failed = (@options[:folder]['in']['patterns'] - @patterns_processed)
          if patterns_failed.size > 0
            body << "<BR/><BR/>The following files were not received:<ul>"
            body << patterns_failed.map{|pattern| "<li>#{pattern}</li>"}.join
            body << "</ul>"
          end

          # sendmail(mailto, subject, body, "text/html")
          # @logger.info { "Email sent to #{mailto.join(', ')}" }

        else
          @logger.info { "Not sending email because 'to' field is empty" }
        end
      end
      # --  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
      def process_file(sftp, folder, entry)
        file_in = File.join(folder,entry)

        @logger.info { "Downloading #{file_in}..." }

        sftp.download!(
          file_in,
          File.join(@options[:folder]['local_out'],entry)
        )

        # @logger.debug "Going to move #{file_in} --> #{File.join( @options[:root], @options[:folder]['on_success']['move_to'], entry)}"
        if @options[:folder]['on_success'].has_key?('move_to')
          sftp.rename(
            file_in,
            File.join( @options[:root], @options[:folder]['on_success']['move_to'], entry)
          )
        else
          @logger.info { "Not moving file because @options[:folder]['on_success']['move_to'] not defined" }
        end
      end
      # --  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
      def sftp_connect_options
        @sftp_connect_options ||= {
          password: @options[:credentials]['pwd'],
          timeout:  @options[:credentials]['timeout'] || 5,
          port:     @options[:credentials]['port']
        }
      end
      # --  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
      def sftp_credentials
        @sftp_credentials ||= [@options[:credentials]['server'], @options[:credentials]['user'], sftp_connect_options]
      end
      # --  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
      def get_files_ordered_by_date(sftp, pattern)
        sftp.dir.glob( root, pattern +"*" ).sort_by{|f| f.attributes.mtime}
      end
      # --  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
      #  if @options[:folder]['in']['root'] was not specified
      #  it's assumed @options[:root] as the place where the files should be
      def root
        @root ||= if @options[:folder]['in'].has_key?('root')
          File.join( @options[:root], @options[:folder]['in']['root'] )
        else
          @options[:root]
        end
      end
      # --  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
      def success_path
        @success_path ||= if @options[:folder]['on_success'].has_key?('move_to')
          File.join( @options[:root], @options[:folder]['on_success']['move_to'])
        else
          @options[:root]
        end
      end
      # --  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
      def cleanup_folder_moving_to_done
        res = Net::SFTP.start( *sftp_credentials ){ |sftp|

          if @options[:folder]['on_success'].has_key?('move_to')
            move_files_to_done(sftp, root)
          else
            @logger.warn { "Not moving files because @options[:folder]['on_success']['move_to'] not defined" }
          end

          if @options[:folder]['on_success'].has_key?('cleanup')
            nr_files = cleanup_old_files(sftp, root)
            @logger.info { "#{nr_files} files were deleted" }
          else
            @logger.warn { "If you need to set a cleanup period, fill folder['on_success']['cleanup']" }
          end

        }
        @logger.debug { 'Closed connection' }
      end
      # --  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
      def cleanup_old_files(sftp, root)
        remove_files_older_than = @cleanup_period.ago.to_i

        begin
          old_files = sftp.dir.entries( success_path ).reject{|f| ['.', '..'].include? f.name}

          files_deleted_counter = 0

          old_files.each { |old_file|

            if old_file.file? # se � um ficheiro, nao come�a por ponto, e � antigo
              if old_file.attributes.mtime < remove_files_older_than and old_file.name[0..0] != '.'
                sftp.remove( File.join( success_path, old_file.name ) ).wait
                files_deleted_counter += 1
                @logger.debug { "#{File.join( success_path, old_file.name)} DELETED!" }
              else
                @logger.debug { "Not Removing #{File.join( success_path, old_file.name)}" }
              end
            end
          }

        rescue Net::SFTP::StatusException => status
          raise "Directory probably does not exist. #{exception_info(status)}"
        end

        return files_deleted_counter
      end
      # --  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
      def move_files_to_done(sftp, root)
        begin
          old_files = sftp.dir.entries( root ).reject{|f| ['.', '..'].include? f.name or f.directory?}
        rescue Net::SFTP::StatusException => status
          @logger.error { "Directory probably does not exist. #{exception_info(status)}" }
          return nil
        end

        if old_files.any?
          @logger.info { "Going to move #{old_files.size} older files, or with a different pattern" }

          old_files.each { |old_file|

            if old_file.directory?
              @logger.debug { "Skipping to move '#{old_file.name}' because is a directory" }
              next
            end

            begin
              sftp.rename!(
                File.join( root, old_file.name),
                File.join( File.join( @options[:root], @options[:folder]['on_success']['move_to'], old_file.name) )
              )
            rescue Net::SFTP::StatusException => e
              # @logger.debug { "Failed to move #{old_file.name}. Going to remove the oldest" }
              @logger.debug { "Failed to move #{old_file.name}" }

              # sftp.remove( File.join( @options[:root], @options[:folder]['on_success']['move_to'], old_file.name) )

              # # mover o ficheiro que existe na pasta PROCESSAR para PROCESSADOS
              # sftp.rename(
              #   File.join( root, old_file.name ),
              #   File.join( File.join( @options[:root], @options[:folder]['on_success']['move_to'], old_file.name) )
              # )
            end
          }
        end # if empty
      end # move_files_to_done

  end   # class SftpExtractor
end   # module SftpExtractor

