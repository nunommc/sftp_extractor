require 'sftp_extractor/version'
require 'sftp_extractor/utils'
require 'sftp_extractor/downloader'

module SftpExtractor
  class NoFilesProcessedException < RuntimeError; end

end
