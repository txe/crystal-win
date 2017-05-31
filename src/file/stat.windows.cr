class File
  struct Stat
    def initialize(@filename : String, @handle : LibWindows::Handle? = nil)
    end

    def get_handle(&block)
      # use given handle
      if @handle
        if (@handle == LibWindows::INVALID_HANDLE_VALUE)
          raise WinError.new("@handle == INVALID_HANDLE_VALUE")
        end
        yield @handle
      # otherwise get handle by file name
      else
        File.open @filename do | file |
          yield file.handle
        end
      end
    end

    # def atime
    #   {% if flag?(:darwin) %}
    #     time @stat.st_atimespec
    #   {% else %}
    #     time @stat.st_atim
    #   {% end %}
    # end
    # 
    # def blksize
    #   @stat.st_blksize
    # end

    # def blocks
    #   @stat.st_blocks
    # end

    # def ctime
    #   {% if flag?(:darwin) %}
    #     time @stat.st_ctimespec
    #   {% else %}
    #     time @stat.st_ctim
    #   {% end %}
    # end

    # def dev
    #   @stat.st_dev
    # end

    # def gid
    #   @stat.st_gid
    # end

    # def ino
    #   @stat.st_ino
    # end

    # def mode
    #   @stat.st_mode
    # end

    # # permission bits of mode
    # def perm
    #   mode & 0o7777
    # end

    def mtime : Time
      last_write_time = uninitialized LibWindows::FILETIME
      get_handle do | handle |
        if 0 == LibWindows.get_file_time(handle, nil, nil, pointerof(last_write_time))
          raise WinError.new("get_file_time")
        end
      end
      time (win_to_unix_epoch last_write_time)
    end

    # def nlink
    #   @stat.st_nlink
    # end

    # def rdev
    #   @stat.st_rdev
    # end

    def size : UInt64
      s = 0_u64
      get_handle do | handle |
        if LibWindows.get_file_size_ex(handle, pointerof(s)) == 0
          raise WinError.new("get_file_size_ex")
        end
      end
      s  
    end

    # def uid
    #   @stat.st_uid
    # end

    # def inspect(io)
    #   io << "#<File::Stat"
    #   io << " dev=0x"
    #   dev.to_s(16, io)
    #   io << ", ino=" << ino
    #   io << ", mode=0o"
    #   mode.to_s(8, io)
    #   io << ", nlink=" << nlink
    #   io << ", uid=" << uid
    #   io << ", gid=" << gid
    #   io << ", rdev=0x"
    #   rdev.to_s(16, io)
    #   io << ", size=" << size
    #   io << ", blksize=" << blksize
    #   io << ", blocks=" << blocks
    #   io << ", atime=" << atime
    #   io << ", mtime=" << mtime
    #   io << ", ctime=" << ctime
    #   io << ">"
    # end

    # def pretty_print(pp)
    #   pp.surround("#<File::Stat", ">", left_break: " ", right_break: nil) do
    #     pp.text "dev=0x#{dev.to_s(16)}"
    #     pp.comma
    #     pp.text "ino=#{ino}"
    #     pp.comma
    #     pp.text "mode=0o#{mode.to_s(8)}"
    #     pp.comma
    #     pp.text "nlink=#{nlink}"
    #     pp.comma
    #     pp.text "uid=#{uid}"
    #     pp.comma
    #     pp.text "gid=#{gid}"
    #     pp.comma
    #     pp.text "rdev=0x#{rdev.to_s(16)}"
    #     pp.comma
    #     pp.text "size=#{size}"
    #     pp.comma
    #     pp.text "blksize=#{blksize}"
    #     pp.comma
    #     pp.text "blocks=#{blocks}"
    #     pp.comma
    #     pp.text "atime=#{atime}"
    #     pp.comma
    #     pp.text "mtime=#{mtime}"
    #     pp.comma
    #     pp.text "ctime=#{ctime}"
    #   end
    # end

    # def blockdev?
    #   (@stat.st_mode & LibC::S_IFMT) == LibC::S_IFBLK
    # end

    # def chardev?
    #   (@stat.st_mode & LibC::S_IFMT) == LibC::S_IFCHR
    # end

    # def directory?
    #   (@stat.st_mode & LibC::S_IFMT) == LibC::S_IFDIR
    # end

    # def file?
    #   (@stat.st_mode & LibC::S_IFMT) == LibC::S_IFREG
    # end

    # def pipe?
    #   (@stat.st_mode & LibC::S_IFMT) == LibC::S_IFIFO
    # end

    # def setuid?
    #   (@stat.st_mode & LibC::S_IFMT) == LibC::S_ISUID
    # end

    # def setgid?
    #   (@stat.st_mode & LibC::S_IFMT) == LibC::S_ISGID
    # end

    # def symlink?
    #   (@stat.st_mode & LibC::S_IFMT) == LibC::S_IFLNK
    # end

    # def socket?
    #   (@stat.st_mode & LibC::S_IFMT) == LibC::S_IFSOCK
    # end

    # def sticky?
    #   (@stat.st_mode & LibC::S_IFMT) == LibC::S_ISVTX
    # end

    private def time(value)
      Time.new value, Time::Kind::Utc
    end

    private def win_to_unix_epoch(filetime : LibWindows::FILETIME)
      winticks = (filetime.dwHighDateTime.to_u64 << 32) | filetime.dwLowDateTime.to_u64
      # winticks start in 1601. unix in 1970.
      timespec = uninitialized LibC::Timespec
      timespec.tv_sec = (winticks / 10_000_000i64) - 11644473600i64
      timespec.tv_nsec = (winticks % 10_000_000) * 10
      timespec
    end
  end
end
