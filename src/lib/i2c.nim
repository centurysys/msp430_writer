import posix
import sequtils
import strformat

type
  I2cdev* = ref object
    fd: File
    address: uint8
    opened*: bool
  I2c_msg {.importc: "struct i2c_msg", header: "<linux/i2c.h>".} = object
    `addr`: cushort  # slave address
    flags: cushort
    len: cushort
    buf: cstring
  I2c_rdwr_ioctl_data {.importc: "struct i2c_rdwr_ioctl_data", header: "<linux/i2c-dev.h>".} = object
    msgs: ptr I2c_msg #  pointers to i2c_msgs
    nmsgs: cuint      #  number of i2c_msgs

const
  I2C_M_RD           = 0x0001  # read data, from slave to master
  I2C_M_TEN          = 0x0010  # this is a ten bit chip address
  I2C_M_DMA_SAFE     = 0x0200  # the buffer of this message is DMA safe
  I2C_M_RECV_LEN     = 0x0400  # length will be first received byte
  I2C_M_NO_RD_ACK    = 0x0800  # if I2C_FUNC_PROTOCOL_MANGLING
  I2C_M_IGNORE_NAK   = 0x1000  # if I2C_FUNC_PROTOCOL_MANGLING
  I2C_M_REV_DIR_ADDR = 0x2000  # if I2C_FUNC_PROTOCOL_MANGLING
  I2C_M_NOSTART      = 0x4000  # if I2C_FUNC_NOSTART
  I2C_M_STOP         = 0x8000  # if I2C_FUNC_PROTOCOL_MANGLING

const
  I2C_RDWR = 0x0707

# -------------------------------------------------------------------
#
# -------------------------------------------------------------------
proc i2c_open*(bus: int, address: uint8): I2cdev =
  let devname = fmt"/dev/i2c-{bus}"
  let fd = open(devname, fmReadWrite)
  result = new I2cdev
  result.fd = fd
  result.address = address
  result.opened = true

# -------------------------------------------------------------------
#
# -------------------------------------------------------------------
proc write_read*(i2c: I2cdev, writebuf: openArray[char|uint8], readlen: int): seq[char] =
  var packets: I2c_rdwr_ioctl_data
  var msgs: array[2, I2c_msg]
  var buf: array[256, char]

  # Setting up the register write
  msgs[0].`addr` = i2c.address.uint16
  msgs[0].flags = 0
  msgs[0].len = writebuf.len.uint16
  msgs[0].buf = cast[cstring](unsafeAddr writebuf)
  # Setting up the read
  msgs[1].`addr` = i2c.address.uint16
  msgs[1].flags = I2c_M_RD
  msgs[1].len = readlen.uint16
  msgs[1].buf = cast[cstring](addr buf)
  packets.msgs = addr msgs[0]
  packets.nmsgs = 2

  let res = posix.ioctl(i2c.fd.getFileHandle, I2C_RDWR, addr packets)
  if res < 0:
    return @[]
  result = newSeq[char](readlen)
  for idx in 0..<readlen:
    result[idx] = buf[idx]

# -------------------------------------------------------------------
#
# -------------------------------------------------------------------
proc write*(i2c: I2cdev, writebuf: openArray[char|uint8]): bool =
  var packets: I2c_rdwr_ioctl_data
  var msgs: array[1, I2c_msg]

  # Setting up the register write
  msgs[0].`addr` = i2c.address.uint16
  msgs[0].flags = 0
  msgs[0].len = writebuf.len.uint16
  msgs[0].buf = cast[cstring](unsafeAddr writebuf)
  packets.msgs = addr msgs[0]
  packets.nmsgs = 1

  let res = posix.ioctl(i2c.fd.getFileHandle, I2C_RDWR, addr packets)
  if res == 0:
    result = true
  else:
    result = false


when isMainModule:
  proc bcd2bin(bcd: char): int =
    result = (((bcd.uint8 and 0xf0) shr 4) * 10 + (bcd.uint8 and 0x0f)).int

  var i2c = i2c_open(1, 0x32)
  var wbuf: seq[uint8] = @[0'u8]

  var buf = i2c.write_read(wbuf, 0x0d + 1)
  echo fmt"buf lenght: {buf.len}"
  if buf.len > 0:
    try:
      let year = bcd2bin(buf[6]) + 2000
      let month = bcd2bin(buf[5])
      let day = bcd2bin(buf[4])
      let hour = bcd2bin(buf[2])
      let minute = bcd2bin(buf[1])
      let second = bcd2bin(buf[0])
      echo fmt"{year}/{month:02d}/{day:02d} {hour:02d}:{minute:02d}:{second:02d} [UTC]"
    except:
      echo "length error"
