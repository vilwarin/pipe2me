require "tempfile"

class File
  def self.atomic_write(path, data=nil, &block)
    tmpfile = Tempfile.new(File.basename(path))
    tmpfile.write data if data
    data = block && yield
    tmpfile.write data if data
    tmpfile.close
    FileUtils.mv tmpfile.path, path           # atomic replace
    tmpfile.unlink                            # deletes the temp file
  rescue
    tmpfile.close! rescue nil                 # close and deletes the temp file
    raise
  end

  def self.secret(path, &block)
    unless exists?(path)
      secret = block_given? ? yield : SecureRandom.base64(16).gsub(/=+$/, "")
      atomic_write path, secret
    end
    read path
  end
end
