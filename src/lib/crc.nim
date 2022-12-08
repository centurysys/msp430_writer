# =============================================================================
# CRC-CCITT(0xffff) for MSP430 BSL
# =============================================================================

func createCrcTable(poly: uint16): array[0..255, uint16] =
  for i in 0..255:
    var
      crc = 0'u16
      c: uint16 = uint16(i) shl 8
    for j in 0..7:
      if ((crc xor c) and 0x8000) > 0:
        crc = (crc shl 1) xor poly
      else:
        crc = crc shl 1
      c = c shl 1
    result[i] = crc

const crcTable = createCrcTable(0x1021)

func calc_CRC_CCITT*(buf: openArray[char|uint8]): uint16 =
  result = uint16(0xffff)
  for i in 0..buf.high:
    result = (result shl 8) xor crcTable[((result shr 8) xor uint8(buf[i])) and 0x00ff]


when isMainModule:
  import strformat
  import sequtils

  let buf: seq[uint8] = @[0x15'u8]
  let buf2: seq[uint8] = @[0x3b'u8, 0x00'u8]
  var crc: uint16

  crc = calc_CRC_CCITT(buf)
  echo &"CRC-CCITT: {buf} -> 0x{crc:04x}"
  crc = calc_CRC_CCITT(buf2)
  echo &"CRC-CCITT: {buf2} -> 0x{crc:04x}"

  let s = "hogehoge".toSeq
  echo &"CRC-CCITT: {s} -> 0x{calc_CRC_CCITT(s):04x}"
