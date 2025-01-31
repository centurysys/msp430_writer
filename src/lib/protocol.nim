# =============================================================================
# MSP430 BSL protocol
# =============================================================================
import std/options
import std/os
import ./crc
import ./i2c

type
  Msp430obj = object
    dev: I2cdev
  Msp430* = ref Msp430obj
  BslPacket* = object
    command: uint8
    address: uint32
    data: seq[char]
  BslVersionInfo* = object
    vendor: uint8
    interpreter: uint8
    api: uint8
    `interface`: uint8
  ResReason* {.pure.} = enum
    Ok = "OK"
    AckError = "Not ACK"
    HeaderError = "Invalid Header"
    LengthError = "Length Error"
    CrcError = "CRC Error"
  PktResponse* = object
    res*: bool
    reason*: ResReason

const
  CMD_SEND_DATA = 0x10
  CMD_SEND_PASSWORD = 0x11
  CMD_MASS_ERASE = 0x15
  CMD_CRC_CHECK = 0x16
  CMD_LOAD_PC = 0x17
  CMD_RECV_DATA = 0x18
  CMD_BSL_VERSION = 0x19
  #RESP_COMMAND = 0x3A
  #RESP_MESSAGE = 0x3B

const
  HEADER = 0x80.char
  ACK = 0x00.char

const
  SKIP_ADDRESS = 0xffffffff.uint32

func byte1[T](val: T): char =
  result = ((val and 0xff0000) shr 16).char

func byte2[T](val: T): char =
  result = ((val and 0x00ff00) shr 8).char

func byte3[T](val: T): char =
  result = (val and 0xff).char

func highbyte[T](val: T): char =
  result = ((val and 0xff00) shr 8).char

func lowbyte[T](val: T): char =
  result = (val and 0xff).char

func getUint16(payload: openArray[char], pos: int): uint16 =
  result = payload[pos].uint16 + (payload[pos + 1].uint16 shl 8)

# ---------------------------------------------------------
#
# ---------------------------------------------------------
proc newMsp430*(bus: int = 1, address: uint8 = 0x48, debug = false): Msp430 =
  let dev = newI2c(bus, address, debug)
  if not dev.opened:
    return nil
  result = new Msp430
  result.dev = dev

# ---------------------------------------------------------
#
# ---------------------------------------------------------
func checkResponse(payload: openArray[char]): PktResponse =
  result.res = false
  if payload[0] != ACK:
    # invalid header
    result.reason = ResReason.AckError
    return
  if payload[1] != HEADER:
    # invalid response header
    result.reason = ResReason.HeaderError
    return
  let length = int(payload.getUint16(2))
  if payload.len != length + 6:
    # invalid response length
    result.reason = ResReason.LengthError
    return
  let crcPkt = payload.getUint16(payload.len - 2)
  let crcCalc = calcCrcCCITT(payload[4..payload.len - 3])
  if crcPkt != crcCalc:
    # CRC error
    result.reason = ResReason.CrcError
    return
  result.reason = ResReason.Ok
  result.res = true

# ---------------------------------------------------------
#
# ---------------------------------------------------------
proc sendRecvI2cPacket(self: Msp430, packet: BslPacket, readlen: int,
    interval: int = 2): seq[char] =
  var xbuf = newSeqOfCap[char](packet.data.len + 8)
  xbuf.add(HEADER)
  var datalen = packet.data.len + 1
  if packet.address != SKIP_ADDRESS:
    datalen += 3
  xbuf.add(datalen.lowbyte)
  xbuf.add(datalen.highbyte)
  xbuf.add(packet.command.char)

  if packet.address != SKIP_ADDRESS:
    xbuf.add(packet.address.byte3)
    xbuf.add(packet.address.byte2)
    xbuf.add(packet.address.byte1)

  if datalen > 0:
    xbuf.add(packet.data)
  let crcVal = calcCrcCCITT(xbuf[3..xbuf.high])
  xbuf.add(crcVal.lowbyte)
  xbuf.add(crcVal.highbyte)

  let wrResult = self.dev.write(xbuf)
  if not wrResult:
    echo "! sendRecvI2cPacket: write failed."
    result = @[]
  else:
    os.sleep(interval)
    result = self.dev.read(readlen + 7)

# ---------------------------------------------------------
#
# ---------------------------------------------------------
proc sendI2cPacket(self: Msp430, packet: BslPacket): bool =
  var xbuf = newSeqOfCap[char](packet.data.len + 8)
  xbuf.add(HEADER)
  let datalen = packet.data.len + 1
  xbuf.add(datalen.lowbyte)
  xbuf.add(datalen.highbyte)
  xbuf.add(packet.command.char)

  if packet.address != SKIP_ADDRESS:
    xbuf.add(packet.address.byte1)
    xbuf.add(packet.address.byte2)
    xbuf.add(packet.address.byte3)

  if datalen > 0:
    xbuf.add(packet.data)
  let crcVal = calcCrcCCITT(xbuf[3..xbuf.high])
  xbuf.add(crcVal.lowbyte)
  xbuf.add(crcVal.highbyte)

  result = self.dev.write(xbuf)

