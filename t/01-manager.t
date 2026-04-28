use strict;
use warnings;

use File::Path qw(make_path);
use File::Temp qw(tempdir);
use JSON::PP qw(decode_json);
use Test::More;

use lib 'lib';

use DDStartup::Manager;

my $tmp = tempdir( CLEANUP => 1 );
my $home = "$tmp/home";
make_path($home);

my @calls;
my $manager = DDStartup::Manager->new(
    home           => $home,
    cwd            => $home,
    euid           => 1000,
    dashboard_bin  => '/usr/bin/dashboard',
    perl5lib       => '/opt/dd/lib:/opt/perl5/lib/perl5',
    systemctl_bin  => '/usr/bin/systemctl',
    journalctl_bin => '/usr/bin/journalctl',
    user_unit_dir  => "$tmp/user-units",
    system_unit_dir => "$tmp/system-units",
    runner => sub {
        my (@cmd) = @_;
        push @calls, [@cmd];
        return { exit => 0, stdout => "ok\n", stderr => q{} };
    },
);

is( $manager->scope_from_args(), 'user', 'non-root default scope is user' );
is( $manager->scope_from_args('--system'), 'system', 'explicit system scope wins' );
is( $manager->scope_from_args('--user'), 'user', 'explicit user scope wins' );

my $auto_tmp = tempdir( CLEANUP => 1 );
my @auto_calls;
my $auto_manager = DDStartup::Manager->new(
    home            => "$auto_tmp/home",
    cwd             => "$auto_tmp/home",
    euid            => 1000,
    dashboard_bin   => '/usr/bin/dashboard',
    systemctl_bin   => '/usr/bin/systemctl',
    journalctl_bin  => '/usr/bin/journalctl',
    user_unit_dir   => "$auto_tmp/user-units",
    system_unit_dir => "$auto_tmp/system-units",
    runner => sub {
        my (@cmd) = @_;
        push @auto_calls, [@cmd];
        return { exit => 0, stdout => "ok\n", stderr => q{} };
    },
);
make_path("$auto_tmp/home");
my $auto_first = $auto_manager->auto_setup();
ok( !$auto_first->{skipped}, 'auto_setup provisions the unit on first install' );
is_deeply( $auto_calls[1], [ '/usr/bin/systemctl', '--user', 'enable', '--now', 'developer-dashboard-startup.service' ], 'auto_setup runs the user enable path when the unit is absent' );

my $setup = $manager->setup();
is( $setup->{scope}, 'user', 'setup defaults to user scope' );
like( $setup->{unit_path}, qr/user-units\/developer-dashboard-startup\.service\z/, 'setup returns the user unit path' );
is( $calls[0][0], '/usr/bin/systemctl', 'setup runs systemctl' );
is_deeply( $calls[0], [ '/usr/bin/systemctl', '--user', 'daemon-reload' ], 'setup reloads the user daemon' );
is_deeply( $calls[1], [ '/usr/bin/systemctl', '--user', 'enable', '--now', 'developer-dashboard-startup.service' ], 'setup enables and starts the user unit' );

@calls = ();
my $enable = $manager->enable();
is( $enable->{scope}, 'user', 'enable returns the user scope payload' );
is_deeply( $calls[1], [ '/usr/bin/systemctl', '--user', 'enable', '--now', 'developer-dashboard-startup.service' ], 'enable restores the unit through systemctl' );

open my $ufh, '<', $setup->{unit_path} or die "Unable to read $setup->{unit_path}: $!";
local $/;
my $unit = <$ufh>;
close $ufh or die "Unable to close $setup->{unit_path}: $!";
like( $unit, qr/\QExecStart=\/usr\/bin\/dashboard restart\E/, 'unit file starts DD through dashboard restart' );
like( $unit, qr/\QExecStop=\/usr\/bin\/dashboard stop\E/, 'unit file stops DD through dashboard stop' );
like( $unit, qr/\QWantedBy=default.target\E/, 'user scope unit uses default.target' );
like( $unit, qr/\QEnvironment=PERL5LIB=\/opt\/dd\/lib:\/opt\/perl5\/lib\/perl5\E/, 'unit file preserves PERL5LIB when the runtime depends on it' );

{
    local $ENV{PERL5LIB};
    local @INC = ( '/opt/dd/lib', '/opt/perl5/lib/perl5', @INC );
    my $inc_manager = DDStartup::Manager->new(
        home            => $home,
        cwd             => $home,
        euid            => 1000,
        dashboard_bin   => '/usr/bin/dashboard',
        systemctl_bin   => '/usr/bin/systemctl',
        journalctl_bin  => '/usr/bin/journalctl',
        user_unit_dir   => "$tmp/inc-user-units",
        system_unit_dir => "$tmp/inc-system-units",
        runner          => sub { return { exit => 0, stdout => "ok\n", stderr => q{} } },
    );
    like(
        $inc_manager->unit_text('user'),
        qr/\QEnvironment=PERL5LIB=\/opt\/dd\/lib:\/opt\/perl5\/lib\/perl5\E/,
        'unit file falls back to runtime @INC when PERL5LIB is unset',
    );
}

