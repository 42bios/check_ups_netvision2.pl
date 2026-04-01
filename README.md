# check_ups_netvision2.pl

Nagios/Icinga plugin to monitor Socomec Netvision UPS systems via SNMP.

## Features

- SNMP-based UPS health checks
- Battery capacity, load, voltage and temperature checks
- Remaining runtime output
- Nagios-compatible status and perfdata output

## Requirements

- Perl 5.10+
- `Net::SNMP`
- `Getopt::Long`

## Usage

```bash
./check_ups_netvision2.pl -H <host> -C <community>
```

SNMPv3 example:

```bash
./check_ups_netvision2.pl -H <host> -v 3 -U <username> -A <authpass> -a sha -X <privpass> -x aes
```

## Output

Returns standard Nagios exit codes:

- `0` OK
- `1` WARNING
- `2` CRITICAL
- `3` UNKNOWN

## License

GNU General Public License v2.0 (see repository license selection).