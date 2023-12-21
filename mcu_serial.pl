#!/usr/bin/perl -w

our $VERSION = '0.20231221';	# format: major_revision.YYYYMMDD[hh24mi]

=head1 NAME

mcu_serial.pl

=head1 SYNOPSIS

 export PORT=/dev/ttyS14
 perl mcu_serial.pl -port $PORT 
 
 -port		# serial port to use.  e.g. /dev/ttyS14
 -reset		# reset the chip then attaches serial (requires suitable serial chip and wiring of RTS and DTR lines)
 -dfu		# resets the chip (while holding down GPIO0) into DFU mode, then attaches serial
 -exit		# skip attaching to the serial port after doing the -reset or -dfu
 -cr		# send extra CR when we get LF keypress (probably never needed)

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
my $CR=0;

GetOptions( "reset" => \$reset, "dfu"   => \$dfu, "exit"   => \$exit, "cr"   => \$CR, "port=s" => \$port_name ) or die "Error in command line arguments\n";

# Serial port configuration
$port_name = '/dev/ttyS25' unless($port_name);
my $baud_rate = 115200;

# Create and open the serial port
my $port = Device::SerialPort->new($port_name) or die "Can't open $port_name: $!";

# Configure the serial port
$port->baudrate($baud_rate);
$port->parity('none');
$port->databits(8);
$port->stopbits(1);

# Set DTR (Data Terminal Ready) line high
$port->dtr_active(0);	# This is GPIO0 (setting this "high" pulls ESP32 GPIO0 low)
$port->rts_active(0);	# this is reset (setting this "high" resets the ESP32)
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
print "Use Control-] ( ^] ) to quit terminal emulator\n";
# Main loop
while ($run) {
    # Create a read set for select
    my $rin = '';
    vec($rin, fileno(STDIN), 1) = 1;
    vec($rin, $port->FILENO, 1) = 1;

    # Wait for data on serial port or STDIN
    select($rin, undef, undef, 1.1);

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
            $port->write($key);
            $port->write(chr(13)) if(ord($key)==10 && $CR);	# Send CR if we got an LF (if the -CR switch was used).
        }
    } until(!defined $key);

} # run

END {
  ReadMode('restore'); # Restore terminal settings
  print "\n";
}

sub reset {
  print "\nresetting...\n";
  $port->rts_active(0); $port->dtr_active(0);
  select(undef, undef, undef, 0.2);
  $port->rts_active(1);
  select(undef, undef, undef, 0.2);
  $port->rts_active(0);
}
sub firmware {
  print "\nresetting into DFU...\n";
  $port->rts_active(0); $port->dtr_active(1);
  select(undef, undef, undef, 0.2);
  $port->rts_active(1);
  select(undef, undef, undef, 0.2);
  $port->rts_active(0); $port->dtr_active(0);
}

