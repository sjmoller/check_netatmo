check_netatmo
=============

Nagios / OP5 plugin for checking the health of your Netatmo Weatherstation.

I have no relation with the Netatmo company. I wrote this because I needed
something to notify me when my Netatmo needed service, like new batteries.

### Install ###

1. Create an App at https://dev.netatmo.com/
   Save the client_id and client_secret in netatmo.conf JSON file.
   Store netatmo.conf in /usr/local/etc.

2. Create run directory /var/run/netatmo.
   Give your monitor read/write access to here:

```
      chown monitor /var/run/netatmo
      chmod 755 /var/run/netatmo
```

   where "monitor" is the username your Nagios or OP5 is using.

3. Install check_netatmo in the monitor plugin directory.

4. Configure your monitor.

   Add "check_netatmo" as a new Command.

      command_name: check_netatmo

      command_line: $USER1$/check_netatmo $ARG1$

5. Define "Netatmo" host and services.

   - Add "Netatmo" as a host. Replace the host-alive check with

      check_netatmo -S

   - Add services:

     - Indoor timestamp:

        check_netatmo -t -m Indoor -s last_status_store

     - Outdoor RF status:

        check_netatmo -m Outdoor -s rf_status -w 120 -c 150

     - Outdoor battery voltage:

        check_netatmo -m Outdoor -s battery_vp

     - Outdoor timestamp:

        check_netatmo -t -m Outdoor -s last_seen

     - Rain Gauge RF status:

        check_netatmo -m "Rain Gauge" -s rf_status -w 120 -c 150

     - Rain Gauge battery voltage:

        check_netatmo -m "Rain Gauge" -s battery_vp

     - Rain Gauge timestamp:

        check_netatmo -t -m "Rain Gauge" -s last_seen

     - WIFI status:

        check_netatmo -m Indoor -s wifi_status

     - Wind Gauge RF status:

        check_netatmo -m "Wind Gauge" -s rf_status -w 120 -c 150

     - Wind Gauge battery voltage:

        check_netatmo -m "Wind Gauge" -s battery_vp

     - Wind Gauge timestamp:

        check_netatmo -t -m "Wind Gauge" -s last_seen

   If you prefer, you can also check battery using percent:

      check_netatmo -m "Rain Gauge" -s battery_percent -w 12 -c 6
