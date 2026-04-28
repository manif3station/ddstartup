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
my $setup_payload = decode_json($setup);
is( $setup_payload->{scope}, 'user', 'cli/setup defaults to user scope' );

my $disable = qx{$^X cli/disable};
is( $? >> 8, 0, 'cli/disable exits cleanly' );
my $disable_payload = decode_json($disable);
ok( $disable_payload->{disabled}, 'cli/disable reports success' );

my $enable = qx{$^X cli/enable};
is( $? >> 8, 0, 'cli/enable exits cleanly' );
my $enable_payload = decode_json($enable);
is( $enable_payload->{scope}, 'user', 'cli/enable restores user scope startup' );

my $status = qx{$^X cli/status};
is( $? >> 8, 0, 'cli/status exits cleanly' );
my $status_payload = decode_json($status);
is( $status_payload->{active}, 'active', 'cli/status reports active state' );
is( $status_payload->{enabled}, 'enabled', 'cli/status reports enabled state' );

my $logs = qx{$^X cli/logs --lines 12};
is( $? >> 8, 0, 'cli/logs exits cleanly' );
is( $logs, "journal line\n", 'cli/logs prints journal output' );

my $remove = qx{$^X cli/remove};
is( $? >> 8, 0, 'cli/remove exits cleanly' );
my $remove_payload = decode_json($remove);
ok( $remove_payload->{removed}, 'cli/remove reports success' );

open my $lfh, '<', $logs_file or die "Unable to read $logs_file: $!";
local $/;
my $calls = <$lfh>;
close $lfh or die "Unable to close $logs_file: $!";
like( $calls, qr/--user daemon-reload/, 'cli/setup used user-scope systemctl reload' );
like( $calls, qr/--user -u developer-dashboard-startup\.service --no-pager -n 12/, 'cli/logs used the requested line count' );
like( $calls, qr/--user disable --now developer-dashboard-startup\.service/, 'cli/disable disabled the user unit' );
like( $calls, qr/--user enable --now developer-dashboard-startup\.service/, 'cli/enable enabled the user unit' );

done_testing();

sub _write_executable {
    my ( $path, $content ) = @_;
    open my $fh, '>', $path or die "Unable to write $path: $!";
    print {$fh} $content;
    close $fh or die "Unable to close $path: $!";
    chmod 0755, $path or die "Unable to chmod $path: $!";
    return 1;
}
