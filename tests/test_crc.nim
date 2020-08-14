import unittest
import ../src/lib/crc


suite "CRC calculatior":
  test "3B 00 --> CRC: 0xC460":
    let buf = @[0x3b'u8, 0x00'u8]
    check calc_CRC_CCITT(buf) == 0xc460'u16
