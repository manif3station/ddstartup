use strict;
use warnings;

use File::Path qw(make_path);
use File::Temp qw(tempdir);
use JSON::PP qw(decode_json);
use Test::More;

my $tmp = tempdir( CLEANUP => 1 );
my $bin = "$tmp/bin";
my $home = "$tmp/home";
my $user_units = "$tmp/user-units";
my $system_units = "$tmp/system-units";
my $logs_file = "$tmp/calls.log";

make_path( $bin, $home, $user_units, $system_units );

_write_executable(
    "$bin/dashboard",
    "#!/usr/bin/env bash\nexit 0\n",
);
_write_executable(
    "$bin/systemctl",
    "#!/usr/bin/env bash\nprintf '%s\\n' \"\$*\" >>\"\$DDSTARTUP_CALLS_LOG\"\nif [ \"\$2\" = \"is-enabled\" ] || [ \"\$1\" = \"is-enabled\" ]; then printf 'enabled\\n'; exit 0; fi\nif [ \"\$2\" = \"is-active\" ] || [ \"\$1\" = \"is-active\" ]; then printf 'active\\n'; exit 0; fi\nexit 0\n",
);
_write_executable(
    "$bin/journalctl",
    "#!/usr/bin/env bash\nprintf '%s\\n' \"\$*\" >>\"\$DDSTARTUP_CALLS_LOG\"\nprintf 'journal line\\n'\n",
);

local $ENV{PATH} = "$bin:$ENV{PATH}";
local $ENV{HOME} = $home;
local $ENV{DDSTARTUP_USER_UNIT_DIR} = $user_units;
local $ENV{DDSTARTUP_SYSTEM_UNIT_DIR} = $system_units;
local $ENV{DDSTARTUP_CALLS_LOG} = $logs_file;
local $ENV{DDSTARTUP_EUID} = 1000;

my $setup = qx{$^X cli/setup};
is( $? >> 8, 0, 'cli/setup exits cleanly' );
like( $setup, qr/\bFIELD\b/, 'cli/setup defaults to table output' );
like( $setup, qr/\bscope\b\s+user\b/, 'cli/setup table reports user scope' );

my $setup_json = qx{$^X cli/setup -o json};
is( $? >> 8, 0, 'cli/setup -o json exits cleanly' );
my $setup_payload = decode_json($setup_json);
is( $setup_payload->{scope}, 'user', 'cli/setup json reports user scope' );

my $disable = qx{$^X cli/disable};
is( $? >> 8, 0, 'cli/disable exits cleanly' );
like( $disable, qr/\bdisabled\b\s+1\b/, 'cli/disable defaults to table output' );

my $enable = qx{$^X cli/enable};
is( $? >> 8, 0, 'cli/enable exits cleanly' );
like( $enable, qr/\bscope\b\s+user\b/, 'cli/enable table reports user scope' );

my $status = qx{$^X cli/status};
is( $? >> 8, 0, 'cli/status exits cleanly' );
like( $status, qr/\benabled\b\s+enabled\b/, 'cli/status defaults to table output' );
my $status_json = qx{$^X cli/status -o json};
is( $? >> 8, 0, 'cli/status -o json exits cleanly' );
my $status_payload = decode_json($status_json);
is( $status_payload->{active}, 'active', 'cli/status reports active state' );
is( $status_payload->{enabled}, 'enabled', 'cli/status reports enabled state' );

my $logs = qx{$^X cli/logs --lines 12};
is( $? >> 8, 0, 'cli/logs exits cleanly' );
like( $logs, qr/\bFIELD\b/, 'cli/logs defaults to table output' );
like( $logs, qr/\blines\b\s+12\b/, 'cli/logs table reports the requested line count' );
like( $logs, qr/\blogs\b\s+journal line\b/, 'cli/logs table carries the log payload' );

my $logs_json = qx{$^X cli/logs -o json --lines 12};
is( $? >> 8, 0, 'cli/logs -o json exits cleanly' );
is( decode_json($logs_json)->{logs}, "journal line\n", 'cli/logs json returns machine-readable logs' );

my $remove = qx{$^X cli/remove};
is( $? >> 8, 0, 'cli/remove exits cleanly' );
like( $remove, qr/\bremoved\b\s+1\b/, 'cli/remove defaults to table output' );
my $remove_json = qx{$^X cli/remove -o json};
is( $? >> 8, 0, 'cli/remove -o json exits cleanly' );
my $remove_payload = decode_json($remove_json);
ok( $remove_payload->{removed}, 'cli/remove reports success' );

open my $lfh, '<', $logs_file or die "Unable to read $logs_file: $!";
local $/;
my $calls = <$lfh>;
close $lfh or die "Unable to close $logs_file: $!";
like( $calls, qr/--user daemon-reload/, 'cli/setup used user-scope systemctl reload' );
like( $calls, qr/--user -u developer-dashboard-startup\.service --no-pager -n 12/, 'cli/logs used the requested line count' );
like( $calls, qr/--user disable --now developer-dashboard-startup\.service/, 'cli/disable disabled the user unit' );
like( $calls, qr/--user enable --now developer-dashboard-startup\.service/, 'cli/enable enabled the user unit' );

my $mac_tmp = tempdir( CLEANUP => 1 );
my $mac_bin = "$mac_tmp/bin";
my $mac_home = "$mac_tmp/home";
my $mac_agents = "$mac_tmp/LaunchAgents";
my $mac_daemons = "$mac_tmp/LaunchDaemons";
my $mac_logs_dir = "$mac_tmp/Logs";
my $mac_calls_log = "$mac_tmp/launchctl.log";
my $mac_state_dir = "$mac_tmp/state";

