#!/usr/bin/env perl
# nagios: -epn
# icinga: -epn
#
# check_ups_netvision2.pl
# Socomec Netvision UPS monitor for Nagios/Icinga via SNMP.
#
# License: GNU GPL v2.0

use strict;
use warnings;
use feature ':5.10';

use Getopt::Long qw(:config no_ignore_case bundling);
use Net::SNMP;

my $script_version = '2.0.0';

# Defaults
my $host = '';
my $version = 2;
my $community = 'public';

my $username = '';
my $auth_password = '';
my $auth_protocol = 'sha';
my $priv_password = '';
my $priv_protocol = 'aes';

my $warn_load = 85;
my $crit_load = 95;
my $warn_temp = 30;
my $crit_temp = 37;
my $warn_remaining = 15;
my $crit_remaining = 10;
my $warn_capacity = 50;
my $crit_capacity = 30;

my $help = 0;

GetOptions(
    'host|H=s'         => \$host,
    'version|v=i'      => \$version,
    'community|C=s'    => \$community,
    'username|U=s'     => \$username,
    'authpassword|A=s' => \$auth_password,
    'authprotocol|a=s' => \$auth_protocol,
    'privpassword|X=s' => \$priv_password,
    'privprotocol|x=s' => \$priv_protocol,

    'warn-load=i'      => \$warn_load,
    'crit-load=i'      => \$crit_load,
    'warn-temp=i'      => \$warn_temp,
    'crit-temp=i'      => \$crit_temp,
    'warn-remaining=i' => \$warn_remaining,
    'crit-remaining=i' => \$crit_remaining,
    'warn-capacity=i'  => \$warn_capacity,
    'crit-capacity=i'  => \$crit_capacity,

    'help|h|?'         => \$help,
) or usage(3, 'UNKNOWN - Invalid arguments');

usage(0) if $help;
usage(3, 'UNKNOWN - Missing required -H/--host') if !$host;

# Socomec Netvision OIDs
my %oids = (
    battery_status   => '1.3.6.1.4.1.4555.1.1.1.1.2.1.0',
    battery_temp     => '1.3.6.1.4.1.4555.1.1.1.1.2.6.0',
    battery_capacity => '1.3.6.1.4.1.4555.1.1.1.1.2.4.0',
    remaining_min    => '1.3.6.1.4.1.4555.1.1.1.1.2.3.0',
    on_battery_sec   => '1.3.6.1.4.1.4555.1.1.1.1.2.2.0',
    output_source    => '1.3.6.1.4.1.4555.1.1.1.1.4.1.0',
    output_load      => '1.3.6.1.4.1.4555.1.1.1.1.4.4.1.4.1',
    output_kva       => '1.3.6.1.4.1.4555.1.1.1.1.4.4.1.5.1',
    input_voltage    => '1.3.6.1.4.1.4555.1.1.1.1.3.3.1.2.1',
    output_voltage   => '1.3.6.1.4.1.4555.1.1.1.1.4.4.1.2.1',
    alarms_present   => '1.3.6.1.4.1.4555.1.1.1.1.6.1.0',
);

my ($session, $error) = create_snmp_session();
if (!$session) {
    print "CRITICAL - SNMP session error: $error\n";
    exit 2;
}

my $result = $session->get_request(-varbindlist => [ values %oids ]);
if (!defined $result) {
    my $err = $session->error();
    $session->close();
    print "CRITICAL - SNMP query failed: $err\n";
    exit 2;
}

$session->close();

my $status = 0;
my @parts;
my @perf;

my %source_map = (
    1 => 'unknown',
    2 => 'onInverter',
    3 => 'onMains',
    4 => 'ecoMode',
    5 => 'onBypass',
    6 => 'standby',
    7 => 'onMaintenanceBypass',
    8 => 'upsOff',
    9 => 'normalMode',
);

my $source = to_num($result->{$oids{output_source}});
if (defined $source) {
    my $label = $source_map{$source} // 'unknown';
    push @parts, "SOURCE: $label";
    if ($source == 5 || $source == 7 || $source == 8) {
        $status = max_state($status, 1);
    }
}

my $load = to_num($result->{$oids{output_load}});
if (defined $load) {
    if ($load > $crit_load) {
        $status = max_state($status, 2);
        push @parts, "CRIT LOAD: ${load}%";
    } elsif ($load > $warn_load) {
        $status = max_state($status, 1);
        push @parts, "WARN LOAD: ${load}%";
    } else {
        push @parts, "LOAD: ${load}%";
    }
    push @perf, "'load'=${load}%;${warn_load};${crit_load};;";
}