@calls = ();
my $status = $manager->status();
is( $status->{enabled}, 'ok', 'status reports enabled state' );
is( $status->{active}, 'ok', 'status reports active state' );
is_deeply( $calls[0], [ '/usr/bin/systemctl', '--user', 'is-enabled', 'developer-dashboard-startup.service' ], 'status asks whether the unit is enabled' );
is_deeply( $calls[1], [ '/usr/bin/systemctl', '--user', 'is-active', 'developer-dashboard-startup.service' ], 'status asks whether the unit is active' );

@calls = ();
my $logs = $manager->logs( lines => 20 );
is( $logs, "ok\n", 'logs returns the journal output' );
is_deeply( $calls[0], [ '/usr/bin/journalctl', '--user', '-u', 'developer-dashboard-startup.service', '--no-pager', '-n', 20 ], 'logs uses journalctl with the requested line count' );

@calls = ();
my $disable = $manager->disable();
ok( $disable->{disabled}, 'disable reports the unit as disabled' );
ok( -e $setup->{unit_path}, 'disable keeps the unit file for later enable' );
is_deeply( $calls[0], [ '/usr/bin/systemctl', '--user', 'disable', '--now', 'developer-dashboard-startup.service' ], 'disable stops and disables the user unit without deleting the file' );

my $auto_skip = $manager->auto_setup();
ok( $auto_skip->{skipped}, 'auto_setup skips when the unit already exists' );
is( $auto_skip->{reason}, 'unit_exists', 'auto_setup explains why it skipped' );

my $unsupported_auto = DDStartup::Manager->new(
    home            => "$tmp/no-systemd-home",
    cwd             => "$tmp/no-systemd-home",
    euid            => 1000,
    dashboard_bin   => '/usr/bin/dashboard',
    systemctl_bin   => 'journalctl_bin',
    journalctl_bin  => '/usr/bin/journalctl',
    user_unit_dir   => "$tmp/no-systemd-user-units",
    system_unit_dir => "$tmp/no-systemd-system-units",
    runner          => sub { die 'auto_setup should not run systemctl on unsupported hosts' },
)->auto_setup();
ok( $unsupported_auto->{skipped}, 'auto_setup skips on unsupported hosts' );
is( $unsupported_auto->{reason}, 'unsupported_host', 'auto_setup reports an unsupported-host skip reason' );

@calls = ();
my $remove = $manager->remove();
ok( $remove->{removed}, 'remove reports the unit as removed' );
ok( !-e $setup->{unit_path}, 'remove deletes the unit file' );
is_deeply( $calls[0], [ '/usr/bin/systemctl', '--user', 'disable', '--now', 'developer-dashboard-startup.service' ], 'remove disables the user unit' );
is_deeply( $calls[1], [ '/usr/bin/systemctl', '--user', 'daemon-reload' ], 'remove reloads the daemon after removing the unit' );

my $root_manager = DDStartup::Manager->new(
    home            => '/root',
    cwd             => '/root',
    euid            => 0,
    dashboard_bin   => '/usr/bin/dashboard',
    systemctl_bin   => '/usr/bin/systemctl',
    journalctl_bin  => '/usr/bin/journalctl',
    user_unit_dir   => "$tmp/ignored-user-units",
    system_unit_dir => "$tmp/root-units",
    runner => sub { return { exit => 0, stdout => "active\n", stderr => q{} } },
);

is( $root_manager->scope_from_args(), 'system', 'root default scope is system' );
my $root_setup = $root_manager->setup();
like( $root_setup->{unit_path}, qr/root-units\/developer-dashboard-startup\.service\z/, 'root setup uses the system unit path' );
is( $root_setup->{wanted_by}, 'multi-user.target', 'system scope uses multi-user.target' );

my $root_auto = $root_manager->auto_setup();
ok( $root_auto->{skipped}, 'root auto_setup also skips when the system unit already exists' );

my ( $output_mode, @parsed ) = $manager->parse_common_argv( '--user', '-o', 'json' );
is( $output_mode, 'json', 'parse_common_argv accepts explicit json output' );
is_deeply( \@parsed, ['--user'], 'parse_common_argv preserves non-output args' );

( $output_mode, @parsed ) = $manager->parse_common_argv('--system');
is( $output_mode, 'table', 'parse_common_argv defaults to table output' );
is_deeply( \@parsed, ['--system'], 'parse_common_argv keeps scope flags' );

