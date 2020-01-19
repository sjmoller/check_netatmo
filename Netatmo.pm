# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

##########################################################################################
# Netatmo.pm
# API for access your Netatmo data at https://dev.netatmo.com
#
# Soren Juul Moller, Jan 2020.

package NetatmoUtils;
use strict;
use warnings;
use JSON;

sub load_json($) {
  my ($jsonfile) = @_;
  if (open(my $fd, '<', $jsonfile)) {
    local $/;
    my $hash = from_json(<$fd>);
    close($fd);
    return $hash;
  }
  return undef;
}

sub store_json($$) {
  my ($jsonfile, $hash) = @_;
  if (open(my $fd, '>', $jsonfile)) {
    print $fd to_json($hash, { utf8 => 1, pretty => 1});
    close($fd);
    return $hash;
  }
  return undef;
}

##########################################################################################
# Netatmo Connection
##########################################################################################

package NetatmoConnection;

use strict;
use warnings;
use YAML ();
use JSON;
use URI;
use LWP::UserAgent;
use Carp;

my $API = "https://api.netatmo.net";

#
# Establish session
# Login using values from configuration file or arguments
#
sub new {
  my ($class, %args) = @_;
  my $self = {};

  # Defaults
  $self->{cachedir} = '/var/run/netatmo';
  my $conffile = '/usr/local/etc/netatmo.conf';

  # Load config file if any
  $conffile = $args{conffile} if defined $args{conffile};
  if (-f $conffile) {
    my $conf = YAML::LoadFile($conffile);
    $self->{$_} = $conf->{$_} foreach keys %$conf;
  }

  # Override with args
  $self->{$_} = $args{$_} foreach keys %args;

  foreach (qw(client_id client_secret username password)) {
    croak("$_ is not defined") unless defined $self->{$_};
  }
 
  mkdir($self->{cachedir}) unless -d $self->{cachedir};

  # Create HTTP client
  $self->{'_ua'} = LWP::UserAgent->new(
	agent => "check_netatmo/0.5",
	ssl_opts => { verify_hostname => 0 }
  );
  $self->{_ua}->default_header('accept' => 'application/json');

  # Get a access token (possibly cached)
  my $access_token = get_token($self);
  if (defined $access_token) {
    $self->{access_token} = $access_token;
    $self->{_ua}->default_header('Authorization' => 'Bearer '.$access_token);
  } else {
    delete $self->{access_token};
  }

  bless $self, $class;
}

# Do a cached login.
# Returns access_token on success, undef on failire.
#
sub get_token {
  my ($self) = @_;
  my $content;

  # Load cache if it exists
  my $token = NetatmoUtils::load_json($self->{cachedir}.'/token.json');

  # If we got a refresh_token
  if (defined $token->{refresh_token}) {

    # Return token if not exipred
    return $token->{access_token} if ($token->{timestamp} + $token->{expires_in} - $self->{cachettl} > time());

    # else try refresh token
    my $res = $self->{_ua}->post(
          "$API/oauth2/token",
	  [
	    grant_type => 'refresh_token',
	    client_id => $self->{client_id},
	    client_secret => $self->{client_secret},
	    refresh_token => $token->{refresh_token}
	  ]
    );
    if ($res->is_success) {
      $content = $res->decoded_content if $res->is_success;
    } else {
      $self->{error} = $res->status_line;
    }
  }

  # else do a login
  if (!defined $content) {
    my $res = $self->{_ua}->post(
	"$API/oauth2/token",
	[
	  grant_type => 'password',
	  client_id => $self->{client_id},
	  client_secret => $self->{client_secret},
	  username => $self->{username},
	  password => $self->{password},
	  scope => 'read_station read_thermostat'
	]
    );
    if ($res->is_success) {
      $content = $res->decoded_content;
    } else {
      $self->{error} = $res->status_line;
    }
  }

  return undef unless defined $content;

  $token = from_json($content);
  $token->{timestamp} = time();
  NetatmoUtils::store_json($self->{cachedir}.'/token.json', $token);
  return $token->{access_token};
}

