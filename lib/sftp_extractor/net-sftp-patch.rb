module Net; module SFTP; module Operations

  class Dir

    # Calls the block once for each entry in the named directory on the
    # remote server. Yields a Name object to the block, rather than merely
    # the name of the entry.
    def foreach(path)
      handle = sftp.opendir!(path)

      loop do
        entries = sftp.readdir(handle).wait
        break if entries.response.eof?
        raise "fail!" unless entries.response.ok?

        entries.response[:names].each { |entry| yield entry }
      end
      return nil
    ensure
      sftp.close!(handle) if handle
    end

  end

end; end; end