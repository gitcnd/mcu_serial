# mcu_serial
A simple perl script to let you see your micro-controller serial port data, and optionally to reset it or put it into DFU firmware update mode.

This is tested and works using an ESP32CAM with the serial programming shield attached.  Note that this shield is problemantic with many other serial emulators, owing to how the RTS and DTR port pins are connected to the MCU (being, reset for RTS, and GPIO0 for DTR - both with the opposite signalling - writing 1 pulls the pins low)

## Usage:

    perl mcu_serial.pl -reset -port /dev/ttyS25
    perl mcu_serial.pl -dfu -exit
    perl mcu_serial.pl

-port	: serial port to use.  e.g. /dev/ttyS14

-reset	: reset the chip then attaches serial (requires suitable serial chip and wiring of RTS and DTR lines)

-dfu	: resets the chip (while holding down GPIO0) into DFU mode, then attaches serial

-exit	: skip attaching to the serial port after doing the -reset or -dfu

-lf	: send LF keypresses, instead of converting them to CR (probably never needed)