( $output_mode, @parsed ) = $manager->parse_common_argv('-o=json', '--user');
is( $output_mode, 'json', 'parse_common_argv accepts inline output form' );
is_deeply( \@parsed, ['--user'], 'parse_common_argv keeps other args with inline output form' );

my $record_table = $manager->render_result(
    output => 'table',
    type   => 'record',
    result => $status,
);
like( $record_table, qr/\bFIELD\b/, 'record table includes a header row' );
like( $record_table, qr/\benabled\b.*\bok\b/s, 'record table renders key-value rows' );

my $record_json = $manager->render_result(
    output => 'json',
    type   => 'record',
    result => $status,
);
is( decode_json($record_json)->{active}, 'ok', 'record json output stays machine-readable' );

my $logs_table = $manager->render_result(
    output => 'table',
    type   => 'logs',
    result => {
        scope        => 'user',
        service_name => 'developer-dashboard-startup.service',
        lines        => 20,
        logs         => "alpha\nbeta\n",
    },
);
like( $logs_table, qr/\blogs\b.*alpha/s, 'logs table renders the first log line' );
like( $logs_table, qr/\n\s*beta\n/s, 'logs table keeps later log lines on following rows' );

my $missing_tool_error = eval {
    DDStartup::Manager->new(
        home          => $home,
        cwd           => $home,
        euid          => 1000,
        dashboard_bin => '/usr/bin/dashboard',
        systemctl_bin => undef,
    )->setup();
    return;
};
like( $@, qr/systemctl is required/, 'setup fails clearly when systemctl is unavailable' );

$missing_tool_error = eval {
    DDStartup::Manager->new(
        home          => $home,
        cwd           => $home,
        euid          => 1000,
        dashboard_bin => '/usr/bin/dashboard',
        systemctl_bin => '/usr/bin/systemctl',
        journalctl_bin => undef,
    )->logs();
    return;
};
like( $@, qr/journalctl is required/, 'logs fail clearly when journalctl is unavailable' );

ok( !defined DDStartup::Manager::_which('definitely-missing-ddstartup-test-binary'), '_which returns undef for missing commands' );

my $real_bin = "$tmp/real-bin";
make_path($real_bin);
_write_executable(
    "$real_bin/systemctl",
    "#!/bin/sh\nif [ \"\$1\" = \"is-enabled\" ]; then printf 'enabled\\n'; exit 0; fi\nif [ \"\$1\" = \"is-active\" ]; then printf 'active\\n'; exit 0; fi\nexit 0\n",
);
_write_executable(
    "$real_bin/journalctl",
    "#!/bin/sh\nprintf 'system journal\\n'\n",
);
_write_executable(
    "$real_bin/dashboard",
    "#!/bin/sh\nexit 0\n",
);

{
    local $ENV{PATH} = $real_bin;
    my $real_manager = DDStartup::Manager->new(
        home            => '/root',
        cwd             => '/root',
        euid            => 0,
        system_unit_dir => "$tmp/system-real",
    );
    is( $real_manager->logs( lines => 7, argv => ['--system'] ), "system journal\n", 'default runner reads system-scope journal output' );
}

my $mac_tmp = tempdir( CLEANUP => 1 );
my $mac_home = "$mac_tmp/home";
my $mac_launch_agents = "$mac_tmp/LaunchAgents";
my $mac_launch_daemons = "$mac_tmp/LaunchDaemons";
my $mac_logs_dir = "$mac_tmp/Logs";
my $mac_calls_log = "$mac_tmp/launchctl.log";
my $mac_state_dir = "$mac_tmp/state";
make_path( $mac_home, $mac_launch_agents, $mac_launch_daemons, $mac_logs_dir, $mac_state_dir );

_write_executable(
    "$real_bin/launchctl",
    <<"EOF",
#!/bin/sh
printf '%s\\n' "\$*" >>"$mac_calls_log"
state_dir="$mac_state_dir"
loaded="$mac_state_dir/loaded"
disabled="$mac_state_dir/disabled"
case "\$1" in
  enable)
    rm -f "\$disabled"
    exit 0
    ;;
  disable)
    : >"\$disabled"
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

my $mac_manager = DDStartup::Manager->new(
    osname                    => 'darwin',
    home                      => $mac_home,
    cwd                       => $mac_home,
    euid                      => 501,
    dashboard_bin             => '/usr/local/bin/dashboard',
    perl5lib                  => '/opt/dd/lib:/opt/perl5/lib/perl5',
    launchctl_bin             => "$real_bin/launchctl",
    user_launch_agents_dir    => $mac_launch_agents,
    system_launch_daemons_dir => $mac_launch_daemons,
    user_logs_dir             => $mac_logs_dir,
    system_logs_dir           => "$mac_tmp/SystemLogs",
);