make_path( $mac_bin, $mac_home, $mac_agents, $mac_daemons, $mac_logs_dir, $mac_state_dir );

_write_executable(
    "$mac_bin/dashboard",
    "#!/usr/bin/env bash\nexit 0\n",
);
_write_executable(
    "$mac_bin/launchctl",
    <<"EOF",
#!/usr/bin/env bash
printf '%s\\n' "\$*" >>"$mac_calls_log"
loaded="$mac_state_dir/loaded"
disabled="$mac_state_dir/disabled"
case "\$1" in
  enable)
    rm -f "\$disabled"
    exit 0
    ;;
  disable)
    : >"\$disabled"
    rm -f "\$loaded"
    exit 0
    ;;
  load)
    : >"\$loaded"
    exit 0
    ;;
  unload)
    rm -f "\$loaded"
    exit 0
    ;;
  list)
    if [ -f "\$loaded" ]; then
      printf '{ "Label" = "developer-dashboard-startup" }\\n'
    else
      printf 'Could not find service "developer-dashboard-startup" in domain for uid: 501\\n'
    fi
    exit 0
    ;;
  print-disabled)
    if [ -f "\$disabled" ]; then
      printf '\\tdisabled services = {\\n\\t\\t"developer-dashboard-startup" => disabled\\n\\t}\\n'
    else
      printf '\\tdisabled services = {\\n\\t}\\n'
    fi
    exit 0
    ;;
esac
exit 0
EOF
);

_write_file( "$mac_logs_dir/developer-dashboard-startup.log", "mac alpha\nmac beta\n" );
_write_file( "$mac_logs_dir/developer-dashboard-startup.err.log", "mac gamma\n" );

local $ENV{PATH} = "$mac_bin:$ENV{PATH}";
local $ENV{HOME} = $mac_home;
local $ENV{DDSTARTUP_OSNAME} = 'darwin';
local $ENV{DDSTARTUP_USER_LAUNCH_AGENTS_DIR} = $mac_agents;
local $ENV{DDSTARTUP_SYSTEM_LAUNCH_DAEMONS_DIR} = $mac_daemons;
local $ENV{DDSTARTUP_USER_LOGS_DIR} = $mac_logs_dir;
local $ENV{DDSTARTUP_SYSTEM_LOGS_DIR} = "$mac_tmp/SystemLogs";
local $ENV{DDSTARTUP_EUID} = 501;

my $mac_setup_cli = qx{$^X cli/setup};
is( $? >> 8, 0, 'mac cli/setup exits cleanly' );
like( $mac_setup_cli, qr/\bplatform\b\s+macos\b/, 'mac cli/setup table reports the platform' );
like( $mac_setup_cli, qr/\bdomain\b\s+user\/501\b/, 'mac cli/setup table reports the launchctl domain' );

my $mac_status_cli = qx{$^X cli/status -o json};
is( $? >> 8, 0, 'mac cli/status -o json exits cleanly' );
my $mac_status_payload = decode_json($mac_status_cli);
is( $mac_status_payload->{enabled}, 'enabled', 'mac cli/status reports enabled state' );
is( $mac_status_payload->{active}, 'active', 'mac cli/status reports active state' );

my $mac_logs_cli = qx{$^X cli/logs --lines 2};
is( $? >> 8, 0, 'mac cli/logs exits cleanly' );
like( $mac_logs_cli, qr/\blogs\b\s+mac beta\b/, 'mac cli/logs includes the requested trailing log lines' );

my $mac_disable_cli = qx{$^X cli/disable};
is( $? >> 8, 0, 'mac cli/disable exits cleanly' );
like( $mac_disable_cli, qr/\bdisabled\b\s+1\b/, 'mac cli/disable reports disabled state' );

my $mac_enable_cli = qx{$^X cli/enable};
is( $? >> 8, 0, 'mac cli/enable exits cleanly' );
like( $mac_enable_cli, qr/\bplatform\b\s+macos\b/, 'mac cli/enable table reports the platform' );

my $mac_remove_cli = qx{$^X cli/remove -o json};
is( $? >> 8, 0, 'mac cli/remove -o json exits cleanly' );
ok( decode_json($mac_remove_cli)->{removed}, 'mac cli/remove reports success' );

open my $mfh, '<', $mac_calls_log or die "Unable to read $mac_calls_log: $!";
my $mac_calls = do { local $/; <$mfh> };
close $mfh or die "Unable to close $mac_calls_log: $!";
like( $mac_calls, qr/\Qenable user\/501\/developer-dashboard-startup\E/, 'mac cli/setup enabled the launchd label' );
like( $mac_calls, qr/\Qload -w \E/, 'mac cli/setup loaded the launch agent plist' );
like( $mac_calls, qr/\Qlist developer-dashboard-startup\E/, 'mac cli/status queried the launchd label state' );
like( $mac_calls, qr/\Qprint-disabled user\/501\E/, 'mac cli/status queried the user disabled map' );
like( $mac_calls, qr/\Qdisable user\/501\/developer-dashboard-startup\E/, 'mac cli/disable disabled the launchd label' );
like( $mac_calls, qr/\Qunload -w \E/, 'mac cli/disable or remove unloaded the launchd job' );

done_testing();

sub _write_executable {
    my ( $path, $content ) = @_;
    open my $fh, '>', $path or die "Unable to write $path: $!";
    print {$fh} $content;
    close $fh or die "Unable to close $path: $!";
    chmod 0755, $path or die "Unable to chmod $path: $!";
    return 1;
}

sub _write_file {
    my ( $path, $content ) = @_;
    open my $fh, '>', $path or die "Unable to write $path: $!";
    print {$fh} $content;
    close $fh or die "Unable to close $path: $!";
    return 1;
}
