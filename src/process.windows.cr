require "c/stdlib"
{% if !flag?(:windows) %}
  require "c/signal"
  require "c/sys/times"
  require "c/sys/wait"
  require "c/unistd"
{% end %}

class Process
  # Terminate the current process immediately. All open files, pipes and sockets
  # are flushed and closed, all child processes are inherited by PID 1. This does
  # not run any handlers registered with `at_exit`, use `::exit` for that.
  #
  # *status* is the exit status of the current process.
  def self.exit(status = 0)
    LibC.exit(status)
  end

  # Returns the process identifier of the current process.
  # def self.pid : LibC::PidT
  #   {% if flag?(:windows) %}
  #     raise Exception.new("getpid is not implemented")
  #   {% else %}
  #     LibC.getpid
  #   {% end %}
  # end

  # Returns the process group identifier of the current process.
  # def self.pgid : LibC::PidT
  #   pgid(0)
  # end

  # Returns the process group identifier of the process identified by *pid*.
  # def self.pgid(pid : Int32) : LibC::PidT
  #   ret = LibC.getpgid(pid)
  #   raise Errno.new("getpgid") if ret < 0
  #   ret
  # end

  # Returns the process identifier of the parent process of the current process.
  # def self.ppid : LibC::PidT
  #   LibC.getppid
  # end

  # Sends a *signal* to the processes identified by the given *pids*.
  # def self.kill(signal : Signal, *pids : Int)
  #   pids.each do |pid|
  #     ret = LibC.kill(pid, signal.value)
  #     raise Errno.new("kill") if ret < 0
  #   end
  #   nil
  # end

  # Returns `true` if the process identified by *pid* is valid for
  # a currently registered process, `false` otherwise. Note that this
  # returns `true` for a process in the zombie or similar state.
  # def self.exists?(pid : Int)
  #   ret = LibC.kill(pid, 0)
  #   if ret == 0
  #     true
  #   else
  #     return false if Errno.value == Errno::ESRCH
  #     raise Errno.new("kill")
  #   end
  # end

  # A struct representing the CPU current times of the process,
  # in fractions of seconds.
  #
  # * *utime*: CPU time a process spent in userland.
  # * *stime*: CPU time a process spent in the kernel.
  # * *cutime*: CPU time a processes terminated children (and their terminated children) spent in the userland.
  # * *cstime*: CPU time a processes terminated children (and their terminated children) spent in the kernel.
  record Tms, utime : Float64, stime : Float64, cutime : Float64, cstime : Float64

  # Returns a `Tms` for the current process. For the children times, only those
  # of terminated children are returned.
  # def self.times : Tms
  #   hertz = LibC.sysconf(LibC::SC_CLK_TCK).to_f
  #   LibC.times(out tms)
  #   Tms.new(tms.tms_utime / hertz, tms.tms_stime / hertz, tms.tms_cutime / hertz, tms.tms_cstime / hertz)
  # end

  # Runs the given block inside a new process and
  # returns a `Process` representing the new child process.
  # def self.fork
  #   pid = fork_internal do
  #     with self yield self
  #   end
  #   new pid
  # end

  # Duplicates the current process.
  # Returns a `Process` representing the new child process in the current process
  # and `nil` inside the new child process.
  # def self.fork : self?
  #   if pid = fork_internal
  #     new pid
  #   else
  #     nil
  #   end
  # end

  # :nodoc:
  # protected def self.fork_internal(run_hooks : Bool = true, &block)
  #   pid = self.fork_internal(run_hooks)

  #   unless pid
  #     begin
  #       yield
  #       LibC._exit 0
  #     rescue ex
  #       ex.inspect STDERR
  #       STDERR.flush
  #       LibC._exit 1
  #     ensure
  #       LibC._exit 254 # not reached
  #     end
  #   end

  #   pid
  # end

  # *run_hooks* should ALWAYS be `true` unless `exec` is used immediately after fork.
  # Channels, `IO` and other will not work reliably if *run_hooks* is `false`.
  # protected def self.fork_internal(run_hooks : Bool = true)
  #   {% if flag?(:windows) %}
  #     raise Errno.new("fork not implemented")
  #   {% else %}
  #     pid = LibC.fork
  #     case pid
  #     when 0
  #       pid = nil
  #       Process.after_fork_child_callbacks.each(&.call) if run_hooks
  #     when -1
  #       raise Errno.new("fork")
  #     end
  #     pid
  #   {% end %}
  # end

  # The standard `IO` configuration of a process:
  #
  # * `nil`: use a pipe
  # * `false`: no `IO` (`/dev/null`)
  # * `true`: inherit from parent
  # * `IO`: use the given `IO`
  alias Stdio = Nil | Bool | IO
  alias Env = Nil | Hash(String, Nil) | Hash(String, String?) | Hash(String, String)

  # Executes a process and waits for it to complete.
  #
  # By default the process is configured without input, output or error.
  def self.run(command : String, args = nil, env : Env = nil, clear_env : Bool = false, shell : Bool = false, input : Stdio = false, output : Stdio = false, error : Stdio = false, chdir : String? = nil) : Process::Status
    status = new(command, args, env, clear_env, shell, input, output, error, chdir).wait
    $? = status
    status
  end

  # Executes a process, yields the block, and then waits for it to finish.
  #
  # By default the process is configured to use pipes for input, output and error. These
  # will be closed automatically at the end of the block.
  #
  # Returns the block's value.
  def self.run(command : String, args = nil, env : Env = nil, clear_env : Bool = false, shell : Bool = false, input : Stdio = nil, output : Stdio = nil, error : Stdio = nil, chdir : String? = nil)
    process = new(command, args, env, clear_env, shell, input, output, error, chdir)
    begin
      value = yield process
      $? = process.wait
      value
    rescue ex
      process.kill
      raise ex
    end
  end

  # Replaces the current process with a new one.
  #
  # The possible values for *input*, *output* and *error* are:
  # * `false`: no `IO` (`/dev/null`)
  # * `true`: inherit from parent
  # * `IO`: use the given `IO`
  # def self.exec(command : String, args = nil, env : Env = nil, clear_env : Bool = false, shell : Bool = false, input : Bool | IO::FileDescriptor = true, output : Bool | IO::FileDescriptor = true, error : Bool | IO::FileDescriptor = true, chdir : String? = nil)
  #   command, argv = prepare_argv(command, args, shell)
  #   exec_internal(command, argv, env, clear_env, input, output, error, chdir)
  # end

  # Process info
  @proc_info : LibWindows::Process_Information?
  @proc_status : Process::Status?

  # A pipe to this process's input. Raises if a pipe wasn't asked when creating the process.
  getter! input : IO::FileDescriptor

  # A pipe to this process's output. Raises if a pipe wasn't asked when creating the process.
  getter! output : IO::FileDescriptor

  # A pipe to this process's error. Raises if a pipe wasn't asked when creating the process.
  getter! error : IO::FileDescriptor

  # Creates a process, executes it, but doesn't wait for it to complete.
  #
  # To wait for it to finish, invoke `wait`.
  #
  # By default the process is configured without input, output or error.
  def initialize(command : String, args = nil, env : Env = nil, clear_env : Bool = false, shell : Bool = false, input : Stdio = false, output : Stdio = false, error : Stdio = false, chdir : String? = nil)
    cmd_line = Process.prepare_cmd_line(command, args, shell)
    
    @wait_count = 0

    if needs_pipe?(input)
      child_input, process_input = IO.pipe(read_blocking: true)
      if input
        @wait_count += 1
        spawn { copy_io(input, process_input, channel, close_dst: true) }
      else
        @input = process_input
      end
    end

    if needs_pipe?(output)
      process_output, child_output = IO.pipe(write_blocking: true)
      if output
        @wait_count += 1
        spawn { copy_io(process_output, output, channel, close_src: true) }
      else
        @output = process_output
      end
    end

    if needs_pipe?(error)
      process_error, child_error = IO.pipe(write_blocking: true)
      if error
        @wait_count += 1
        spawn { copy_io(process_error, error, channel, close_src: true) }
      else
        @error = process_error
      end
    end

    @proc_info = create_child_process(
      cmd_line, 
      shell,
      child_input, 
      child_output, 
      child_error, 
      chdir)
  end

  # :nodoc:
  private def create_child_process(cmd_line : String, shell, input, output, error, chdir) : LibWindows::Process_Information
    info = LibWindows::StartupInfoA.new
    info.cb = sizeof(typeof(info))
    info.hStdInput =  input.handle if input;
    info.hStdOutput = output.handle if output;
    info.hStdError = error.handle if error;
    info.dwFlags = LibWindows::STARTF_USESTDHANDLES;

    creationFlags = LibWindows::NORMAL_PRIORITY_CLASS | LibWindows::CREATE_NO_WINDOW
    p_info = LibWindows::Process_Information.new

    is_success = LibWindows.create_process(
      nil,        
      cmd_line.check_no_null_byte,      
      nil,          # process security attributes 
      nil,          # primary thread security attributes 
      1,            # handles are inherited 
      creationFlags, 
      nil,          # use parent's environment 
      nil,          # change work dir
      pointerof(info), 
      pointerof(p_info)) # receives PROCESS_INFORMATION
    
    # ReadFile hangs if these handles are not closed
    input.close if input
    output.close if output
    error.close if error

    if is_success == 0
      close
      raise WinError.new "CreateProcess"
    end

    p_info
  end

  # See also: `Process.kill`
  def kill
    # FIXME when do we need to clean up handles?
    if p = @proc_info
      LibWindows.kill_process(p.hProcess, -1)
    end
    nil
  end

  # Waits for this process to complete and closes any pipes.
  def wait : Process::Status      
    if @proc_status.nil?
      raise WinError.new "@proc_info == nil" if @proc_info.nil?

      close_io @input # only closed when a pipe was created but not managed by copy_io
      @wait_count.times do
        ex = channel.receive
        raise ex if ex
      end
      @wait_count = 0

      # FIXME: maybe we can attach handle to IOCP so we wouldn't block whole process
      if LibWindows.wait_for_single_object(@proc_info.try &.hProcess, LibWindows::INFINITY) != LibWindows::WAIT_OBJECT_0
        raise WinError.new "WaitForSingleObject"
      end
      if LibWindows.get_exit_code_process(@proc_info.try &.hProcess, out exit_code) == 0
        raise WinError.new "GetExitCodeProcess"
      end

      @proc_status = Process::Status.new exit_code.to_i32
    end
    @proc_status.not_nil!
  ensure
    close
  end

  # Whether the process is still registered in the system.
  # Note that this returns `true` for processes in the zombie or similar state.
  def exists?
    !terminated?
  end

  # Whether this process is already terminated.
  def terminated?
    @proc_nil.nil?
  end

  # Closes any pipes to the child process.
  def close
    close_io @input
    close_io @output
    close_io @error
    if @proc_info && @proc_info.try &.hProcess != LibWindows::INVALID_HANDLE_VALUE
      LibWindows.close_handle(@proc_info.try &.hProcess)
      LibWindows.close_handle(@proc_info.try &.hThread)
    end
    @proc_info = nil
  end

  # :nodoc:
  protected def self.prepare_cmd_line(command, args, shell)
    cmd_line = [] of String
    if shell
      cmd_line << "cmd.exe /c"
    end

    cmd_line << command
    args.try &.each do |arg|
      cmd_line << arg
    end

    cmd_line.join(" ")
  end

  private def channel
    @channel ||= Channel(Exception?).new
  end

  private def needs_pipe?(io)
    io.nil? || (io.is_a?(IO) && !io.is_a?(IO::FileDescriptor))
  end

  private def copy_io(src, dst, channel, close_src = false, close_dst = false)
    return unless src.is_a?(IO) && dst.is_a?(IO)

    begin
      IO.copy(src, dst)

      # close is called here to trigger exceptions
      # close must be called before channel.send or the process may deadlock
      src.close if close_src
      close_src = false
      dst.close if close_dst
      close_dst = false

      channel.send nil
    rescue ex
      channel.send ex
    ensure
      # any exceptions are silently ignored because of spawn
      src.close if close_src
      dst.close if close_dst
    end
  end

  private def close_io(io)
    io.close if io
  end
