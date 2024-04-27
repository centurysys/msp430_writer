import unittest
import ../src/lib/crc


suite "CRC calculator":
  test "0x3B 0x00 --> CRC: 0xC460":
    let buf = @[0x3b'u8, 0x00'u8]
    check calcCrcCCITT(buf) == 0xc460'u16
  test "0x15 --> CRC: 0xA364":
    let buf = @[0x15'u8]
    check calcCrcCCITT(buf) == 0xa364'u16
  test "0x17 0x00 0x44 0x00 --> CRC: 0x0F42":
    let buf = @[0x17'u8, 0x00'u8, 0x44'u8, 0x00'u8]
    check calcCrcCCITT(buf) == 0x0f42'u16