sub getWeatherStation {
  my ($self, %opts) = @_;
  return NetatmoWeatherStation->new(connection => $self, %opts);
}

sub getEnergy {
  my ($self) = @_;
  return NetatmoEnergy->new(connection => $self);
}

##########################################################################################
# Netatmo Weather
##########################################################################################

package NetatmoWSmodule;
use strict;
use warnings;
use Carp;

sub new {
  my ($class, %args) = @_;
  croak "module must be specified" unless defined $args{module};
  my $self = $args{module};
  bless $self, $class;
}

sub dashboard_data { shift->{dashboard_data} }

######################################

package NetatmoWSdevice;
use strict;
use warnings;
use Carp;

sub new {
  my ($class, %args) = @_;
  croak "device must be specified" unless defined $args{device};
  my $self = $args{device};
  bless $self, $class;
}

sub data_type      { @{shift->{data_type}} }
sub place          { shift->{place} }
sub dashboard_data { shift->{dashboard_data} }
sub user           { shift->{user} }
sub modules        { map { NetatmoWSmodule->new(module => $_) } @{shift->{modules}} };

sub moduleByName($) {
  my ($self, $name) = @_;
  foreach (@{$self->{modules}}) {
    return NetatmoWSmodule->new(module => $_) if $_->{module_name} eq $name;
  }
  return undef;
}

######################################

package NetatmoWeatherStation;
use strict;
use warnings;
use Carp;
use JSON;
use URI;

sub new {
  my ($class, %args) = @_;
  my $self = { map { $_ => $args{$_} } keys %args };

  croak "Must specify connection" unless defined $args{connection};

  my ($json, $cachefile);
  if (defined $self->{connection}->{cachedir}) {
    $cachefile = $self->{connection}->{cachedir}.'/weatherstation.json';
    my $cachettl = $self->{connection}->{cachettl};
    if (-s $cachefile) {
      my $mtime = (stat($cachefile))[9];
      if (time() - $mtime < $cachettl) {
        $json = NetatmoUtils::load_json($cachefile);
      }
    }
  }

  if (!defined $json) {
    $self->{_ua} = $self->{connection}->{_ua};
    my $url = URI->new("$API/api/getstationsdata");
    $url->query_form(get_favorites => $args{get_favorites}) if defined $args{get_favorites};
    my $res = $self->{_ua}->get($url);
    if ($res->is_success) {
      $json = from_json($res->decoded_content);
      NetatmoUtils::store_json($cachefile, $json) if defined $cachefile;
    } else {
      $self->{error} = $res->status_line;
    }
  }

  if (defined $json) {
    $self->{devices} = $json->{body}->{devices};
    $self->{user} = $json->{body}->{user};
    $self->{status} = $json->{status};
  }

  bless $self, $class;
}

sub devices {
  my ($self) = @_;
  return map { NetatmoWSdevice->new(device => $_) } @{$self->{devices}};
}

sub deviceByID($) {
  my ($self, $value) = @_;
  foreach (@{$self->{devices}}) {
    return NetatmoWSdevice->new(device => $_) if $_->{'_id'} eq $value;
  }
  return undef;
}

sub status { shift->{status} }


##########################################################################################
#  Netatmo Energy
##########################################################################################

package NetatmoEnergy;
use strict;
use warnings;
use Carp;
use JSON;
use URI;

sub new {
  my ($class, %args) = @_;
  my $self = { map { $_ => $args{$_} } keys %args };

  croak "connection must be specified" unless defined $args{connection};

  my ($cachefile, $json);
  if (defined $self->{connection}->{cachedir}) {
    $cachefile = $self->{connection}->{cachedir}.'/homesdata.json';
    my $cachettl = $self->{connection}->{cachettl};
    if (-s $cachefile) {
      my $mtime = (stat($cachefile))[9];
      if (time() - $mtime < $cachettl) {
        $json = NetatmoUtils::load_json($cachefile);
      }
    }
  }

  if (!defined $json) {
    my $url = URI->new("$API/api/homesdata");
    my $res = $self->{connection}->{_ua}->get($url);
    if ($res->is_success) {
      $json = from_json($res->decoded_content);
      NetatmoUtils::store_json($cachefile, $json) if defined $cachefile;
    } else {
      $self->{error} = $res->status_line;
    }
  }
  if (defined $json) {
    $self->{homes} = $json->{body}->{homes};
    $self->{user} = $json->{body}->{user};
    $self->{status} = $json->{status};
  }

  bless $self, $class;
}

