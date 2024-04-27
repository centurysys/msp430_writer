# Package

version       = "0.2.0"
author        = "Takeyoshi Kikuchi"
description   = "MSP430 ISP writer"
license       = "MIT"
srcDir        = "src"
binDir        = "bin"
bin           = @["msp430_writer"]


# Dependencies

requires "nim >= 1.6.10"
requires "argparse == 0.10.1"
