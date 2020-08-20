# =============================================================================
# GPIO(LED driver) access
# =============================================================================
import os
import strformat

type
  Trigger* {.pure.} = enum
    None = "none"
    Oneshot = "oneshot"
  Gpio* = ref object
    name: string
    basedir: string
    fd: File
  GpioDir {.pure.} = enum
    Reset = "MSP430_RST"
    Test = "MSP430_TEST"
  Msp430Reset* = ref object
    test: Gpio
    reset: Gpio

# -------------------------------------------------------------------
#
# -------------------------------------------------------------------
proc set(fd: File, val: string) =
  fd.setFilePos(0, fspSet)
  fd.write(fmt"{val}")
  fd.flushFile()

# -------------------------------------------------------------------
# GPIO (LED)
# -------------------------------------------------------------------
proc gpio_open(gpio: GpioDir): Gpio =
  let basedir = fmt"/sys/class/leds/{gpio}"
  let nodetrigger = fmt"{basedir}/trigger"
  let fd_trigger = open(node_trigger, fmReadWrite)
  defer:
    fd_trigger.close()
  fd_trigger.set($Trigger.None)
  let node_value = fmt"{basedir}/brightness"
  let fd = open(node_value, fmReadWrite)
  result = new Gpio
  result.name = $gpio
  result.basedir = basedir
  result.fd = fd

# -------------------------------------------------------------------
#
# -------------------------------------------------------------------
proc set(gpio: Gpio, state: bool) =
  let value = if state: 255 else: 0
  gpio.fd.set($value)

# -------------------------------------------------------------------
#
# -------------------------------------------------------------------
proc wait(msec: int) =
  os.sleep(msec)

# -------------------------------------------------------------------
# MSP430 Reset
# -------------------------------------------------------------------
proc msp430reset_init*(): Msp430Reset =
  result = new Msp430Reset
  result.test = gpio_open(GpioDir.Test)
  result.reset = gpio_open(GpioDir.Reset)

# -------------------------------------------------------------------
#
# -------------------------------------------------------------------
proc invoke_bsl*(self: Msp430Reset) =
  # TEST -> L
  self.test.set(false)
  # RESET -> L
  self.reset.set(true)
  wait(10)

  # TEST -> H
  self.test.set(true)
  wait(10)
  # TEST -> L
  self.test.set(false)
  wait(10)

  # TEST -> H
  self.test.set(true)
  wait(10)
  # RESET -> H
  self.reset.set(false)
  wait(10)
  # TEST -> L
  self.test.set(false)

# -------------------------------------------------------------------
#
# -------------------------------------------------------------------
proc reset_mcu*(self: Msp430Reset) =
  self.test.set(false)
  self.reset.set(true)
  os.sleep(10)
  # RESET -> H
  self.reset.set(false)


when isMainModule:
  let msp430 = msp430reset_init()
  msp430.invoke_bsl()
