require "./sys/types"
require "./stdint"

lib LibC
  F_OK       = 0
  R_OK       = 4
  W_OK       = 2

  # FIXME: use _waccess
  fun _access(name : Char*, type : Int) : Int
end