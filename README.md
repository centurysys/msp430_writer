# MSP430 firmware writer

## how to build

[Nim](http://nim-lang.org/) と ARM用クロスコンパイラが必要です。\
ビルドは nimble を用いた通常の方法でビルドします。\
標準で ARM 用バイナリを出力する設定にしてあります。

    $ nimble build -d:release

## usage

MSP430用ファームウェアをTI-TXT形式で出力し、MA-S1xx実機で下記のように実行します。

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

### options

    root@gemini:/tmp# ./msp430_writer -h
    msp430_writer

    Usage:
    msp430_writer [options] 

    Options:
    -f, --firmware=FIRMWARE    Firmware filename(TI-TXT format)
    -b, --busnum=BUSNUM        I2C bus number (default: 1)
    -a, --address=ADDRESS      MSP430 address (default: 0x48)
    -h, --help                 Show this help
