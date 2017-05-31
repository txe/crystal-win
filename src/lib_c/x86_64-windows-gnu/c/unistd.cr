require "./sys/types"
require "./stdint"

lib LibC
  F_OK       = 0
  R_OK       = 4
  W_OK       = 2

  SEEK_CUR   = 1  
  SEEK_END   = 2
  SEEK_SET   = 0
  
  # FIXME: use _waccess
  fun _access(name : Char*, type : Int32) : Int32
  fun _lseeki64(fd : Int32, offset : Int64, origin : Int32) : Int64
  fun _ltelli64(fd : Int32) : Int64
  fun _read(fd : Int32, buffer : Void*, count : UInt32) : Int32
end