check_netatmo
=============

Nagios / OP5 plugin for checking values from your Netatmo Weatherstation.

I have no relation with the Netatmo company. I wrote this because I needed
something to notify me when my Netatmo needed service, like new batteries.

### Install ###

1. Create an App at https://dev.netatmo.com/

   Save the client_id and client_secret in netatmo.conf JSON file.<br />
   Store netatmo.conf in /usr/local/etc.

2. Create run directory /var/run/netatmo (as root).

```
   # mkdir -m 755 /var/run/netatmo
   # chown monitor /var/run/netatmo
```

   where "monitor" is the username your Nagios or OP5 is using.

3. Install check_netatmo in the monitor plugin directory.

### Configure Monitor ###

1. Configure your monitor.

  Add "check_netatmo" as a new Command.

    command_name: check_netatmo
    command_line: $USER1$/check_netatmo $ARG1$

2. Define "Netatmo" host and services.

   - Add "Netatmo" as a host. Replace the host-alive check with

    check_netatmo -a '{body}->{status}' -e ok

3. Define Netatmo service checks

  Assuming one device and one Outdoor module (module 0), one rain gauge (module 1) and one wind gauge (module 2).<br />
  See also https://dev.netatmo.com/resources/technical/reference/weather/getstationsdata for thresholds.<br />
  Also https://nagios-plugins.org/doc/guidelines.html#THRESHOLDFORMAT for Nagios threshold parameter format.

  - Indoor timestamp:

    check_netatmo -a '{body}->{devices}[0]->{last_status_store}' -T -w3600 -c7200 -p '3600:7200' -m 'Indoor last seen %t ago'

  - Outdoor RF status:

    check_netatmo -a '{body}->{devices}[0]->{modules}[0]->{rf_status}' -w120 -c150 -p '120:150:40:200'

  - Outdoor battery voltage:

    check_netatmo -a '{body}->{devices}[0]->{modules}[0]->{battery_vp}' -w4500: -c4000: -p '4500:4000:3500:6500'

  - Outdoor timestamp:

    check_netatmo -a '{body}->{devices}[0]->{modules}[0]->{last_seen}' -T -w3600 -c7200 -p '3600:7200' -m 'Outdoor last seen %t ago'

  - ... the same from rain and wind gauge, just with module index 1 and 2.

  - WIFI status:

    check_netatmo -a '{body}->{devices}[0]->{wifi_status}' -w75 -c86 -p '75:86:40:100'

If you prefer, you can also check battery using percent:

    check_netatmo -a '{body}->{devices}[0]->{modules}[0]->{battery_percent}' -w12: -c6: -p '12:6:0:100'

Exotic checks can also be done:<br />
Give a warning if wind angle is between 220 and 280, and a critical if wind angle is between 281 and 330

    check_netatmo -a '{body}->{devices}[0]->{modules}[2]->{dashboard_data}->{WindAngle}' -w@220:280 -c@281:330 -m 'Wind angle is %v degrees'

See /var/run/netatmo/data.json for possible values to check.

### Usage ###

```
Usage: check_netatmo -a attr [-w INT:INT -c INT:INT -T -e equal-str -n not-equal-str -p perfdata -m message-template]

 -?, --usage
   Print usage information
 -h, --help
   Print detailed help screen
 -V, --version
   Print version information
 --extra-opts=[section][@file]
   Read options from an ini file. See http://nagiosplugins.org/extra-opts
   for usage and examples.
 -a, --attribute {attr}->{attr}
 -w, --warning INT:INT
 -c, --critical INT:INT
 -T, --timestamp
   value is an epoch. Compare to epoch now (diff in seconds)
 -e, --equals str
   critical if not equal
 -n, --notequals str
   critical if equal
 -p, --perfdata [thresholds]
   Nagios performance data format: name=value[:warnlevel[:critlevel[:min[:max]]]]   Format defaults to "label=value"
   threshols:  warn[;crit[;min[;max]]] - example: -p '25:50:25:50'
 -m, --message message-template
   Format: 'Value %a is %v' or 'device seen %t ago'
   where %a is attribute name, %v is value and %t is duration
 -t, --timeout=INTEGER
   Seconds before plugin times out (default: 15)
 -v, --verbose
   Show details for command-line debugging (can repeat up to 3 times)
```
