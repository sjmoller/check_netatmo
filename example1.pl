#!/usr/bin/perl
#
# Example script using Netatmo.pm
#

use strict;
use warnings;
use Netatmo;
use Data::Dumper;

my $c = NetatmoConnection->new(conffile => 'netatmo.conf');
die("Unable to establish connection") unless $c;

my $w = $c->getWeatherStation(get_favorites => 'false');
foreach my $d ($w->devices) {
  print "Dashboard Temperature: ".$d->dashboard_data->{Temperature}."\n";
  print "Modules:\n";
  foreach my $m ($d->modules) {
    print "- ".$m->{module_name}."\n";
    my $mdb = $m->dashboard_data;
    print "-- $_: ".$mdb->{$_}."\n" foreach keys %$mdb;
  }
}

my $e = $c->getEnergy;

foreach my $home ($e->homes) {
  foreach my $room ($home->rooms) {
    print "Room ID $room->{id} named $room->{name}\n";
    my $data = $room->getroommeasure(type => 'temperature,sp_temperature,boileron');
    #print Dumper $data;
    foreach my $t (@$data) {
      print localtime($t->[0]).": ".$t->[1]." ".$t->[2]."\n";
   }
  }
}