# ---------------------------------------------------------
#
# ---------------------------------------------------------
proc invokeBsl*(self: Msp430, invokeStr: array[8, char]): bool =
  result = self.dev.write(invokeStr)

# ---------------------------------------------------------
# Command:0x10 : RX Data Block (4.1.5.1)
# ---------------------------------------------------------
proc sendData*(self: Msp430, address: uint32, buf: openArray[char]): bool =
  var packet: BslPacket
  packet.command = CMD_SEND_DATA
  packet.address = address
  packet.data = @buf
  let res = self.sendRecvI2cPacket(packet, 1)
  if res.len == 0:
    return false
  let pktState = checkResponse(res)
  return pktState.res

# ---------------------------------------------------------
# Command:0x11 : RX Password (4.1.5.2)
# ---------------------------------------------------------
proc unlockDevice*(self: Msp430, password: array[32, char]): bool =
  result = false
  var packet: BslPacket
  packet.command = CMD_SEND_PASSWORD
  packet.address = SKIP_ADDRESS
  packet.data = @password
  let res = self.sendRecvI2cPacket(packet, 1)
  if res.len == 0:
    return result
  let pktState = checkResponse(res)
  if pktState.res:
    # check result
    let msg = res[5]
    if msg == 0.char:
      result = true

# ---------------------------------------------------------
# Command:0x15 : Mass Erase (4.1.5.3)
# ---------------------------------------------------------
proc massErase*(self: Msp430): bool =
  var packet: BslPacket
  packet.command = CMD_MASS_ERASE
  packet.address = SKIP_ADDRESS
  packet.data = @[]
  let res = self.sendRecvI2cPacket(packet, 1)
  if res.len == 0:
    return false
  let pktState = checkResponse(res)
  return pktState.res

# ---------------------------------------------------------
# Command:0x16 : CRC Check (4.1.5.4)
# ---------------------------------------------------------
proc checkCrc*(self: Msp430, address: uint32, length: uint16): Option[uint16] =
  var packet: BslPacket
  packet.command = CMD_CRC_CHECK
  packet.address = address
  packet.data = newSeqOfCap[char](2)
  packet.data.add(length.lowbyte)
  packet.data.add(length.highbyte)
  let res = self.sendRecvI2cPacket(packet, 2, interval = 500)
  if res.len == 0:
    return none(uint16)
  var crcVal = res[5].uint16 + (res[6].uint16 shl 8)
  result = some(crcVal)

# ---------------------------------------------------------
# Command:0x17 : Load PC (4.1.5.5)
# ---------------------------------------------------------
proc setProgramCounter*(self: Msp430, address: uint16): bool =
  var packet: BslPacket
  packet.command = CMD_LOAD_PC
  packet.address = address
  packet.data = @[]
  result = self.sendI2cPacket(packet)

# ---------------------------------------------------------
# Command:0x18 : TX Data Block (4.1.5.6)
# ---------------------------------------------------------
proc readData*(self: Msp430, address: uint32, readlen: int16): seq[char] =
  var packet: BslPacket
  packet.command = CMD_RECV_DATA
  packet.address = address
  packet.data = newSeqOfCap[char](2)
  packet.data.add(readlen.lowbyte)
  packet.data.add(readlen.highbyte)
  let res = self.sendRecvI2cPacket(packet, readlen)
  if res.len == 0:
    return @[]
  let pktState = checkResponse(res)
  if not pktState.res:
    return @[]
  result = res[5..<(5 + readlen)]

# ---------------------------------------------------------
# Command:0x19 : TX BSL Version (4.1.5.7)
# ---------------------------------------------------------
proc getVersion*(self: Msp430): Option[BslVersionInfo] =
  var packet: BslPacket
  packet.command = CMD_BSL_VERSION
  packet.address = SKIP_ADDRESS
  packet.data = @[]
  let res = self.sendRecvI2cPacket(packet, 4)
  if res.len == 0:
    return none(BslVersionInfo)
  let pktState = checkResponse(res)
  if not pktState.res:
    return none(BslVersionInfo)
  var info: BslVersionInfo
  info.vendor = res[5].uint8
  info.interpreter = res[6].uint8
  info.api = res[7].uint8
  info.`interface` = res[8].uint8
  result = some(info)


when isMainModule:
  import std/algorithm
  import std/strformat

  var msp430 = newMsp430(debug = true)
  var password: array[32, char]
  password.fill(0xff.char)
  let unlockResult = msp430.unlockDevice(password)
  if not unlockResult:
    quit("unlock failed.")
  let resVersion = msp430.getVersion()
  if resVersion.isSome:
    let versionInfo = resVersion.get
    echo &"vendor: {versionInfo.vendor:02x}"
    echo &"interpreter: {versionInfo.interpreter:02x}"
    echo &"api: {versionInfo.api:02x}"
    echo &"interface: {versionInfo.`interface`:02x}"
  else:
    echo "failed"