sub homes {
  my ($self) = @_;
  map { NetatmoEnergyHome->new(home => $_, homes => $self) } @{$self->{homes}};
}

######################################

package NetatmoEnergyHome;
use strict;
use warnings;
use Carp;

sub new {
  my ($class, %args) = @_;
  croak "home must be specfied" unless defined $args{home};
  croak "homes must be specfied" unless defined $args{homes};
  my $self = $args{home};
  $self->{homes} = $args{homes};
  bless $self, $class;
}

sub rooms           { my $s=shift; map { NetatmoEnergyRoom->new(room => $_, home => $s) } @{$s->{rooms}} }
sub modules         { map { NetatmoEnergyModule->new(module => $_) } @{shift->{module}} }
sub therm_schedules { map { NetatmoEnergySchedule->new(schedule => $_) } @{shift->{therm_schedules}} }
sub schedules       { map { NetatmoEnergySchedule->new(schedule => $_) } @{shift->{schedules}} }

######################################

package NetatmoEnergyRoom;
use strict;
use warnings;
use Carp;
use URI;
use JSON;

sub new {
  my ($class, %args) = @_;
  croak "room must be specified" unless defined $args{room};
  croak "home must be specified" unless defined $args{home};
  my $self = $args{room};
  $self->{home} = $args{home};
  bless $self, $class;
}

sub getroommeasure {
  my ($self, %opts) = @_;
  my ($cachefile, $json);

  my $connection = $self->{home}->{homes}->{connection};
  if (defined $connection->{cachedir}) {
    $cachefile = $connection->{cachedir}.'/roommeasure-'.$self->{id}.'.json';
    my $cachettl = $connection->{cachettl};
    if (-s $cachefile) {
      my $mtime = (stat($cachefile))[9];
      if (time() - $mtime < $cachettl) {
        $json = NetatmoUtils::load_json($cachefile);
      }
    }
  }

  if (!defined $json) {
    my $ua = $connection->{_ua};
    $opts{scale} = '1hour' unless defined $opts{scale};
    $opts{type} = 'temperature,sp_temperature' unless defined $opts{type};
    $opts{limit} = 24 unless defined $opts{limit};
    my $url = URI->new("$API/api/getroommeasure");
    $url->query_form(home_id => $self->{home}->{id}, room_id => $self->{id}, %opts);
    my $res = $ua->get($url);
    if ($res->is_success) {
      $json = from_json($res->decoded_content);
      NetatmoUtils::store_json($cachefile, $json) if defined $cachefile;
    } else {
      $self->{error} = $res->status_line;
      return [];
    }
  }

  my @temps = ();
  foreach my $dataset (@{$json->{body}}) {
    my $t = $dataset->{beg_time};
    while (my $dstemps = shift(@{$dataset->{value}})) {
      push(@temps, [$t, @{$dstemps}]);
      $t += $dataset->{step_time};
    }
  }
  return \@temps;
}

######################################

package NetatmoEnergyModule;
use strict;
use warnings;
use Carp;

sub new {
  my ($class, %args) = @_;
  croak "module must be specified" unless defined $args{module};
  my $self = $args{module};
  bless $self, $class;
}

package NetatmoEnergySchedule;
use strict;
use warnings;
use Carp;

sub new {
  my ($class, %args) = @_;
  croak "schedule must be specified" unless defined $args{schedule};
  my $self = $args{schedule};
  bless $self, $class;
}

sub timetable { @{shift->{timetable}} }
sub zones     { @{shift->{zones}} }

1;
