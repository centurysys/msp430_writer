# =============================================================================
# MSP430 In-System-Programmer
#
# Copyright(c) 2020 Takeyoshi Kikuchi <kikuchi@centurysys.co.jp>
# =============================================================================
import algorithm
import options
import os
import strformat
import argparse
import lib/gpio
import lib/protocol
import lib/firmware_parser

type
  AppOptions = object
    firmware*: string
    busnumber*: int
    address*: uint8
  App = ref object
    msp430: Msp430
    msp430reset: Msp430Reset
    firmware: Firmware
    options: AppOptions

# ---------------------------------------------------------
#
# ---------------------------------------------------------
proc parse_args(): AppOptions =
  var p = newParser("msp430_writer"):
    argparse.option("-f", "--firmware",
                    help = "Firmware filename(TI-TXT format)")
    argparse.option("-b", "--busnum", default = "1",
                    help = "I2C bus number")
    argparse.option("-a", "--address", default = "0x48",
                    help = "MSP430 address")
  var opts = p.parse()
  result.firmware = opts.firmware
  result.busnumber = opts.busnum.parseInt
  result.address = opts.address.parseHexInt.uint8
  if opts.help:
    quit(1)

# ---------------------------------------------------------
#
# ---------------------------------------------------------
proc invoke_bsl(self: App) =
  stdout.write("* Invoke MSP430 BSL...")
  self.msp430reset.invoke_bsl()
  echo "done."
  stdout.write("* Wait for BSL booting...")
  os.sleep(2200)
  echo "done."

# ---------------------------------------------------------
#
# ---------------------------------------------------------
proc unlock_device(self: App): bool =
  var password: array[32, char]
  password.fill(0, password.high, 0xff.char)
  if self.msp430.unlock_device(password):
    echo "* Unlock device succeeded."
    result = true
  else:
    echo "* Unlock device failed."
    result = false

# ---------------------------------------------------------
#
# ---------------------------------------------------------
proc mass_erase(self: App): bool =
  stdout.write(fmt"* Mass-erase device...")
  if self.msp430.mass_erase():
    echo "done."
    result = true
  else:
    echo "failed."
    result = false

# ---------------------------------------------------------
#
# ---------------------------------------------------------
proc load_firmware(self: App, filename: string) =
  stdout.write(fmt"* Load firmware from file: {filename} ...")
  self.firmware = load_firmware(filename)
  echo "done."

# ---------------------------------------------------------
#
# ---------------------------------------------------------
proc write_segment(self: App, segment: MemSegment): bool =
  var address = segment.startAddress
  var pos = 0
  let wr_unit = 16

  while pos < (segment.buffer.len - 1):
    let bytes_remain = segment.buffer.len - pos
    let num_write = if bytes_remain > wr_unit: wr_unit else: bytes_remain
    let data = segment.buffer[pos..<(pos + num_write)]
    if self.msp430.send_data((address + pos.uint16).uint32, data):
      stderr.write(".")
      pos += num_write
      os.sleep(10)
    else:
      echo fmt"\nwrite_segment failed at pos: {pos}"
      return false

  stderr.write("\n")
  return true

# ---------------------------------------------------------
#
# ---------------------------------------------------------
proc write_firmware(self: App): bool =
  for segment in self.firmware.segments:
    if not self.write_segment(segment):
      return false
  return true

# ---------------------------------------------------------
#
# ---------------------------------------------------------
proc verify_segment(self: App, segment: MemSegment): bool =
  let address = segment.startAddress
  let segment_len = segment.buffer.len
  let crc_val = self.msp430.check_crc(address, segment_len.uint16)
  if not crc_val.isSome:
    return false
  result = (crc_val.get == segment.crc)

# ---------------------------------------------------------
#
# ---------------------------------------------------------
proc verify_firmware(self: App): bool =
  for idx, segment in self.firmware.segments.mpairs:
    var verify_ok = false

    for retry in 0..<3:
      stdout.write(fmt"* CRC Check segment No. {idx + 1} ...")
      if self.verify_segment(segment):
        echo "OK."
        verify_ok = true
        os.sleep(100)
        break
      else:
        echo "Failed."
        os.sleep(500)
    if not verify_ok:
      return false

  return true

# ---------------------------------------------------------
#
# ---------------------------------------------------------
proc run_firmware(self: App) =
  self.msp430reset.reset_mcu()

# ---------------------------------------------------------
#
# ---------------------------------------------------------
proc main(): int =
  var app = new App
  let options = parse_args()
  app.options = options
  echo "MSP430 firmware updater"
  app.msp430reset = msp430reset_init()
  app.msp430 = msp430_open(options.busnumber, options.address)
  if app.msp430.isNil:
    quit("open I2C driver failed.", 1)

  app.load_firmware(app.options.firmware)

  var unlock_ok = false
  for i in 0..2:
    app.invoke_bsl()
    if app.unlock_device():
      unlock_ok = true
      break
    if i < 2:
      os.sleep(1)

  if not unlock_ok:
    quit("Device unlock failed.", 1)

  discard app.mass_erase()
  os.sleep(1)

  if not app.write_firmware():
    quit("write firmware failed.")
  os.sleep(1)
  if not app.verify_firmware():
    quit("verify(CRC check) failed.")

  app.run_firmware()
  quit(0)

when isMainModule:
  discard main()
