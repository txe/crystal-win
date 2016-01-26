class IO::Decoder
  BUFFER_SIZE = 1024

  def initialize(encoding)
    @iconv = Iconv.new(encoding, "UTF-8")
    @buffer = Slice.new((GC.malloc_atomic(BUFFER_SIZE) as UInt8*), BUFFER_SIZE)
    @in_buffer = @buffer.to_unsafe
    @in_buffer_left = LibC::SizeT.new(0)
    @last_errno = 0
  end

  def read_utf8(io, slice : Slice(UInt8))
    if @in_buffer_left == 0
      @in_buffer = @buffer.to_unsafe
      @in_buffer_left = LibC::SizeT.new(io.read(@buffer))
    elsif @last_errno == Errno::EINVAL
      # EINVAL means "An incomplete multibyte sequence has been encountered in the input."
      buffer_remaining = BUFFER_SIZE - @in_buffer_left - (@in_buffer - @buffer.to_unsafe)
      if buffer_remaining < 64
        @buffer.copy_from(@in_buffer, @in_buffer_left)
        @in_buffer = @buffer.to_unsafe
        buffer_remaining = BUFFER_SIZE - @in_buffer_left
      end
      @in_buffer_left += LibC::SizeT.new(io.read(Slice.new(@in_buffer + @in_buffer_left, buffer_remaining)))
    end

    out_buffer = slice.to_unsafe
    out_buffer_left = LibC::SizeT.new(slice.size)
    result = @iconv.convert(pointerof(@in_buffer), pointerof(@in_buffer_left), pointerof(out_buffer), pointerof(out_buffer_left))
    if result == -1
      @last_errno = Errno.value
    else
      @last_errno = 0
    end
    slice.size - out_buffer_left
  end
end
