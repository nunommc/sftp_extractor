require './lib/sftp_extractor_exceptions'
require './bin/utils'
require 'net/sftp'
require './lib/net-sftp-patch'
require 'active_support/core_ext'
require 'icarept-notifier'
#require 'active_support/core_ext/numeric/time'
#require 'active_support/core_ext/date/calculations'
#require 'ruby-debug'

# gem install net-sftp
# http://net-ssh.github.com/sftp/v2/api/index.html

module SftpExtractor
  class SftpExtractor

    def initialize args={}
      @options	  = args.dup

      @logger     = init_logger('cel_sftp_extractor', @options[:logger]['level'], @options[:logger]['path'])
      @logger.debug "configs: #{@options.inspect}"
      @patterns_processed = [] # empty list
    end

    def process_file(sftp, folder, entry)
      file_in = File.join(folder,entry)

      @logger.info "Downloading #{file_in}..."

      sftp.download!(
        file_in,
        File.join(@options[:folder]['local_out'],entry)
      )

      # @logger.debug "Going to move #{file_in} --> #{File.join( @options[:root], @options[:folder]['on_success']['move_to'], entry)}"
      if @options[:folder]['on_success'].key?('move_to')
        sftp.rename(
          file_in,
          File.join( @options[:root], @options[:folder]['on_success']['move_to'], entry)
        )
      else
        @logger.info "Not moving file because @options[:folder]['on_success']['move_to'] not defined"
      end
    end

    def cleanup_folder_moving_to_done(sftp, root)
      if @options[:folder]['on_success'].key?('move_to')
        move_files_to_done(sftp, root)
      else
        @logger.warn "Not moving files because @options[:folder]['on_success']['move_to'] not defined"
      end

      if @options[:folder]['on_success'].key?('cleanup')
        nr_files = cleanup_old_files(sftp, root, @options[:folder]['on_success']['cleanup'])
        @logger.info "#{nr_files} files were deleted"
      else
        @logger.warn "If you need to set a cleanup period, fill folder['on_success']['cleanup']"
      end
    end

    def cleanup_old_files(sftp, root, cleanup_period)
      cleanup_period = eval(@options[:folder]['on_success']['cleanup'].to_s.gsub(' ', '.'))

      raise TypeError, "cleanup_period must be an integer (in seconds) or a 'date helper' like '3 days'" unless cleanup_period.class == Fixnum


      remove_files_older_than = cleanup_period.ago.to_i
      success_path = if @options[:folder]['on_success'].key?('move_to')
        File.join( @options[:root], @options[:folder]['on_success']['move_to'])
      else
        @options[:root]
      end

      begin
        old_files = sftp.dir.entries( success_path ).reject{|f| ['.', '..'].include? f.name}

        files_deleted_counter = 0

        old_files.each { |old_file|

          if old_file.file? # se é um ficheiro, nao começa por ponto, e é antigo
            if old_file.attributes.mtime < remove_files_older_than and old_file.name[0..0] != '.'
              sftp.remove( File.join( success_path, old_file.name ) ).wait
              files_deleted_counter += 1
              @logger.debug "#{File.join( success_path, old_file.name)} DELETED!"
            else
              @logger.debug "Not Removing #{File.join( success_path, old_file.name)}"
            end
          end
        }

      rescue Net::SFTP::StatusException => status
        raise "Directory probably does not exist. #{exception_info(status)}"
      end

      return files_deleted_counter
    end

    def move_files_to_done(sftp, root)
      begin
        old_files = sftp.dir.entries( root ).reject{|f| ['.', '..'].include? f.name or f.directory?}
      rescue Net::SFTP::StatusException => status
        @logger.error "Directory probably does not exist. #{exception_info(status)}"
        return nil
      end

      return nil unless old_files.size > 0

      @logger.info "Going to move #{old_files.size} older files, or with a different pattern"

      old_files.each { |old_file|

        if old_file.directory?
          @logger.debug "Skipping to move '#{old_file.name}' because is a directory"
          next
        end

        begin
          sftp.rename!(
            File.join( root, old_file.name),
            File.join( File.join( @options[:root], @options[:folder]['on_success']['move_to'], old_file.name) )
          )
        rescue Net::SFTP::StatusException => e
          @logger.debug "Failed to move #{old_file.name}. Going to remove the eldest"

          sftp.remove( File.join( @options[:root], @options[:folder]['on_success']['move_to'], old_file.name) )

          # mover o ficheiro que existe na pasta PROCESSAR para PROCESSADOS
          sftp.rename(
            File.join( root, old_file.name ),
            File.join( File.join( @options[:root], @options[:folder]['on_success']['move_to'], old_file.name) )
          )
        end
      }
    end


    # old_files = sftp.dir.entries( root ).reject{|f| ['.', '..'].include? f.name}
    # old_files.each do |old_file|
              # NOTA (*PARA ESQUECER*): quando existe 1 ficheiro com o mesmo nome na pasta Destino, o Sftp#rename não está a lançar excepção
              #   e acaba por deixar o ficheiro na pasta Origem.
              #   Enquanto não se conseguir descobrir a Response ao Request (algo como moved_file.session#request.response.code),
              #   a solução passa por eliminar todos os ficheiros desta pasta no fim da execução.
              #   Idealmente, se foi colocado 1 ficheiro repetido, é porque vem corrigir alguma informação enviada anteriormente, por isso,
              #   o rename devia substituir o ficheiro antigo em vez de apagar o mais recente
    # end


    def run
      @logger.info "Starting..."
      with_error = false
      error_output = []

      ['server', 'user'].each{|not_null|
        unless @options[:credentials][not_null]
          raise ArgumentError, "Please fill all the following fields of SFTP credentials: 'server', 'user', ['pwd'] and ['port']. Missing #{not_null}"
        end
      }
      sftp_connect_options = {
          :password => @options[:credentials]['pwd'],
          :timeout => @options[:credentials]['timeout'] || 5,
          :port => @options[:credentials]['port']
        }

      ['in', 'on_success', 'local_out'].each{|not_null|
        unless @options[:folder][not_null]
          raise ArgumentError, "Please fill all the following fields of folder options: 'in', 'on_success' and 'local_out'. Missing #{not_null}"
        end
      }

      unless @options[:folder]['extraction_mode']
        @logger.info "Extraction Mode not defined on Folder Options. Options: 'last', 'full'"
        extraction_full_mode = false
      else
        unless ['last', 'full'].include?(@options[:folder]['extraction_mode'])
          @logger.info "Invalid Extraction Mode on Folder Options. Options: 'last', 'full'"
          extraction_full_mode = false
        else
          extraction_full_mode = (@options[:folder]['extraction_mode'] === 'full')
        end
      end

      unless @options.key?(:root)
        raise ArgumentError, "Please fill all the :root"
      end

      #     se nao for passado o @options[:folder]['in']['root'] é para podermos aceitar
      # => que a raiz possa ser o sitio onde estao os ficheiros
      root = if @options[:folder]['in'].key?('root')
        File.join( @options[:root], @options[:folder]['in']['root'] )
      else
        @options[:root]
      end

      # TODO: substituir por retry (pckg bin/utils)
      max_retries = @options[:retry_on_error]['max_times'] || 0

      process = Proc.new do |sftp, root, entry, pattern|
        if entry
          process_file(sftp, root, entry.name)
          @patterns_processed << pattern
        else
          raise "No files on '#{root}' with the pattern '#{pattern}*'"
        end
      end

      (0..max_retries).each{ |retry_idx|
        with_error = false

        @logger.info "Getting Files from SFTP server @ #{@options[:credentials]['server']}"


        # # timeout no upload # http://www.rafaelbiriba.com/2010/09/24/problema-no-net-sftp-timeout-para-o-upload.html

        res = Net::SFTP.start(@options[:credentials]['server'], @options[:credentials]['user'], sftp_connect_options){ |sftp|

            (@options[:folder]['in']['patterns'] - @patterns_processed).each{ |pattern|
                begin

                  if extraction_full_mode
                    sftp.dir.glob( root, pattern +"*" ).sort_by{|f| f.attributes.mtime}.each{|entry|
                      process.call sftp, root, entry, pattern
                    }
                  else
                    entry = sftp.dir.glob( root, pattern +"*" ).sort_by{|f| f.attributes.mtime}.last
                    process.call sftp, root, entry, pattern
                  end


                rescue
                  with_error = true
                  error_output << "[#{Time.now.strftime('%H:%M:%S')}] Failed to get file(#{retry_idx+1}): #{$!.message}"
                  @logger.warn("Failed to get file(#{retry_idx+1}). #{$!.message}. Skipping this pattern...")
                  next

                end
            }


        } ; @logger.debug "Closed connection"
        if with_error and retry_idx < max_retries

          @logger.info "Will retry in #{@options[:retry_on_error]['period'].to_i.to_s}"
          sleep(eval(@options[:retry_on_error]['period'].to_s.gsub(' ', '.')).to_i)

          next
        end

        break # On success breaks the main loop
      }


      ########

      res = Net::SFTP.start(@options[:credentials]['server'], @options[:credentials]['user'], sftp_connect_options){ |sftp|
        cleanup_folder_moving_to_done(sftp, root)
      } ; @logger.debug "Closed connection"


      if(@patterns_processed.empty?)
        raise Cel::SftpExtractor::NoFilesProcessedException
      end

    ensure

      if with_error and @options[:retry_on_error]['mail_config']['to']
        subject= @options[:retry_on_error]['mail_config']['subject']

        if @options[:env] != 'production'
          env = {'development' => 'DEV'}[@options[:env] ]
          env ||= @options[:env]
          subject << " @ #{env}"
        end

        body = @options[:retry_on_error]['mail_config']['body']  + "<br/><br/>"

        error_output.each{ |err| body += err + "<br/>"   }

        patterns_failed = (@options[:folder]['in']['patterns'] - @patterns_processed)
        if patterns_failed.size > 0
          body += "<br/><br/>The following files were not received:<ul>"
          patterns_failed.each{|pattern| body += "<li>#{pattern}</li>"}
          body += "</ul>"
        end

        unless @options[:retry_on_error]['mail_config']['to'].is_a? Array
          @logger.warn "Deprecated mail_to format. Change to a Array of emails in the config file"
          ICarePT::Notifier.sendmail(@options[:retry_on_error]['mail_config']['to'].split(',').map{|e| e.strip}, subject, body, "text/html")
          @logger.info "Email sent to #{@options[:retry_on_error]['mail_config']['to']}"
        else
          ICarePT::Notifier.sendmail(@options[:retry_on_error]['mail_config']['to'], subject, body, "text/html")
          @logger.info "Email sent to #{@options[:retry_on_error]['mail_config']['to'].join(', ')}"
        end

      else
        @logger.info "Not sending email because 'to' field is empty" if with_error
      end

    end

  end   # class SftpExtractor
end   # module Cel

