@[Link("iconv")]
lib LibIconv
  type Iconv = Void*

  fun open = iconv_open(tocode : LibC::Char*, fromcode : LibC::Char*) : Iconv
  fun iconv(cd : Iconv, inbuf : LibC::Char**, inbytesleft : LibC::SizeT*, outbuf : LibC::Char**, outbytesleft : LibC::SizeT*) : LibC::SizeT
  fun close = iconv_close(cd : Iconv) : LibC::Int
end

struct Iconv
  def initialize(from : String, to : String)
    @iconv = LibIconv.open(to, from)
    if @iconv.address == -1
      raise ArgumentError.new("invalid encoding")
    end
  end

  def self.new(from : String, to : String)
    iconv = new(from, to)
    begin
      yield iconv
    ensure
      iconv.close
    end
  end

  def convert(inbuf : UInt8**, inbytesleft : LibC::SizeT*, outbuf : UInt8**, outbytesleft : LibC::SizeT*)
    LibIconv.iconv(@iconv, inbuf, inbytesleft, outbuf, outbytesleft)
  end

  def close
    LibIconv.close(@iconv)
  end
end
