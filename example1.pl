#!/usr/bin/perl
#
# Example script using Netatmo.pm
#

use strict;
use warnings;
use Netatmo;
use Data::Dumper;

my $c = NetatmoConnection->new(conffile => 'netatmo.conf');
die("Unable to establish connection: ".$c->{error}) if $c->{error};

my $w = $c->getWeatherStation(get_favorites => 'false');
die("Unable to fetch Weatherstation data: ".$w->{error}) if $w->{error};

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
die("Unable to fetch Netatmo Energy data: ".$e->{error}) if $e->{error};

foreach my $home ($e->homes) {
  foreach my $room ($home->rooms) {
    print "Room ID $room->{id} named $room->{name}\n";
    my $data = $room->getroommeasure(type => 'temperature,sp_temperature,boileron');
    if ($data->{error}) {
      print STDERR "Unable to fetch room measure: ".$data->{error}."\n";
      next;
    }
    #print Dumper $data;
    foreach my $t (@$data) {
      print localtime($t->[0]).": ".$t->[1]." ".$t->[2]."\n";
   }
  }
}
