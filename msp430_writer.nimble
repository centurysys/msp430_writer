# Package

version       = "0.1.0"
author        = "Takeyoshi Kikuchi"
description   = "MSP430 ISP writer"
license       = "MIT"
srcDir        = "src"
bin           = @["msp430_writer"]


# Dependencies

requires "nim >= 1.3.5"
requires "argparse >= 0.10.1"
