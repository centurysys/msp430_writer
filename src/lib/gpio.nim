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
proc newGpio(gpioName: string): Gpio =
  let basedir = &"/sys/class/leds/{gpioName}"
  let nodeTrigger = &"{basedir}/trigger"
  let fdTrigger = open(nodeTrigger, fmReadWrite)
  defer:
    fdTrigger.close()
  fdTrigger.set($Trigger.None)
  let nodeValue = &"{basedir}/brightness"
  let fd = open(nodeValue, fmReadWrite)
  result = new Gpio
  result.name = gpioName
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
  let pinReset = if chip.len > 0: &"MSP430_{chip}_RST" else: "MSP430_RST"
  let pinTest = if chip.len > 0: &"MSP430_{chip}_TEST" else: "MSP430_TEST"
  result.test = newGpio(pinTest)
  result.reset = newGpio(pinReset)

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
