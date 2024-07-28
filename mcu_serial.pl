#!/usr/bin/perl -w

our $VERSION = '0.20240623';	# format: major_revision.YYYYMMDD[hh24mi]

=head1 NAME

mcu_serial.pl

=head1 SYNOPSIS

 export PORT=/dev/ttyS14

 use this for esp32 programmers and esp32_cam and other chips that use RTS=>Reset and DTR=>GPIO0
	 perl mcu_serial.pl -port $PORT 

 use this for boards which actually use flow control:
	 perl mcu_serial.pl -port $PORT -setdtr -setrts -norts -nodtr

 
 -port		# serial port to use.  e.g. /dev/ttyS14
 -reset		# reset the chip then attaches serial (requires suitable serial chip and wiring of RTS and DTR lines)
 -dfu		# resets the chip (while holding down GPIO0) into DFU mode, then attaches serial
 -exit		# skip attaching to the serial port after doing the -reset or -dfu
 -lf		# send LF keypresses, instead of converting them to CR (probably never needed)
 -baud		# defaults to 115200

=head1 DESCRIPTION

A simple perl script to let you see your micro-controller serial port data, and optionally to reset it or put it into DFU firmware update mode.

This is tested and works using an ESP32CAM with the serial programming shield attached.  Note that this shield is problemantic with many other serial emulators, owing to how the RTS and DTR port pins are connected to the MCU (being, reset for RTS, and GPIO0 for DTR - both with the opposite signalling - writing 1 pulls the pins low)

=cut

######################################################################

use strict;
use warnings;
use Device::SerialPort;
use IO::Handle;
use Getopt::Long;
use Term::ReadKey;
use Fcntl;

# Open STDIN in non-blocking mode
fcntl(STDIN, F_SETFL, O_NONBLOCK) or die "Can't set non-blocking mode on STDIN: $!";

# Command-line options
my $reset = 0;
my $dfu = 0;
my $exit = 0;
my $port_name;
my $run=1;
my $LF=0;
my $baud_rate = 115200;
my $nodtr=0;
my $norts=0;

my $setdtr=0;
my $setrts=0;

my $clrdtr=0;
my $clrrts=0;

GetOptions( "reset" => \$reset,		# cycle a pulse on the RTS line
	    "dfu"   => \$dfu,		# hold down DTR (GPIO0) while cycling a pulse on the RTS line
	    "exit"   => \$exit,		# quite after setting above things up (don't run the terminal)
	    "lf"   => \$LF,		# send LF keypresses, instead of converting them to CR (probably never needed)
	    "port=s" => \$port_name,	# eg: /dev/ttyS14 or COM14
	    "baud=i" => \$baud_rate,	# defaults to 115200
	    "setdtr" => \$setdtr,	# do $port->dtr_active(1)
	    "setrts" => \$setrts,	# do $port->rts_active(1)
	    "clrdtr" => \$clrdtr,	# do $port->dtr_active(1)
	    "clrrts" => \$clrrts,	# do $port->rts_active(1)
	    "norts" => \$norts,		# don't use the RTS pin (except for -setrts)
	    "nodtr" => \$nodtr,		# don't use the DTR  pin (except for -setdtr)
	 ) or die "Error in command line arguments\n";

# Serial port configuration
$port_name = '/dev/ttyS25' unless($port_name);

# Create and open the serial port
my $port = Device::SerialPort->new($port_name) or die "Can't open $port_name: $!";

# Configure the serial port
$port->baudrate($baud_rate);
$port->parity('none');
$port->databits(8);
$port->stopbits(1);

# Set DTR (Data Terminal Ready) line high
$port->dtr_active(1) if($setdtr);	# This is GPIO0 (setting this "high" pulls ESP32 GPIO0 low) - skip this on Lolin S2 Mini otherwise it hangs.
$port->rts_active(1) if($setrts);	# this is reset (setting this "high" resets the ESP32)

$port->dtr_active(0) if($clrdtr);	# esp32c2 uses both flow control, and reset, on these lines
$port->rts_active(0) if($clrrts);	# 

$port->dtr_active(0) unless($nodtr || $setdtr);	# This is GPIO0 (setting this "high" pulls ESP32 GPIO0 low) - skip this on Lolin S2 Mini otherwise it hangs.
$port->rts_active(0) unless($norts || $setrts);	# this is reset (setting this "high" resets the ESP32)
# Note that performing a reset while holding GPIO0 low enters firmware programming mode)

# Set autoflush for STDOUT and STDIN
STDOUT->autoflush(1);
STDIN->autoflush(1);

$port->datatype('raw');	# stop line buffering

# Set STDIN to non-blocking mode
my $old_fh = select(STDIN);
$| = 1;
select($old_fh);

&firmware() if($dfu);
&reset() if($reset);
exit(0) if($exit);

ReadMode('raw'); # Set terminal to raw mode to read characters immediately
print "dtr=" . $port->dtr_active() . "\n";
print "rts=" . $port->rts_active() . "\n";
print "Use Control-] ( ^] ) to quit terminal emulator\n";
# Main loop
while ($run) {
  # Create a read set for select
    my $rin = '';
    vec($rin, fileno(STDIN), 1) = 1;
    vec($rin, $port->FILENO, 1) = 1;

    # Wait for data on serial port or STDIN
    select($rin, undef, undef, 0.1);

    # Check for data from the serial port
    if (vec($rin, $port->FILENO, 1)) {
        # my $data = $port->lookfor; # always line-buffered
        my ($count, $data) = $port->read(255);  # Read up to 255 bytes
        if ($count) {
            #print "Received: $data\n";
            print $data;
        }
    }

    # Check for data from STDIN (keyboard input)
    #  if (vec($rin, fileno(STDIN), 1)) 	# doesn't work on when pasting stuff fast - needed O_NONBLOCK to fix...
    my $key;
    do {
        undef($key);
        my $key = getc(STDIN);
        if( defined $key && ord($key) == 29 ){ # Exit on Ctrl+] 
          $run=0; last;
        }
        if (defined $key) {
            if(ord($key)==10 && !$LF) {	# Send CR if we got an LF (unless the -lf switch was used).
                $port->write(chr(13));
            } else {
                $port->write($key);
            }
        }
    } until(!defined $key);

} # run

END {
  ReadMode('restore'); # Restore terminal settings
  print "\n";
}

sub reset {
  print "\nresetting...\n";
  $port->rts_active(0) unless($norts);
  $port->dtr_active(0) unless($nodtr);
  select(undef, undef, undef, 0.2);
  $port->rts_active(1) unless($norts);
  select(undef, undef, undef, 0.2);
  $port->rts_active(0) unless($norts);
}
sub firmware {
  print "\nresetting into DFU...\n";
  $port->rts_active(0) unless($norts);
  $port->dtr_active(1) unless($nodtr);
  select(undef, undef, undef, 0.2);
  $port->rts_active(1) unless($norts);
  select(undef, undef, undef, 0.2);
  $port->rts_active(0) unless($norts);
  $port->dtr_active(0) unless($nodtr);
}

