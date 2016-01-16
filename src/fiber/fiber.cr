@[NoInline]
fun get_stack_top : Void*
  dummy :: Int32
  pointerof(dummy) as Void*
end

require "ck/lib_ck"

class Fiber
  STACK_SIZE = 8 * 1024 * 1024

  @@first_fiber = nil
  @@last_fiber = nil
  @@stack_pool = [] of Void*
  @@fiber_list_mutex = Mutex.new
  @thread :: Void*

  # @@gc_lock = LibCK.rwlock_init
  @@gc_lock = LibCK.brlock_init
  @[ThreadLocal]
  @@gc_lock_reader = LibCK.brlock_reader_init

  protected property :stack_top
  protected property :stack_bottom
  protected property :next_fiber
  protected property :prev_fiber

  def initialize(&@proc)
    @thread = Pointer(Void).null
    @stack = Fiber.allocate_stack
    @stack_bottom = @stack + STACK_SIZE
    fiber_main = ->(f : Fiber) { f.run }

    stack_ptr = @stack + STACK_SIZE - sizeof(Void*)

    # Align the stack pointer to 16 bytes
    stack_ptr = Pointer(Void*).new(stack_ptr.address & ~0x0f_u64)

    # @stack_top will be the stack pointer on the initial call to `resume`
    ifdef x86_64
      # In x86-64, the context switch push/pop 7 registers
      @stack_top = (stack_ptr - 7) as Void*

      stack_ptr[0] = fiber_main.pointer # Initial `resume` will `ret` to this address
      stack_ptr[-1] = self as Void*     # This will be `pop` into %rdi (first argument)
    elsif i686
      # In IA32, the context switch push/pops 4 registers.
      # Add two more to store the argument of `fiber_main`
      @stack_top = (stack_ptr - 6) as Void*

      stack_ptr[0] = self as Void*       # First argument passed on the stack
      stack_ptr[-1] = Pointer(Void).null # Empty space to keep the stack alignment (16 bytes)
      stack_ptr[-2] = fiber_main.pointer # Initial `resume` will `ret` to this address
    else
      {{ raise "Unsupported platform, only x86_64 and i686 are supported." }}
    end

    @@fiber_list_mutex.synchronize do
      if last_fiber = @@last_fiber
        @prev_fiber = last_fiber
        last_fiber.next_fiber = @@last_fiber = self
      else
        @@first_fiber = @@last_fiber = self
      end
    end
  end

  def initialize
    @thread = LibPThread.self as Void*
    @proc = ->{}
    @stack = Pointer(Void).null
    @stack_top = get_stack_top
    @stack_bottom = LibGC.get_stackbottom

    Fiber.gc_register_thread

    @@fiber_list_mutex.synchronize do
      if last_fiber = @@last_fiber
        @prev_fiber = last_fiber
        last_fiber.next_fiber = @@last_fiber = self
      else
        @@first_fiber = @@last_fiber = self
      end
    end
  end

  protected def self.allocate_stack
    @@stack_pool.pop? || LibC.mmap(nil, Fiber::STACK_SIZE,
      LibC::PROT_READ | LibC::PROT_WRITE,
      LibC::MAP_PRIVATE | LibC::MAP_ANON,
      -1, LibC::SSizeT.new(0)).tap do |pointer|
      raise Errno.new("Cannot allocate new fiber stack") if pointer == LibC::MAP_FAILED
    end
  end

  def self.stack_pool_collect
    return if @@stack_pool.size == 0
    free_count = @@stack_pool.size > 1 ? @@stack_pool.size / 2 : 1
    free_count.times do
      stack = @@stack_pool.pop
      LibC.munmap(stack, Fiber::STACK_SIZE)
    end
  end

  def run
    Fiber.gc_read_unlock
    @proc.call
    @@stack_pool << @stack

    # Remove the current fiber from the linked list

    @@fiber_list_mutex.synchronize do
      if prev_fiber = @prev_fiber
        prev_fiber.next_fiber = @next_fiber
      else
        @@first_fiber = @next_fiber
      end

      if next_fiber = @next_fiber
        next_fiber.prev_fiber = @prev_fiber
      else
        @@last_fiber = @prev_fiber
      end
    end

    # Delete the resume event if it was used by `yield` or `sleep`
    if event = @resume_event
      event.free
    end

    Scheduler.reschedule
  end

  protected def self.gc_register_thread
    LibCK.brlock_read_register pointerof(@@gc_lock), pointerof(@@gc_lock_reader)
  end

  protected def self.gc_read_lock
    # LibCK.rwlock_read_lock pointerof(@@gc_lock)
    LibCK.brlock_read_lock pointerof(@@gc_lock), pointerof(@@gc_lock_reader)
  end

  protected def self.gc_read_unlock
    # LibCK.rwlock_read_unlock pointerof(@@gc_lock)
    LibCK.brlock_read_unlock pointerof(@@gc_lock_reader)
  end

  protected def self.gc_write_lock
    # LibCK.rwlock_write_lock pointerof(@@gc_lock)
    LibCK.brlock_write_lock pointerof(@@gc_lock)
  end

  protected def self.gc_write_unlock
    # LibCK.rwlock_write_unlock pointerof(@@gc_lock)
    LibCK.brlock_write_unlock pointerof(@@gc_lock)
  end

  @[NoInline]
  @[Naked]
  protected def self.switch_stacks(current, to)
    ifdef x86_64
      asm(%(
        pushq %rdi
        pushq %rbx
        pushq %rbp
        pushq %r12
        pushq %r13
        pushq %r14
        pushq %r15
        movq %rsp, ($0)
        movq ($1), %rsp
        popq %r15
        popq %r14
        popq %r13
        popq %r12
        popq %rbp
        popq %rbx
        popq %rdi)
              :: "r"(current), "r"(to))
    elsif i686
      asm(%(
        pushl %edi
        pushl %ebx
        pushl %ebp
        pushl %esi
        movl %esp, ($0)
        movl ($1), %esp
        popl %esi
        popl %ebp
        popl %ebx
        popl %edi)
              :: "r"(current), "r"(to))
    end
  end

  protected def thread=(@thread)
  end

  def resume
    Fiber.gc_read_lock
    current, @@current = @@current, self

    # LibGC.set_stackbottom LibPThread.self as Void*, @stack_bottom
    current.thread = Pointer(Void).null
    self.thread = LibPThread.self as Void*
    Fiber.switch_stacks(pointerof(current.@stack_top), pointerof(@stack_top))

    Fiber.gc_read_unlock
  end

  def sleep(time)
    event = @resume_event ||= Scheduler.create_resume_event(self)
    event.add(time)
    Scheduler.reschedule
  end

  def yield
    sleep(0)
  end

  def self.sleep(time)
    Fiber.current.sleep(time)
  end

  def self.yield
    Fiber.current.yield
  end

  protected def push_gc_roots
    # Push the used section of the stack
    LibGC.push_all_eager @stack_top, @stack_bottom
  end

  @@root = new

  def self.root
    @@root
  end

  @[ThreadLocal]
  @@current = root

  def self.current
    @@current
  end

  def self.current=(@@current)
  end

  @@prev_push_other_roots = LibGC.get_push_other_roots

  LibGC.set_start_callback ->do
    Fiber.gc_write_lock
  end

  # This will push all fibers stacks whenever the GC wants to collect some memory
  LibGC.set_push_other_roots ->do
    fiber = @@first_fiber
    while fiber
      if thread = fiber.@thread
        # LibC.printf "%lx\n", thread
        LibGC.set_stackbottom thread, fiber.@stack_bottom
      else
        fiber.push_gc_roots
      end

      fiber = fiber.next_fiber
    end

    @@prev_push_other_roots.call
    Fiber.gc_write_unlock
  end
end
