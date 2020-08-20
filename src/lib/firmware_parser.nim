# =============================================================================
# TI-TXT format firmware parser
# =============================================================================
import strutils
import sequtils
import crc

type
  MemSegment* = ref object
    startAddress*: uint16
    buffer*: seq[char]
    crc*: uint16
  Firmware* = ref object
    segments*: seq[MemSegment]

# -------------------------------------------------------------------
#
# -------------------------------------------------------------------
proc load_firmware*(filename: string): Firmware =
  let fd = open(filename)
  defer:
    fd.close()

  var segment: MemSegment
  var in_section = false
  var ok = false
  while true:
    let line = fd.readLine().strip()
    if line == "q":
      ok = true
      break
    if line.startsWith("@"):
      if line.len != 5:
        quit("format error", 1)
      let startAddress = line[1..line.high].parseHexInt()
      segment = new MemSegment
      segment.startAddress = uint16(startAddress)
      if not in_section:
        result = new Firmware
      result.segments.add(segment)
      in_section = true
    else:
      if not in_section:
        quit("format error", 2)
      let bytes = line.split(" ").mapIt(uint8(it.parseHexInt()))
      for b in bytes:
        segment.buffer.add(char(b))
  for segment in result.segments:
    let crc_val = calc_CRC_CCITT(segment.buffer)
    segment.crc = crc_val

when isMainModule:
  import strformat

  let firm = load_firmware("firm.txt")
  for segment in firm.segments.items():
    echo fmt"* start address: {segment.startAddress:04x}"
    for idx in 0..segment.buffer.high:
      let pos = idx mod 16
      if pos == 0:
        stdout.write(fmt"{idx:04x}")
      stdout.write(fmt" {segment.buffer[idx]:02x}")
      if pos == 15:
        echo ""
    echo ""
    echo fmt"  section length: 0x{segment.buffer.len:04x}"
    echo fmt"  CRC: 0x{segment.crc:04x}"
