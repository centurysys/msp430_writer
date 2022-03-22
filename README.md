# MSP430 firmware writer

## How to Build

[Nim](http://nim-lang.org/) と ARM用クロスコンパイラが必要です。\
ビルドは nimble を用いた通常の方法でビルドします。\
標準で ARM 用バイナリを出力する設定にしてあります。

    $ nimble build -d:release

## Usage

MSP430用ファームウェアをTI-TXT形式で出力し、MA-S1xx実機で下記のように実行します。\
同一バス上の複数のMSP430をプログラム可能にするため、BSLに入るためのRESET/TESTピンを\
指定可能にしてあります。

    root@gemini:/tmp# ./msp430_writer -f firm.txt -b 1 -a 0x48
    MSP430 firmware updater
    * Load firmware from file: firm.txt ...done.
    * Invoke MSP430 BSL...done.
    * Wait for BSL booting...done.
    * Mass-erase device...done.
    * Unlock device succeeded.
    .......
    .
    * Verify segment No. 1 ...OK.
    * Verify segment No. 2 ...OK.

### Options

    root@gemini:/tmp# ./msp430_writer -h
    msp430_writer

    Usage:
    msp430_writer [options]

    Options:
    -c, --config=CONFIG        config file
    -f, --firmware=FIRMWARE    Firmware filename(TI-TXT format)
    -b, --busnum=BUSNUM        I2C bus number (default: 1)
    -a, --address=ADDRESS      MSP430 address (default: 0x48)
    -t, --pin_test=PIN_TEST    MSP430 control pin (TEST) (default: MSP430_TEST)
    -r, --pin_reset=PIN_RESET  MSP430 control pin (RESET) (default: MSP430_RST)
    -h, --help                 Show this help

### Config file format

    Firmware =
    BusNumber = 1
    Address = 0x48
    Pin_TEST = "MSP430_TEST"
    Pin_RESET = "MSP430_RESET"