end

# Executes the given command in a subshell.
# Standard input, output and error are inherited.
# Returns `true` if the command gives zero exit code, `false` otherwise.
# The special `$?` variable is set to a `Process::Status` associated with this execution.
#
# If *command* contains no spaces and *args* is given, it will become
# its argument list.
#
# If *command* contains spaces and *args* is given, *command* must include
# `"${@}"` (including the quotes) to receive the argument list.
#
# No shell interpretation is done in *args*.
#
# Example:
#
# ```
# system("echo *")
# ```
#
# Produces:
#
# ```text
# LICENSE shard.yml Readme.md spec src
# ```
def system(command : String, args = nil) : Bool
  status = Process.run(command, args, shell: true, input: true, output: true, error: true)
  $? = status
  status.success?
end

# Returns the standard output of executing *command* in a subshell.
# Standard input, and error are inherited.
# The special `$?` variable is set to a `Process::Status` associated with this execution.
#
# Example:
#
# ```
# `echo hi` # => "hi\n"
# ```
def `(command) : String
    process = Process.new(command, shell: true, input: true, output: nil, error: true)
    output = process.output.gets_to_end
    status = process.wait
    $? = status
    output
end

# See also: `Process.fork`
# def fork
#   Process.fork { yield }
# end

# See also: `Process.fork`
# def fork
#   Process.fork
# end

require "./process/*"
