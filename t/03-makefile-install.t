use strict;
use warnings;

use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test::More;

my $tmp = tempdir( CLEANUP => 1 );
my $bin = "$tmp/bin";
my $home = "$tmp/home";
my $user_units = "$tmp/user-units";
my $calls_log = "$tmp/calls.log";

make_path( $bin, $home, $user_units );

_write_executable(
    "$bin/systemctl",
    "#!/bin/sh\nprintf '%s\\n' \"\$*\" >>\"\$DDSTARTUP_CALLS_LOG\"\nexit 0\n",
);
_write_executable(
    "$bin/journalctl",
    "#!/bin/sh\nexit 0\n",
);
_write_executable(
    "$bin/dashboard",
    "#!/bin/sh\nexit 0\n",
);

my $install = qx{PATH="$bin:$ENV{PATH}" HOME="$home" DDSTARTUP_USER_UNIT_DIR="$user_units" DDSTARTUP_CALLS_LOG="$calls_log" DDSTARTUP_EUID=1000 make install};
is( $? >> 8, 0, 'make install exits cleanly' );
ok( -f "$user_units/developer-dashboard-startup.service", 'make install auto-provisions the startup unit' );
open my $ufh, '<', "$user_units/developer-dashboard-startup.service" or die "Unable to read unit file: $!";
local $/;
my $unit = <$ufh>;
close $ufh or die "Unable to close unit file: $!";
like( $unit, qr/\QWorkingDirectory=$home\E/, 'install-time auto-setup writes the user home as the working directory' );

my $disable = qx{PATH="$bin:$ENV{PATH}" HOME="$home" DDSTARTUP_USER_UNIT_DIR="$user_units" DDSTARTUP_CALLS_LOG="$calls_log" DDSTARTUP_EUID=1000 $^X cli/disable};
is( $? >> 8, 0, 'cli/disable exits cleanly after make install' );

my $install_again = qx{PATH="$bin:$ENV{PATH}" HOME="$home" DDSTARTUP_USER_UNIT_DIR="$user_units" DDSTARTUP_CALLS_LOG="$calls_log" DDSTARTUP_EUID=1000 make install};
is( $? >> 8, 0, 'make install remains clean when the unit file already exists' );

open my $fh, '<', $calls_log or die "Unable to read $calls_log: $!";
local $/;
my $calls = <$fh>;
close $fh or die "Unable to close $calls_log: $!";
my $enable_count = () = $calls =~ /enable --now developer-dashboard-startup\.service/g;
is( $enable_count, 1, 'auto-setup enables only on first install and does not override later state automatically' );
like( $calls, qr/disable --now developer-dashboard-startup\.service/, 'disable was called after install' );

my $unsupported_tmp = tempdir( CLEANUP => 1 );
my $unsupported_bin = "$unsupported_tmp/bin";
my $unsupported_home = "$unsupported_tmp/home";
my $unsupported_units = "$unsupported_tmp/user-units";
make_path( $unsupported_bin, $unsupported_home, $unsupported_units );
_write_executable(
    "$unsupported_bin/perl",
    "#!/bin/sh\nexec \"$^X\" \"\$@\"\n",
);

my $unsupported_install = qx{PATH="$unsupported_bin:$ENV{PATH}" HOME="$unsupported_home" DDSTARTUP_USER_UNIT_DIR="$unsupported_units" DDSTARTUP_SYSTEMCTL_BIN="journalctl_bin" make install};
is( $? >> 8, 0, 'make install stays clean on unsupported hosts' );
ok( !-f "$unsupported_units/developer-dashboard-startup.service", 'unsupported-host install skips unit creation' );

my $mac_tmp = tempdir( CLEANUP => 1 );
my $mac_bin = "$mac_tmp/bin";
my $mac_home = "$mac_tmp/home";
my $mac_agents = "$mac_tmp/LaunchAgents";
my $mac_logs = "$mac_tmp/Logs";
my $mac_calls_log = "$mac_tmp/launchctl.log";
my $mac_state_dir = "$mac_tmp/state";
make_path( $mac_bin, $mac_home, $mac_agents, $mac_logs, $mac_state_dir );

_write_executable(
    "$mac_bin/launchctl",
    <<"EOF",
#!/bin/sh
printf '%s\\n' "\$*" >>"$mac_calls_log"
loaded="$mac_state_dir/loaded"
case "\$1" in
  enable)
    exit 0
    ;;
  load)
    : >"\$loaded"
    exit 0
    ;;
  print-disabled)
    printf '\\tdisabled services = {\\n\\t}\\n'
    exit 0
    ;;
esac
exit 0
EOF
);
_write_executable(
    "$mac_bin/dashboard",
    "#!/bin/sh\nexit 0\n",
);

my $mac_install = qx{PATH="$mac_bin:$ENV{PATH}" HOME="$mac_home" DDSTARTUP_OSNAME=darwin DDSTARTUP_USER_LAUNCH_AGENTS_DIR="$mac_agents" DDSTARTUP_USER_LOGS_DIR="$mac_logs" DDSTARTUP_EUID=501 make install};
is( $? >> 8, 0, 'make install provisions launchd startup on macOS hosts' );
ok( -f "$mac_agents/developer-dashboard-startup.plist", 'mac make install writes the launch agent plist' );

open my $mfh, '<', $mac_calls_log or die "Unable to read $mac_calls_log: $!";
my $mac_calls = do { local $/; <$mfh> };
close $mfh or die "Unable to close $mac_calls_log: $!";
like( $mac_calls, qr/\Qenable user\/501\/developer-dashboard-startup\E/, 'mac make install enables the launchd label' );
like( $mac_calls, qr/\Qload -w \E/, 'mac make install loads the launch agent plist' );

done_testing();

sub _write_executable {
    my ( $path, $content ) = @_;
    open my $fh, '>', $path or die "Unable to write $path: $!";
    print {$fh} $content;
    close $fh or die "Unable to close $path: $!";
    chmod 0755, $path or die "Unable to chmod $path: $!";
    return 1;
}
