use strict;
use warnings;

use File::Path qw(make_path);
use File::Temp qw(tempdir);
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

done_testing();

sub _write_executable {
    my ( $path, $content ) = @_;
    open my $fh, '>', $path or die "Unable to write $path: $!";
    print {$fh} $content;
    close $fh or die "Unable to close $path: $!";
    chmod 0755, $path or die "Unable to chmod $path: $!";
    return 1;
}
