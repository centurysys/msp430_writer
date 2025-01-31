# =============================================================================
# TI-TXT format firmware parser
# =============================================================================
import std/strutils
import std/sequtils
import ./crc

type
  MemSegmentObj = object
    startAddress*: uint16
    buffer*: seq[char]
    crc*: uint16
  MemSegment* = ref MemSegmentObj
  FirmwareObj = object
    segments*: seq[MemSegment]
  Firmware* = ref FirmwareObj

# -------------------------------------------------------------------
#
# -------------------------------------------------------------------
proc loadFirmware*(filename: string): Firmware =
  let fd = open(filename)
  defer:
    fd.close()

  var
    segment: MemSegment
    inSection = false
    ok = false
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
      if not inSection:
        result = new Firmware
      result.segments.add(segment)
      inSection = true
    else:
      if not inSection:
        quit("format error", 2)
      let bytes = line.split(" ").mapIt(uint8(it.parseHexInt()))
      for b in bytes:
        segment.buffer.add(char(b))
  if not ok or result.isNil:
    quit("format error", 3)
  for segment in result.segments:
    let crcVal = calcCrcCCITT(segment.buffer)
    segment.crc = crcVal


when isMainModule:
  import strformat

  let firm = loadFirmware("firm.txt")
  for segment in firm.segments.items():
    echo &"* start address: {segment.startAddress:04x}"
    for idx in 0..segment.buffer.high:
      let pos = idx mod 16
      if pos == 0:
        stdout.write(&"{idx:04x}")
      stdout.write(&" {segment.buffer[idx]:02x}")
      if pos == 15:
        echo ""
    echo ""
    echo &"  section length: 0x{segment.buffer.len:04x}"
    echo &"  CRC: 0x{segment.crc:04x}"
