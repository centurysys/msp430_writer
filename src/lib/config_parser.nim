import std/sequtils
import std/strutils

type
  AppOptions* = object
    config*: string
    firmware*: string
    busnumber*: int
    address*: uint8
    chip*: string
    eraseOnly*: bool

# ---------------------------------------------------------
#
# ---------------------------------------------------------
proc parse_config*(path: string): AppOptions =
  for line in path.readFile.splitLines():
    if line.startsWith("#"):
      continue
    let parts = line.split(" = ").mapIt(it.strip)
    if parts.len != 2:
      continue
    try:
      case parts[0].toUpper
      of "FIRMWARE":
        result.firmware = parts[1]
      of "BUSNUMBER":
        result.busnumber = parts[1].parseInt
      of "ADDRESS":
        result.address = parts[1].parseHexInt.uint8
      of "CHIP":
        result.chip = parts[1]
    except:
      discard
