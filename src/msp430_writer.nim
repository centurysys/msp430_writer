# =============================================================================
# MSP430 In-System-Programmer
#
# Copyright(c) 2020-2022 Takeyoshi Kikuchi <kikuchi@centurysys.co.jp>
# =============================================================================
import std/algorithm
import std/os
import std/strformat
import argparse
import lib/config_parser
import lib/crc
import lib/gpio
import lib/protocol
import lib/firmware_parser

type
  AppObj = object
    msp430: Msp430
    msp430reset: Msp430Reset
    firmware: Firmware
    options: AppOptions
  App = ref AppObj

# ---------------------------------------------------------
#
# ---------------------------------------------------------
proc parse_args(): AppOptions =
  let p = newParser("msp430_writer"):
    argparse.option("-c", "--config",
        help = "config file")
    argparse.option("-f", "--firmware",
        help = "Firmware filename(TI-TXT format)")
    argparse.flag("-e", "--erase-only",
        help = "Mass-Erase only")
    argparse.option("-b", "--busnum", default = "1",
        help = "I2C bus number")
    argparse.option("-a", "--address", default = "0x48",
        help = "MSP430 address")
    argparse.option("-s", "--chip", default = "",
        help = "MSP430 select chip")
  let opts = p.parse()
  if opts.help:
    quit(1)
  if opts.config.len > 0:
    result = parse_config(opts.config)
  if result.firmware.len == 0:
    result.firmware = opts.firmware
  if result.busnumber == 0:
    result.busnumber = opts.busnum.parseInt
  if result.address == 0:
    result.address = opts.address.parseHexInt.uint8
  if result.chip.len == 0 and opts.chip.len > 0:
    result.chip = opts.chip
  if opts.eraseOnly:
    result.eraseOnly = true

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
    echo "! Unlock device failed."
    result = false

# ---------------------------------------------------------
#
# ---------------------------------------------------------
proc mass_erase(self: App): bool =
  stdout.write("* Mass-erase device...")
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
  stdout.write(&"* Load firmware from file: {filename} ...")
  self.firmware = load_firmware(filename)
  echo "done."

# ---------------------------------------------------------
#
# ---------------------------------------------------------
proc write_segment(self: App, segment: MemSegment): bool =
  var
    address = segment.startAddress
    pos = 0
  const wr_unit = 16

  while pos < (segment.buffer.len - 1):
    let
      bytes_remain = segment.buffer.len - pos
      num_write = if bytes_remain > wr_unit: wr_unit else: bytes_remain
      data = segment.buffer[pos..<(pos + num_write)]

    var write_ok = false
    for retry in 0..<3:
      if self.msp430.send_data((address + pos.uint16).uint32, data):
        stderr.write(".")
        pos += num_write
        os.sleep(2)
        write_ok = true
        break
      else:
        stderr.write("x")
        os.sleep(100)
    if not write_ok:
      echo &"\nwrite_segment failed at pos: {pos}"
      return false

  return true

# ---------------------------------------------------------
#
# ---------------------------------------------------------
proc write_firmware(self: App): bool =
  for idx, segment in self.firmware.segments.pairs:
    stdout.write(&"* Writing segment No. {idx + 1} ")
    stdout.flushFile()
    if not self.write_segment(segment):
      echo " Writing Firmware Failed."
      return false
    stdout.write(" OK.\n")
    stdout.flushFile()
  return true

# ---------------------------------------------------------
#
# ---------------------------------------------------------
proc verify_segment(self: App, segment: MemSegment): bool =
  let
    address = segment.startAddress.uint32
    segment_len = segment.buffer.len
  const chunksize = 16'u16
  var
    buf = newSeqOfCap[char](segment_len)
    pos = 0'u32
    remain = segment_len.uint16

  while remain > 0:
    let
      readlen = if remain > chunksize: chunksize else: remain
      chunk = self.msp430.read_data(address + pos, readlen.int16)
    if chunk.len == 0:
      echo "! verify_segment: read failed."
      return false
    buf.add(chunk)
    pos += readlen
    remain -= readlen
  let crc_buf = calc_CRC_CCITT(buf)
  if crc_buf == segment.crc:
    result = true
  else:
    echo "! verify_segment: crc mismatch"
    return false

# ---------------------------------------------------------
#
# ---------------------------------------------------------
proc verify_firmware(self: App): bool =
  for idx, segment in self.firmware.segments.pairs:
    var verify_ok = false

    for retry in 0..<3:
      stdout.write(&"* Verify segment No. {idx + 1} ...")
      stdout.flushFile()
      if self.verify_segment(segment):
        echo " OK."
        verify_ok = true
        os.sleep(100)
        break
      else:
        echo " Failed."
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
  let app = new App
  let options = parse_args()
  app.options = options
  echo "MSP430 firmware updater"
  app.msp430reset = newMsp430Reset(chip = options.chip)
  app.msp430 = newMsp430(options.busnumber, options.address)
  if app.msp430.isNil:
    quit("open I2C driver failed.", 1)

  app.load_firmware(app.options.firmware)
  app.invoke_bsl()

  let erased = app.mass_erase()
  if not erased:
    quit("Failed to do Mass-Erase.")

  if options.eraseOnly:
    quit(0)
  os.sleep(500)

  var unlock_ok = false
  for i in 0..2:
    if app.unlock_device():
      unlock_ok = true
      break
    echo "! password not match, mass-erase."
    if i < 2:
      os.sleep(100)

  if not unlock_ok:
    quit("Device unlock failed.", 1)

  os.sleep(500)

  if not app.write_firmware():
    quit("write firmware failed.", 1)

  os.sleep(1000)

  if not app.verify_firmware():
    quit("verify(CRC check) failed.", 1)

  app.run_firmware()
  quit(0)


when isMainModule:
  discard main()
