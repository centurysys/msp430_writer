# =============================================================================
# MSP430 In-System-Programmer
#
# Copyright(c) 2020-2024 Takeyoshi Kikuchi <kikuchi@centurysys.co.jp>
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
proc parseArgs(): AppOptions =
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
    result = parseConfig(opts.config)
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
proc invokeBsl(self: App) =
  stdout.write("* Invoke MSP430 BSL...")
  self.msp430reset.invokeBsl()
  echo "done."
  stdout.write("* Wait for BSL booting...")
  os.sleep(2200)
  echo "done."

# ---------------------------------------------------------
#
# ---------------------------------------------------------
proc unlockDevice(self: App): bool =
  var password: array[32, char]
  password.fill(0, password.high, 0xff.char)
  if self.msp430.unlockDevice(password):
    echo "* Unlock device succeeded."
    result = true
  else:
    echo "! Unlock device failed."
    result = false

# ---------------------------------------------------------
#
# ---------------------------------------------------------
proc massErase(self: App): bool =
  stdout.write("* Mass-erase device...")
  if self.msp430.massErase():
    echo "done."
    result = true
  else:
    echo "failed."
    result = false

# ---------------------------------------------------------
#
# ---------------------------------------------------------
proc loadFirmware(self: App, filename: string) =
  stdout.write(&"* Load firmware from file: {filename} ...")
  self.firmware = loadFirmware(filename)
  echo "done."

# ---------------------------------------------------------
#
# ---------------------------------------------------------
proc writeSegment(self: App, segment: MemSegment): bool =
  var
    address = segment.startAddress
    pos = 0
  const wr_unit = 16

  while pos < (segment.buffer.len - 1):
    let
      bytesRemain = segment.buffer.len - pos
      numWrite = if bytesRemain > wr_unit: wr_unit else: bytesRemain
      data = segment.buffer[pos..<(pos + numWrite)]

    var writeOk = false
    for retry in 0..<3:
      if self.msp430.sendData((address + pos.uint16).uint32, data):
        stderr.write(".")
        pos += numWrite
        os.sleep(2)
        writeOk = true
        break
      else:
        stderr.write("x")
        os.sleep(100)
    if not writeOk:
      echo &"\nwrite_segment failed at pos: {pos}"
      return false

  return true

# ---------------------------------------------------------
#
# ---------------------------------------------------------
proc writeFirmware(self: App): bool =
  for idx, segment in self.firmware.segments.pairs:
    stdout.write(&"* Writing segment No. {idx + 1} ")
    stdout.flushFile()
    if not self.writeSegment(segment):
      echo " Writing Firmware Failed."
      return false
    stdout.write(" OK.\n")
    stdout.flushFile()
  return true

# ---------------------------------------------------------
#
# ---------------------------------------------------------
proc verifySegment(self: App, segment: MemSegment): bool =
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
      chunk = self.msp430.readData(address + pos, readlen.int16)
    if chunk.len == 0:
      echo "! verifySegment: read failed."
      return false
    buf.add(chunk)
    pos += readlen
    remain -= readlen
  let crcBuf = calcCrcCCITT(buf)
  if crcBuf == segment.crc:
    result = true
  else:
    echo "! verifySegment: crc mismatch"
    return false

# ---------------------------------------------------------
#
# ---------------------------------------------------------
proc verifyFirmware(self: App): bool =
  for idx, segment in self.firmware.segments.pairs:
    var verify_ok = false

    for retry in 0..<3:
      stdout.write(&"* Verify segment No. {idx + 1} ...")
      stdout.flushFile()
      if self.verifySegment(segment):
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
proc runFirmware(self: App) =
  self.msp430reset.resetMcu()

# ---------------------------------------------------------
#
# ---------------------------------------------------------
proc main(): int =
  let app = new App
  let options = parseArgs()
  app.options = options
  echo "MSP430 firmware updater"
  app.msp430reset = newMsp430Reset(chip = options.chip)
  app.msp430 = newMsp430(options.busnumber, options.address)
  if app.msp430.isNil:
    quit("open I2C driver failed.", 1)

  app.loadFirmware(app.options.firmware)
  app.invokeBsl()

  let erased = app.massErase()
  if not erased:
    quit("Failed to do Mass-Erase.")

  if options.eraseOnly:
    quit(0)
  os.sleep(500)

  var unlockOk = false
  for i in 0..2:
    if app.unlockDevice():
      unlockOk = true
      break
    echo "! password not match, mass-erase."
    if i < 2:
      os.sleep(100)

  if not unlockOk:
    quit("Device unlock failed.", 1)

  os.sleep(500)

  if not app.writeFirmware():
    quit("write firmware failed.", 1)

  os.sleep(1000)

  if not app.verifyFirmware():
    quit("verify(CRC check) failed.", 1)

  app.runFirmware()
  quit(0)


when isMainModule:
  discard main()
