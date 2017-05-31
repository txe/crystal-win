# :nodoc:
class File::PReader
  include IO::Buffered

  getter? closed = false

  def initialize(@fd : Int32, @offset : Int32, @bytesize : Int32)
    @pos = 0
  end

  def unbuffered_read(slice : Bytes)
    check_open

    count = slice.size
    count = Math.min(count, @bytesize - @pos)
    bytes_read = -1

    {% if !flag?(:windows) %}
      bytes_read = LibC.pread(@fd, slice.pointer(count).as(Void*), count, @offset + @pos)
    {% else %}
      # emulate pread
      saved_pos = LibC._ltelli64(@fd)
      if saved_pos == -1
        raise Errno.new "Error reading file (_ltelli64)"
      end
      if LibC._lseeki64(@fd, @offset + @pos, LibC::SEEK_SET) == -1
        raise Errno.new "Error reading file (_lseeki64)"
      end
      bytes_read = LibC._read(@fd, slice.pointer(count).as(Void*), count)  
      if LibC._lseeki64(@fd, saved_pos, LibC::SEEK_SET) == -1
        raise Errno.new "Error reading file (_lseeki64)"
      end
    {% end %}
    
    if bytes_read == -1
      raise Errno.new "Error reading file"
    end

    @pos += bytes_read

    bytes_read
  end

  def unbuffered_write(slice : Bytes)
    raise IO::Error.new("Can't write to read-only IO")
  end

  def unbuffered_flush
    raise IO::Error.new("Can't flush read-only IO")
  end

  def unbuffered_rewind
    @pos = 0
  end

  def unbuffered_close
    @closed = true
  end
end