my $temp = to_num($result->{$oids{battery_temp}});
if (defined $temp) {
    if ($temp > $crit_temp) {
        $status = max_state($status, 2);
        push @parts, "CRIT BATT TEMP: ${temp}C";
    } elsif ($temp > $warn_temp) {
        $status = max_state($status, 1);
        push @parts, "WARN BATT TEMP: ${temp}C";
    } else {
        push @parts, "BATT TEMP: ${temp}C";
    }
    push @perf, "'temp'=${temp};${warn_temp};${crit_temp};;";
}

my $capacity = to_num($result->{$oids{battery_capacity}});
if (defined $capacity) {
    if ($capacity < $crit_capacity) {
        $status = max_state($status, 2);
        push @parts, "CRIT CAPACITY: ${capacity}%";
    } elsif ($capacity < $warn_capacity) {
        $status = max_state($status, 1);
        push @parts, "WARN CAPACITY: ${capacity}%";
    } else {
        push @parts, "CAPACITY: ${capacity}%";
    }
    push @perf, "'capacity'=${capacity}%;${warn_capacity};${crit_capacity};;";
}

my $remaining = to_num($result->{$oids{remaining_min}});
if (defined $remaining) {
    if ($remaining <= $crit_remaining) {
        $status = max_state($status, 2);
        push @parts, "CRIT REMAINING: ${remaining}min";
    } elsif ($remaining <= $warn_remaining) {
        $status = max_state($status, 1);
        push @parts, "WARN REMAINING: ${remaining}min";
    } else {
        push @parts, "REMAINING: ${remaining}min";
    }
    push @perf, "'remaining_min'=${remaining};${warn_remaining};${crit_remaining};0;";
}

my $on_battery = to_num($result->{$oids{on_battery_sec}});
if (defined $on_battery) {
    push @parts, "ON_BATTERY: ${on_battery}s";
    push @perf, "'on_battery_sec'=${on_battery};;;;";
}

my $kva = to_num($result->{$oids{output_kva}});
push @perf, "'kva'=${kva};;;;" if defined $kva;

my $vin = to_num($result->{$oids{input_voltage}});
push @perf, "'vin'=${vin};;;;" if defined $vin;

my $vout = to_num($result->{$oids{output_voltage}});
push @perf, "'vout'=${vout};;;;" if defined $vout;

my $alarms = to_num($result->{$oids{alarms_present}});
if (defined $alarms) {
    if ($alarms > 0) {
        $status = max_state($status, 2);
        push @parts, "ALARMS: $alarms";
    } else {
        push @parts, 'ALARMS: 0';
    }
    push @perf, "'alarms'=${alarms};;;;";
}

my %state_text = (0 => 'OK', 1 => 'WARNING', 2 => 'CRITICAL', 3 => 'UNKNOWN');
my $line = join(' - ', @parts);
my $perf = join(' ', @perf);

print $state_text{$status} . " - $line";
print "|$perf" if $perf ne '';
print "\n";
exit $status;

sub create_snmp_session {
    if ($version == 3) {
        return Net::SNMP->session(
            -hostname     => $host,
            -port         => 161,
            -version      => 3,
            -username     => $username,
            -authpassword => $auth_password,
            -authprotocol => lc($auth_protocol),
            -privpassword => $priv_password,
            -privprotocol => lc($priv_protocol),
            -timeout      => 5,
            -retries      => 2,
        );
    }

    return Net::SNMP->session(
        -hostname  => $host,
        -community => $community,
        -port      => 161,
        -version   => $version,
        -timeout   => 5,
        -retries   => 2,
    );
}

sub to_num {
    my ($v) = @_;
    return undef if !defined $v;
    if ($v =~ /(-?\d+(?:\.\d+)?)/) {
        return 0 + $1;
    }
    return undef;
}

sub max_state {
    my ($a, $b) = @_;
    return $a > $b ? $a : $b;
}

sub usage {
    my ($exit_code, $msg) = @_;
    print "$msg\n" if defined $msg;
    print <<'USAGE';
check_ups_netvision2.pl v2.0.0

Usage:
  check_ups_netvision2.pl -H <host> [-C <community>] [-v <1|2|3>] [options]

SNMP v1/v2c:
  -H, --host           Hostname or IP
  -C, --community      Community (default: public)
  -v, --version        1 or 2 (default: 2)

SNMP v3:
  -v, --version        3
  -U, --username       Username
  -A, --authpassword   Auth password
  -a, --authprotocol   sha|md5 (default: sha)
  -X, --privpassword   Privacy password
  -x, --privprotocol   aes|des (default: aes)

Threshold options:
  --warn-load / --crit-load
  --warn-temp / --crit-temp
  --warn-remaining / --crit-remaining
  --warn-capacity / --crit-capacity

  -h, --help           Show this help
USAGE
    exit $exit_code;
}
