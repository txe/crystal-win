@[Link("icucore")]
lib LibICU
  type Converter = Void*
  alias ErrorCode = Int32

  fun ucnv_open(converter_name : LibC::Char*, err : ErrorCode*) : Converter
  fun ucnv_getNextUChar(converter : Converter, source : LibC::Char**, source_limit : LibC::Char*, err : ErrorCode*) : Int32
  fun ucnv_convertEx(targetCnv : Converter, sourceCnv : Converter, target : LibC::Char**, targetLimit : LibC::Char*,
                     source : LibC::Char**, sourceLimit : LibC::Char*,
                     pivotStart : UInt8*, pivotSource : UInt8**, pivotTarget : UInt8**, pivotLimit : UInt8*,
                     reset : UInt8, flush : UInt8, err : ErrorCode*)
end

class IO::Decoder
  BUFFER_SIZE = 1024

  def initialize(encoding)
    err = 0
    @source_icu = LibICU.ucnv_open(encoding, pointerof(err))
    # pp err

    err = 0
    @target_icu = LibICU.ucnv_open("UTF-8", pointerof(err))
    # pp err

    # @iconv = Iconv.new(encoding, "UTF-8")
    @buffer = Slice.new((GC.malloc_atomic(BUFFER_SIZE) as UInt8*), BUFFER_SIZE)
    @pivot = Slice.new((GC.malloc_atomic(BUFFER_SIZE) as UInt8*), BUFFER_SIZE)
    @pivot_start = @pivot.to_unsafe
    @pivot_source = @pivot_start
    @pivot_target = @pivot_start
    @pivot_limit = @pivot_start + BUFFER_SIZE
    @in_buffer = @buffer.to_unsafe
    @in_buffer_end = @in_buffer
    # @in_buffer_left = LibC::SizeT.new(0)
    # @last_errno = 0
  end

  def read_utf8(io, slice : Slice(UInt8))
    if @in_buffer == @in_buffer_end
      @in_buffer = @buffer.to_unsafe
      @in_buffer_end = @in_buffer + io.read(@buffer)
      # @in_buffer_left = LibC::SizeT.new(io.read(@buffer))
      # elsif @last_errno == Errno::EINVAL
      #   # EINVAL means "An incomplete multibyte sequence has been encountered in the input."
      #   buffer_remaining = BUFFER_SIZE - @in_buffer_left - (@in_buffer - @buffer.to_unsafe)
      #   if buffer_remaining < 64
      #     @buffer.copy_from(@in_buffer, @in_buffer_left)
      #     @in_buffer = @buffer.to_unsafe
      #     buffer_remaining = BUFFER_SIZE - @in_buffer_left
      #   end
      #   @in_buffer_left += LibC::SizeT.new(io.read(Slice.new(@in_buffer + @in_buffer_left, buffer_remaining)))
    end

    # out_buffer = slice.to_unsafe
    # out_buffer_left = LibC::SizeT.new(slice.size)

    target = slice.to_unsafe

    err = 0
    # pp err
    LibICU.ucnv_convertEx(@target_icu, @source_icu,
      pointerof(target), target + slice.size,
      pointerof(@in_buffer), @in_buffer_end,
      @pivot_start, pointerof(@pivot_source), pointerof(@pivot_target), @pivot_limit,
      0, 0, pointerof(err))

    target - slice.to_unsafe

    # total = 0
    # while @in_buffer != @in_buffer_end
    #   err = 0
    #   old_in_buffer = @in_buffer
    #   codepoint = LibICU.ucnv_getNextUChar(@icu, pointerof(@in_buffer), @in_buffer_end, pointerof(err))
    #   char = codepoint.chr
    #   bytesize = char.bytesize
    #   if bytesize > slice.size
    #     @in_buffer = old_in_buffer
    #     break
    #   end

    #   char.each_byte do |byte|
    #     slice.to_unsafe.value = byte
    #     slice += 1
    #   end

    #   total += bytesize
    # end

    # total
  end

  def read_char(io) : Char?
    info = read_char_with_bytesize(io)
    info ? info[0] : nil
  end

  private def read_char_with_bytesize(io)
    first = read_utf8_byte(io)
    return nil unless first

    first = first.to_u32
    return first.chr, 1 if first < 0x80

    second = read_utf8_masked_byte(io)
    return ((first & 0x1f) << 6 | second).chr, 2 if first < 0xe0

    third = read_utf8_masked_byte(io)
    return ((first & 0x0f) << 12 | (second << 6) | third).chr, 3 if first < 0xf0

    fourth = read_utf8_masked_byte(io)
    return ((first & 0x07) << 18 | (second << 12) | (third << 6) | fourth).chr, 4 if first < 0xf8

    raise InvalidByteSequenceError.new
  end

  private def read_utf8_masked_byte(io)
    byte = read_utf8_byte(io) || raise "Incomplete UTF-8 byte sequence"
    (byte & 0x3f).to_u32
  end

  def read_utf8_byte(io) : UInt8?
    byte = uninitialized UInt8
    if read_utf8(io, Slice.new(pointerof(byte), 1)) == 1
      byte
    else
      nil
    end
  end
end
