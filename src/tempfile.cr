require "c/stdlib"

# The `Tempfile` class is for managing temporary files.
# Every tempfile is operated as a `File`, including
# initializing, reading and writing.
#
# ```
# tempfile = Tempfile.new("foo")
# # or
# tempfile = Tempfile.open("foo") { |file|
#   file.print("foobar")
# }
#
# File.size(tempfile.path)       # => 6
# File.stat(tempfile.path).mtime # => 2015-10-20 13:11:12 UTC
# File.exists?(tempfile.path)    # => true
# File.read_lines(tempfile.path) # => ["foobar"]
# ```
#
# Files created from this class are stored in a directory that handles
# temporary files.
#
# ```
# Tempfile.new("foo").path # => "/tmp/foo.ulBCPS"
# ```
#
# Also, it is encouraged to delete a tempfile after using it, which
# ensures they are not left behind in your filesystem until garbage collected.
#
# ```
# tempfile = Tempfile.new("foo")
# tempfile.unlink
# ```
class Tempfile < IO::FileDescriptor
  # Creates a `Tempfile` with the given filename.
  {% if flag?(:windows) %}
    def initialize(name)
      tmpdir = self.class.dirname
      @path = String.new(260) do | buffer |
        if 0 == LibWindows.get_temp_file_name(tmpdir.check_no_null_byte, "", 0, name.check_no_null_byte)
          raise WinError.new("get_temp_file_name")
        end
        len = LibC.strlen(buffer)
        {len, len}
      end
        
      access = LibWindows::GENERIC_READ | LibWindows::GENERIC_WRITE
      creation = LibWindows::CREATE_ALWAYS
      flags = LibWindows::FILE_FLAG_OVERLAPPED
      handle = LibWindows.create_file(@path.check_no_null_byte, access, 0, nil, creation, flags, nil)
      if handle == LibWindows::INVALID_HANDLE_VALUE
        raise WinError.new("TempFIle")
      end
      super(handle, blocking: true)
    end
  {% else %}
    def initialize(name)
      tmpdir = self.class.dirname + File::SEPARATOR
      @path = "#{tmpdir}#{name}.XXXXXX"
      fileno = LibC.mkstemp(@path)
      if fileno == -1
        raise Errno.new("mkstemp")
      end
      super(fileno, blocking: true)
    end
  {% end %}

  # Retrieves the full path of a this tempfile.
  #
  # ```
  # Tempfile.new("foo").path # => "/tmp/foo.ulBCPS"
  # ```
  getter path : String

  # Creates a file with *filename*, and yields it to the given block.
  # It is closed and returned at the end of this method call.
  #
  # ```
  # tempfile = Tempfile.open("foo") { |file|
  #   file.print("bar")
  # }
  # File.read(tempfile.path) # => "bar"
  # ```
  def self.open(filename)
    tempfile = Tempfile.new(filename)
    begin
      yield tempfile
    ensure
      tempfile.close
    end
    tempfile
  end

  # Returns the tmp dir used for tempfile.
  #
  # ```
  # Tempfile.dirname # => "/tmp"
  # ```
  def self.dirname : String
    {% if flag?(:winsows) %}
      tmpdir = String.new(260) do |buffer|
        len = LibWindows.get_full_path_name(buf, 260)
        if len == 0 || len > 260
          raise WinError.new("Error resolving temp dir")
        end
        {len, len}
      end
      File.dirname(tmpdir)
    {% else %}
      unless tmpdir = ENV["TMPDIR"]?
        tmpdir = "/tmp"
      end
      tmpdir = tmpdir + File::SEPARATOR unless tmpdir.ends_with? File::SEPARATOR
      File.dirname(tmpdir)
    {% end %}
  end

  # Deletes this tempfile.
  def delete
    File.delete(@path)
  end

  # ditto
  def unlink
    delete
  end
end