my $mac_setup = $mac_manager->setup();
is( $mac_setup->{platform}, 'macos', 'mac setup reports the mac platform' );
is( $mac_setup->{scope}, 'user', 'mac setup defaults to user scope' );
like( $mac_setup->{unit_path}, qr/LaunchAgents\/developer-dashboard-startup\.plist\z/, 'mac setup returns the user plist path' );
is( $mac_setup->{domain}, 'user/501', 'mac setup returns the expected launchctl domain' );
is( $mac_setup->{wanted_by}, 'launchd', 'mac setup reports launchd instead of systemd wanted_by' );
is( $mac_setup->{activation}, 'loaded', 'mac setup reports an immediate load when launchctl load succeeds' );

open my $mfh, '<', $mac_setup->{unit_path} or die "Unable to read $mac_setup->{unit_path}: $!";
local $/;
my $plist = <$mfh>;
close $mfh or die "Unable to close $mac_setup->{unit_path}: $!";
like( $plist, qr/<key>Label<\/key>\s*<string>developer-dashboard-startup<\/string>/s, 'mac plist includes the launchd label' );
like( $plist, qr/<key>RunAtLoad<\/key>\s*<true\/>/s, 'mac plist runs at load' );
like( $plist, qr{\Q/usr/local/bin/dashboard\E}s, 'mac plist carries the dashboard path' );
like( $plist, qr{\Q$mac_logs_dir/developer-dashboard-startup.log\E}s, 'mac plist writes stdout logs to the expected path' );
like( $plist, qr{\Q$mac_logs_dir/developer-dashboard-startup.err.log\E}s, 'mac plist writes stderr logs to the expected path' );

my $mac_status = $mac_manager->status();
is( $mac_status->{enabled}, 'enabled', 'mac status reports the service as enabled' );
is( $mac_status->{active}, 'active', 'mac status reports the service as active after setup' );

_write_file( "$mac_logs_dir/developer-dashboard-startup.log", "alpha\nbeta\n" );
_write_file( "$mac_logs_dir/developer-dashboard-startup.err.log", "gamma\n" );
is( $mac_manager->logs( lines => 3 ), "alpha\nbeta\ngamma\n", 'mac logs return combined stdout and stderr log lines' );

my $mac_disable = $mac_manager->disable();
ok( $mac_disable->{disabled}, 'mac disable reports success' );
ok( -e $mac_setup->{unit_path}, 'mac disable keeps the plist file for later enable' );
my $mac_disabled_status = $mac_manager->status();
is( $mac_disabled_status->{enabled}, 'disabled', 'mac status reports disabled after disable' );
is( $mac_disabled_status->{active}, 'inactive', 'mac status reports inactive after disable' );

my $mac_enable = $mac_manager->enable();
is( $mac_enable->{scope}, 'user', 'mac enable returns user scope payload' );
my $mac_reenabled_status = $mac_manager->status();
is( $mac_reenabled_status->{enabled}, 'enabled', 'mac status reports enabled after enable' );
is( $mac_reenabled_status->{active}, 'active', 'mac status reports active after enable' );

my $mac_remove = $mac_manager->remove();
ok( $mac_remove->{removed}, 'mac remove reports success' );
ok( !-e $mac_setup->{unit_path}, 'mac remove deletes the plist file' );

open my $mcl, '<', $mac_calls_log or die "Unable to read $mac_calls_log: $!";
my $mac_calls = do { local $/; <$mcl> };
close $mcl or die "Unable to close $mac_calls_log: $!";
like( $mac_calls, qr/\Qenable user\/501\/developer-dashboard-startup\E/, 'mac setup enables the launchd label' );
like( $mac_calls, qr/\Qload -w \E/, 'mac setup loads the launch agent plist' );
like( $mac_calls, qr/\Qdisable user\/501\/developer-dashboard-startup\E/, 'mac disable disables the launchd label' );
like( $mac_calls, qr/\Qunload -w \E/, 'mac disable or remove unloads the launchd job' );

my $mac_auto_tmp = tempdir( CLEANUP => 1 );
my $mac_auto_home = "$mac_auto_tmp/home";
my $mac_auto_agents = "$mac_auto_tmp/LaunchAgents";
my $mac_auto_logs = "$mac_auto_tmp/Logs";
make_path( $mac_auto_home, $mac_auto_agents, $mac_auto_logs );
my $mac_auto = DDStartup::Manager->new(
    osname                 => 'darwin',
    home                   => $mac_auto_home,
    cwd                    => $mac_auto_home,
    euid                   => 501,
    dashboard_bin          => '/usr/local/bin/dashboard',
    launchctl_bin          => "$real_bin/launchctl",
    user_launch_agents_dir => $mac_auto_agents,
    user_logs_dir          => $mac_auto_logs,
);
my $mac_auto_first = $mac_auto->auto_setup();
ok( !$mac_auto_first->{skipped}, 'mac auto_setup provisions the launch agent on first install' );

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
