#require "c/dirent"
#require "errno"
#require "c/unistd"
#require "c/sys/stat"

# Objects of class `Dir` are directory streams representing directories in the underlying file system.
# They provide a variety of ways to list directories and their contents.
#
# The directory used in these examples contains the two regular files (`config.h` and `main.rb`),
# the parent directory (`..`), and the directory itself (`.`).
#
# See also: `File`.
fun __chkstk
end

class Dir
  include Enumerable(String)
  include Iterable(String)

  getter path : String

  # Returns a new directory object for the named directory.
  def initialize(@path)
    if !Dir.exists?(@path)
      raise WinError.new("Error opening directory '#{@path}'")
    end
    @handle = LibWindows::INVALID_HANDLE_VALUE
  end

  # Alias for `new(path)`
  def self.open(path) : self
    new path
  end

  # Opens a directory and yields it, closing it at the end of the block.
  # Returns the value of the block.
  def self.open(path)
    dir = new path
    begin
      yield dir
    ensure
      dir.close
    end
  end

  # Calls the block once for each entry in this directory,
  # passing the filename of each entry as a parameter to the block.
  #
  # ```
  # Dir.mkdir("testdir")
  # File.write("testdir/config.h", "")
  #
  # d = Dir.new("testdir")
  # d.each { |x| puts "Got #{x}" }
  # ```
  #
  # produces:
  #
  # ```text
  # Got .
  # Got ..
  # Got config.h
  # ```
  def each : Nil
    while entry = read
      yield entry
    end
  end

  def each
    EntryIterator.new(self)
  end

  # Reads the next entry from dir and returns it as a string. Returns `nil` at the end of the stream.
  #
  # ```
  # d = Dir.new("testdir")
  # array = [] of String
  # while file = d.read
  #   array << file
  # end
  # array.sort # => [".", "..", "config.h"]
  # ```
  def read
    data = LibWindows::WIN32_FIND_DATA_A.new
    if @handle == LibWindows::INVALID_HANDLE_VALUE
      @handle = LibWindows.find_first_file((path + "\\*").check_no_null_byte, pointerof(data))
      if @handle == LibWindows::INVALID_HANDLE_VALUE
        raise WinError.new("FindFirstFileA")
      end
    elsif LibWindows.find_next_file(@handle, pointerof(data)) == 0
      error = LibWindows.get_last_error()
      if error == WinError::ERROR_NO_MORE_FILES
        return nil
      else
        raise WinError.new("FindNextFileA", error)
      end
    end
    String.new(data.cFileName.to_slice)
  end

  # Repositions this directory to the first entry.
  def rewind
    close
    self
  end

  # Closes the directory stream.
  def close
    if @handle != LibWindows::INVALID_HANDLE_VALUE
      if LibWindows.find_close(@handle) == 0
        raise WinError.new("FindClose")
      end
      @handle = LibWindows::INVALID_HANDLE_VALUE
    end
  end

  # Returns the current working directory.
  def self.current : String
    len = LibWindows.get_current_directory(0, nil)
    if len == 0
      raise WinError.new("get_current_directory");
    end
    String.new(len) do |buffer|
      if LibWindows.get_current_directory(len, buffer) == 0
        raise WinError.new("get_current_directory")
      end
      {len-1, len-1} # remove \0 at the end
    end
  end

  # Changes the current working directory of the process to the given string.
  def self.cd(path)
    if LibWindows.set_current_directory(path.check_no_null_byte) == 0
      raise WinError.new("Error while changing directory to #{path.inspect}")
    end
  end

  # Changes the current working directory of the process to the given string
  # and invokes the block, restoring the original working directory
  # when the block exits.
  def self.cd(path)
    old = current
    begin
      cd(path)
      yield
    ensure
      cd(old)
    end
  end

  # Calls the block once for each entry in the named directory,
  # passing the filename of each entry as a parameter to the block.
  def self.foreach(dirname)
    Dir.open(dirname) do |dir|
      dir.each do |filename|
        yield filename
      end
    end
  end

  # Returns an array containing all of the filenames in the given directory.
  def self.entries(dirname) : Array(String)
    entries = [] of String
    foreach(dirname) do |filename|
      entries << filename
    end
    entries
  end

  # Returns `true` if the given path exists and is a directory
  def self.exists?(path) : Bool
    atr = LibWindows.get_file_attributes(path.check_no_null_byte);
    if (atr == LibWindows::INVALID_FILE_ATTRIBUTES)
      return false
    end
    return atr & LibWindows::FILE_ATTRIBUTE_DIRECTORY != 0
  end

  # Returns `true` if the directory at *path* is empty, otherwise returns `false`.
  # Raises `Errno` if the directory at *path* does not exist.
  #
  # ```
  # Dir.mkdir("bar")
  # Dir.empty?("bar") # => true
  # File.write("bar/a_file", "The content")
  # Dir.empty?("bar") # => false
  # ```
  def self.empty?(path) : Bool
    raise WinError.new("Error determining size of '#{path}'") unless Dir.exists?(path)

    foreach(path) do |f|
      return false unless {".", ".."}.includes?(f)
    end
    true
  end

  # Creates a new directory at the given path. The linux-style permission mode
  # can be specified, with a default of 777 (0o777).
  def self.mkdir(path, mode = 0o777)
    if LibWindows.create_directory(path.check_no_null_byte, nil) == 0
      raise WinError.new("Unable to create directory '#{path}'")
    end
    0
  end

  # Creates a new directory at the given path, including any non-existing
  # intermediate directories. The linux-style permission mode can be specified,
  # with a default of 777 (0o777).
  def self.mkdir_p(path, mode = 0o777)
    return 0 if Dir.exists?(path)

    components = path.split(File::SEPARATOR)
    if components.first == "." || components.first == ""
      subpath = components.shift
    else
      subpath = "."
    end

    components.each do |component|
      subpath = File.join subpath, component

      mkdir(subpath, mode) unless Dir.exists?(subpath)
    end

    0
  end

  # Removes the directory at the given path.
  def self.rmdir(path)
    if LibWindows.remove_directory(path.check_no_null_byte) == 0
      raise WinError.new("Unable to remove directory '#{path}'")
    end
    0
  end

  def to_s(io)
    io << "#<Dir:" << @path << ">"
  end

  def inspect(io)
    to_s(io)
  end

  def pretty_print(pp)
    pp.text inspect
  end

  private struct EntryIterator
    include Iterator(String)

    def initialize(@dir : Dir)
    end

    def next
      @dir.read || stop
    end

    def rewind
      @dir.rewind
      self
    end
  end
end

require "./dir/*"
