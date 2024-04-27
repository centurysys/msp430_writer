# =============================================================================
# GPIO(LED driver) access
# =============================================================================
import std/os
import std/strformat

type
  Trigger* {.pure.} = enum
    None = "none"
    Oneshot = "oneshot"
  GpioObj = object
    name: string
    basedir: string
    fd: File
  Gpio* = ref GpioObj
  Msp430ResetObj = object
    test: Gpio
    reset: Gpio
  Msp430Reset* = ref Msp430ResetObj

# -------------------------------------------------------------------
#
# -------------------------------------------------------------------
proc set(fd: File, val: string) =
  fd.setFilePos(0, fspSet)
  fd.write(&"{val}")
  fd.flushFile()

# -------------------------------------------------------------------
# GPIO (LED)
# -------------------------------------------------------------------
proc newGpio(gpio_name: string): Gpio =
  let basedir = &"/sys/class/leds/{gpio_name}"
  let node_trigger = &"{basedir}/trigger"
  let fd_trigger = open(node_trigger, fmReadWrite)
  defer:
    fd_trigger.close()
  fd_trigger.set($Trigger.None)
  let node_value = &"{basedir}/brightness"
  let fd = open(node_value, fmReadWrite)
  result = new Gpio
  result.name = gpio_name
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
proc newMsp430Reset*(chip: string = ""): Msp430Reset =
  result = new Msp430Reset
  let pin_reset = if chip.len > 0: &"MSP430_{chip}_RST" else: "MSP430_RST"
  let pin_test = if chip.len > 0: &"MSP430_{chip}_TEST" else: "MSP430_TEST"
  result.test = newGpio(pin_test)
  result.reset = newGpio(pin_reset)

# -------------------------------------------------------------------
#
# -------------------------------------------------------------------
proc invokeBsl*(self: Msp430Reset) =
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
proc resetMcu*(self: Msp430Reset) =
  self.test.set(false)
  self.reset.set(true)
  os.sleep(10)
  # RESET -> H
  self.reset.set(false)


when isMainModule:
  let msp430 = newMsp430Reset()
  msp430.invokeBsl()
