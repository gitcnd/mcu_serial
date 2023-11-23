#!/usr/bin/perl
use strict;
use warnings;
use Device::SerialPort;
use IO::Handle;
use Getopt::Long;

# Command-line options
my $reset = 0;
my $dfu = 0;
my $exit = 0;
my $port_name;

GetOptions( "reset" => \$reset, "dfu"   => \$dfu, "exit"   => \$exit, "port=s" => \$port_name ) or die "Error in command line arguments\n";

# Serial port configuration
$port_name = '/dev/ttyS21' unless($port_name);
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

# Set STDIN to non-blocking mode
my $old_fh = select(STDIN);
$| = 1;
select($old_fh);

&firmware() if($dfu);
&reset() if($reset);
&exit(0) if($exit);

# Main loop
while (1) {
    # Create a read set for select
    my $rin = '';
    vec($rin, fileno(STDIN), 1) = 1;
    vec($rin, $port->FILENO, 1) = 1;

    # Wait for data on serial port or STDIN
    select($rin, undef, undef, undef);

    # Check for data from the serial port
    if (vec($rin, $port->FILENO, 1)) {
        my $data = $port->lookfor;
        if ($data) {
            print "Received: $data\n";
        }
    }

    # Check for data from STDIN (keyboard input)
    if (vec($rin, fileno(STDIN), 1)) {
        my $key = getc(STDIN);
        if (defined $key) {
            $port->write($key);
        }
    }
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

