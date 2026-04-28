package DDStartup::Manager;

use strict;
use warnings;

use Cwd qw(abs_path getcwd);
use File::Path qw(make_path);
use File::Spec;
use JSON::PP qw(encode_json);

sub new {
    my ( $class, %args ) = @_;
    my $systemd_service_name = exists $args{service_name}
      ? $args{service_name}
      : ( $args{systemd_service_name} || 'developer-dashboard-startup.service' );
    my $launchd_label = $args{launchd_label} || _strip_service_suffix($systemd_service_name);
    my $osname = exists $args{osname} ? $args{osname} : ( $ENV{DDSTARTUP_OSNAME} || $^O );
    my $home = exists $args{home} ? $args{home} : ( $ENV{HOME} || q{} );
    my $cwd = exists $args{cwd} ? $args{cwd} : ( $args{home} || $ENV{HOME} || getcwd() );
    my $euid = defined $args{euid} ? $args{euid} : ( defined $ENV{DDSTARTUP_EUID} ? $ENV{DDSTARTUP_EUID} : $> );
    my $dashboard_bin = exists $args{dashboard_bin} ? $args{dashboard_bin} : _detect_dashboard_bin($home);
    my $perl_bin = exists $args{perl_bin} ? $args{perl_bin} : _detect_perl_bin($dashboard_bin);
    my $perl5lib = exists $args{perl5lib} ? $args{perl5lib} : _runtime_perl5lib($dashboard_bin);
    my $systemctl_bin = exists $args{systemctl_bin} ? $args{systemctl_bin} : ( $ENV{DDSTARTUP_SYSTEMCTL_BIN} || _which('systemctl') );
    my $journalctl_bin = exists $args{journalctl_bin} ? $args{journalctl_bin} : ( $ENV{DDSTARTUP_JOURNALCTL_BIN} || _which('journalctl') );
    my $launchctl_bin = exists $args{launchctl_bin} ? $args{launchctl_bin} : ( $ENV{DDSTARTUP_LAUNCHCTL_BIN} || _which('launchctl') );
    my $user_unit_dir = exists $args{user_unit_dir} ? $args{user_unit_dir} : ( $ENV{DDSTARTUP_USER_UNIT_DIR} || File::Spec->catdir( $ENV{HOME} || q{}, '.config', 'systemd', 'user' ) );
    my $system_unit_dir = exists $args{system_unit_dir} ? $args{system_unit_dir} : ( $ENV{DDSTARTUP_SYSTEM_UNIT_DIR} || File::Spec->catdir( File::Spec->rootdir(), 'etc', 'systemd', 'system' ) );
    my $user_launch_agents_dir = exists $args{user_launch_agents_dir} ? $args{user_launch_agents_dir} : ( $ENV{DDSTARTUP_USER_LAUNCH_AGENTS_DIR} || File::Spec->catdir( $ENV{HOME} || q{}, 'Library', 'LaunchAgents' ) );
    my $system_launch_daemons_dir = exists $args{system_launch_daemons_dir} ? $args{system_launch_daemons_dir} : ( $ENV{DDSTARTUP_SYSTEM_LAUNCH_DAEMONS_DIR} || File::Spec->catdir( File::Spec->rootdir(), 'Library', 'LaunchDaemons' ) );
    my $user_logs_dir = exists $args{user_logs_dir} ? $args{user_logs_dir} : ( $ENV{DDSTARTUP_USER_LOGS_DIR} || File::Spec->catdir( $ENV{HOME} || q{}, 'Library', 'Logs' ) );
    my $system_logs_dir = exists $args{system_logs_dir} ? $args{system_logs_dir} : ( $ENV{DDSTARTUP_SYSTEM_LOGS_DIR} || File::Spec->catdir( File::Spec->rootdir(), 'Library', 'Logs' ) );
    my $runner = $args{runner} || \&_run;

    my $self = bless {
        osname                    => $osname,
        home                      => $home,
        cwd                       => $cwd,
        euid                      => $euid,
        systemd_service_name      => $systemd_service_name,
        launchd_label             => $launchd_label,
        dashboard_bin             => $dashboard_bin,
        perl_bin                  => $perl_bin,
        perl5lib                  => $perl5lib,
        systemctl_bin             => $systemctl_bin,
        journalctl_bin            => $journalctl_bin,
        launchctl_bin             => $launchctl_bin,
        user_unit_dir             => $user_unit_dir,
        system_unit_dir           => $system_unit_dir,
        user_launch_agents_dir    => $user_launch_agents_dir,
        system_launch_daemons_dir => $system_launch_daemons_dir,
        user_logs_dir             => $user_logs_dir,
        system_logs_dir           => $system_logs_dir,
        runner                    => $runner,
    }, $class;
    return $self;
}

sub scope_from_args {
    my ( $self, @args ) = @_;
    return 'system' if grep { defined && $_ eq '--system' } @args;
    return 'user'   if grep { defined && $_ eq '--user' } @args;
    return $self->{euid} == 0 ? 'system' : 'user';
}

sub setup {
    my ( $self, @args ) = @_;
    return $self->_setup_launchd(@args) if $self->_is_macos;
    return $self->_setup_systemd(@args);
}

sub enable {
    my ( $self, @args ) = @_;
    return $self->setup(@args);
}

sub auto_setup {
    my ( $self, @args ) = @_;
    my $scope = $self->scope_from_args(@args);
    my $unit_path = $self->unit_path($scope);
    return {
        platform     => $self->platform,
        scope        => $scope,
        service_name => $self->service_name($scope),
        unit_path    => $unit_path,
        skipped      => 1,
        reason       => 'unit_exists',
    } if -e $unit_path;
    return {
        platform     => $self->platform,
        scope        => $scope,
        service_name => $self->service_name($scope),
        unit_path    => $unit_path,
        skipped      => 1,
        reason       => 'unsupported_host',
    } if !$self->_auto_setup_supported;
    return $self->setup(@args);
}

sub status {
    my ( $self, @args ) = @_;
    return $self->_status_launchd(@args) if $self->_is_macos;
    return $self->_status_systemd(@args);
}

sub logs {
    my ( $self, %args ) = @_;
    return $self->_logs_launchd(%args) if $self->_is_macos;
    return $self->_logs_systemd(%args);
}

sub disable {
    my ( $self, @args ) = @_;
    return $self->_disable_launchd(@args) if $self->_is_macos;
    return $self->_disable_systemd(@args);
}

sub remove {
    my ( $self, @args ) = @_;
    return $self->_remove_launchd(@args) if $self->_is_macos;
    return $self->_remove_systemd(@args);
}

sub parse_common_argv {
    my ( $self, @argv ) = @_;
    my $output = 'table';
    my @rest;
    while (@argv) {
        my $arg = shift @argv;
        if ( defined $arg && $arg eq '-o' ) {
            $output = shift @argv;
            next;
        }
        if ( defined $arg && $arg =~ /^-o=(.+)\z/ ) {
            $output = $1;
            next;
        }
        push @rest, $arg;
    }
    return ( $output || 'table', @rest );
}

sub render_result {
    my ( $self, %args ) = @_;
    my $output = $args{output} || 'table';
    my $type   = $args{type}   || 'record';
    my $result = $args{result};
    return encode_json($result) if $output eq 'json';
    return $self->format_logs_table($result) if $type eq 'logs';
    return $self->format_kv_table($result);
}

sub format_kv_table {
    my ( $self, $data ) = @_;
    my @preferred = qw(platform scope service_name unit_path dashboard working_directory wanted_by domain log_path activation enabled active disabled removed skipped reason);
    my %seen;
    my @keys = grep { exists $data->{$_} && !$seen{$_}++ } @preferred;
    push @keys, grep { !$seen{$_}++ } sort keys %{$data};
    my $width = 5;
    for my $key (@keys) {
        $width = length($key) if length($key) > $width;
    }
    my $text = sprintf "%-*s  %s\n", $width, 'FIELD', 'VALUE';
    $text .= sprintf "%-*s  %s\n", $width, '-' x $width, '-' x 5;
    for my $key (@keys) {
        my $value = $data->{$key};
        $value = '' if !defined $value;
        $value = $value ? 1 : 0 if ref(\$value) eq 'SCALAR' && ( $value eq '0' || $value eq '1' );
        $text .= sprintf "%-*s  %s\n", $width, $key, $value;
    }
    return $text;
}

sub format_logs_table {
    my ( $self, $data ) = @_;
    my $logs = defined $data->{logs} ? $data->{logs} : q{};
    $logs =~ s/\n\z//;
    my @lines = split /\n/, $logs;
    @lines = ('') if !@lines;
    my @rows = (
        [ platform     => $data->{platform} ],
        [ scope        => $data->{scope} ],
        [ service_name => $data->{service_name} ],
        [ lines        => $data->{lines} ],
        [ logs         => shift @lines ],
    );
    push @rows, map { [ q{}, $_ ] } @lines if @lines;
    my $width = length('service_name');
    $width = length('platform') if length('platform') > $width;
    my $text = sprintf "%-*s  %s\n", $width, 'FIELD', 'VALUE';
    $text .= sprintf "%-*s  %s\n", $width, '-' x $width, '-' x 5;
    for my $row (@rows) {
        my ( $key, $value ) = @{$row};
        $value = '' if !defined $value;
        $text .= sprintf "%-*s  %s\n", $width, $key, $value;
    }
    return $text;
}

sub platform {
    my ($self) = @_;
    return $self->_is_macos ? 'macos' : 'systemd';
}

sub service_name {
    my ( $self, $scope ) = @_;
    return $self->_is_macos ? $self->{launchd_label} : $self->{systemd_service_name};
}

sub unit_dir {
    my ( $self, $scope ) = @_;
    if ( $self->_is_macos ) {
        return $scope eq 'system' ? $self->{system_launch_daemons_dir} : $self->{user_launch_agents_dir};
    }
    return $scope eq 'system' ? $self->{system_unit_dir} : $self->{user_unit_dir};
}

sub unit_path {
    my ( $self, $scope ) = @_;
    my $name = $self->_is_macos ? $self->{launchd_label} . '.plist' : $self->{systemd_service_name};
    return File::Spec->catfile( $self->unit_dir($scope), $name );
}

sub unit_text {
    my ( $self, $scope ) = @_;
    return $self->_plist_text($scope) if $self->_is_macos;
    return $self->_unit_text_systemd($scope);
}

sub _setup_systemd {
    my ( $self, @args ) = @_;
    $self->_require_tool('systemctl');
    my $scope = $self->scope_from_args(@args);
    my $unit_path = $self->unit_path($scope);
    make_path( $self->unit_dir($scope) );
    _write_file( $unit_path, $self->unit_text($scope) );
    $self->_run_checked( $self->_systemctl_command( $scope, 'daemon-reload' ) );
    $self->_run_checked( $self->_systemctl_command( $scope, 'enable', '--now', $self->{systemd_service_name} ) );
    return {
        platform          => $self->platform,
        scope             => $scope,
        service_name      => $self->{systemd_service_name},
        unit_path         => $unit_path,
        dashboard         => $self->{dashboard_bin},
        working_directory => $self->{cwd},
        wanted_by         => $scope eq 'system' ? 'multi-user.target' : 'default.target',
    };
}

sub _setup_launchd {
    my ( $self, @args ) = @_;
    $self->_require_tool('launchctl');
    my $scope = $self->scope_from_args(@args);
    my $unit_path = $self->unit_path($scope);
    make_path( $self->unit_dir($scope), $self->_logs_dir($scope) );
    _write_file( $unit_path, $self->unit_text($scope) );
    my $domain = $self->_launchd_domain($scope);
    my $service_target = $self->_launchd_service_target($scope);
    $self->_run_checked( $self->_launchctl_command( 'enable', $service_target ) );
    my $load = $self->_run_capture( $self->_launchctl_command( 'load', '-w', $unit_path ) );
    return {
        platform          => $self->platform,
        scope             => $scope,
        service_name      => $self->{launchd_label},
        unit_path         => $unit_path,
        dashboard         => $self->{dashboard_bin},
        working_directory => $self->{cwd},
        wanted_by         => 'launchd',
        domain            => $domain,
        log_path          => $self->_logs_path($scope),
        activation        => $load->{exit} ? 'deferred' : 'loaded',
    };
}

sub _status_systemd {
    my ( $self, @args ) = @_;
    $self->_require_tool('systemctl');
    my $scope = $self->scope_from_args(@args);
    return {
        platform     => $self->platform,
        scope        => $scope,
        service_name => $self->{systemd_service_name},
        unit_path    => $self->unit_path($scope),
        enabled      => _trim( $self->_run_capture( $self->_systemctl_command( $scope, 'is-enabled', $self->{systemd_service_name} ) )->{stdout} ),
        active       => _trim( $self->_run_capture( $self->_systemctl_command( $scope, 'is-active', $self->{systemd_service_name} ) )->{stdout} ),
    };
}

sub _status_launchd {
    my ( $self, @args ) = @_;
    $self->_require_tool('launchctl');
    my $scope = $self->scope_from_args(@args);
    my $domain = $self->_launchd_domain($scope);
    my $disabled_domain = $self->_launchd_disabled_domain($scope);
    my $disabled = $self->_run_checked( $self->_launchctl_command( 'print-disabled', $disabled_domain ) )->{stdout};
    my $enabled = $disabled =~ /\Q"$self->{launchd_label}"\E\s*=>\s*disabled/ ? 'disabled' : 'enabled';
    my $active = 'inactive';
    if ( $enabled eq 'enabled' && -e $self->unit_path($scope) ) {
        my $list = $self->_run_capture( $self->_launchctl_command( 'list', $self->{launchd_label} ) );
        $active = ( !$list->{exit} && $list->{stdout} !~ /Could not find service/ ) ? 'active' : 'configured';
    }
    return {
        platform     => $self->platform,
        scope        => $scope,
        service_name => $self->{launchd_label},
        unit_path    => $self->unit_path($scope),
        domain       => $domain,
        enabled      => $enabled,
        active       => $active,
        log_path     => $self->_logs_path($scope),
    };
}

sub _logs_systemd {
    my ( $self, %args ) = @_;
    $self->_require_tool('journalctl');
    my $scope = $self->scope_from_args( @{ $args{argv} || [] } );
    my $lines = $args{lines} || 50;
    return $self->_run_checked(
        $self->_journalctl_command( $scope, '-u', $self->{systemd_service_name}, '--no-pager', '-n', $lines )
    )->{stdout};
}

sub _logs_launchd {
    my ( $self, %args ) = @_;
    my $scope = $self->scope_from_args( @{ $args{argv} || [] } );
    my $lines = $args{lines} || 50;
    return _tail_combined_logs( $self->_logs_path($scope), $self->_err_logs_path($scope), $lines );
}

sub _disable_systemd {
    my ( $self, @args ) = @_;
    $self->_require_tool('systemctl');
    my $scope = $self->scope_from_args(@args);
    my $unit_path = $self->unit_path($scope);
    $self->_run_checked( $self->_systemctl_command( $scope, 'disable', '--now', $self->{systemd_service_name} ) );
    return {
        platform     => $self->platform,
        scope        => $scope,
        service_name => $self->{systemd_service_name},
        unit_path    => $unit_path,
        disabled     => 1,
        removed      => 0,
    };
}

sub _disable_launchd {
    my ( $self, @args ) = @_;
    $self->_require_tool('launchctl');
    my $scope = $self->scope_from_args(@args);
    my $unit_path = $self->unit_path($scope);
    my $domain = $self->_launchd_domain($scope);
    my $service_target = $self->_launchd_service_target($scope);
    $self->_run_capture( $self->_launchctl_command( 'unload', '-w', $unit_path ) );
    $self->_run_checked( $self->_launchctl_command( 'disable', $service_target ) );
    return {
        platform     => $self->platform,
        scope        => $scope,
        service_name => $self->{launchd_label},
        unit_path    => $unit_path,
        domain       => $domain,
        disabled     => 1,
        removed      => 0,
    };
}

sub _remove_systemd {
    my ( $self, @args ) = @_;
    $self->_require_tool('systemctl');
    my $scope = $self->scope_from_args(@args);
    my $unit_path = $self->unit_path($scope);
    $self->_run_checked( $self->_systemctl_command( $scope, 'disable', '--now', $self->{systemd_service_name} ) );
    unlink $unit_path if -e $unit_path;
    $self->_run_checked( $self->_systemctl_command( $scope, 'daemon-reload' ) );
    return {
        platform     => $self->platform,
        scope        => $scope,
        service_name => $self->{systemd_service_name},
        unit_path    => $unit_path,
        removed      => -e $unit_path ? 0 : 1,
    };
}

sub _remove_launchd {
    my ( $self, @args ) = @_;
    $self->_require_tool('launchctl');
    my $scope = $self->scope_from_args(@args);
    my $unit_path = $self->unit_path($scope);
    my $domain = $self->_launchd_domain($scope);
    my $service_target = $self->_launchd_service_target($scope);
    $self->_run_capture( $self->_launchctl_command( 'unload', '-w', $unit_path ) );
    $self->_run_capture( $self->_launchctl_command( 'disable', $service_target ) );
    unlink $unit_path if -e $unit_path;
    return {
        platform     => $self->platform,
        scope        => $scope,
        service_name => $self->{launchd_label},
        unit_path    => $unit_path,
        domain       => $domain,
        removed      => -e $unit_path ? 0 : 1,
    };
}

sub _unit_text_systemd {
    my ( $self, $scope ) = @_;
    my $wanted_by = $scope eq 'system' ? 'multi-user.target' : 'default.target';
    return join "\n",
      '[Unit]',
      'Description=Developer Dashboard startup manager',
      'After=network.target',
      q{},
      '[Service]',
      'Type=oneshot',
      'RemainAfterExit=yes',
      'WorkingDirectory=' . $self->{cwd},
      'Environment=HOME=' . $self->{home},
      ( $self->{perl5lib} ne q{} ? ( 'Environment=PERL5LIB=' . $self->{perl5lib} ) : () ),
      'ExecStart=' . $self->{perl_bin} . ' ' . $self->{dashboard_bin} . ' restart',
      'ExecStop=' . $self->{perl_bin} . ' ' . $self->{dashboard_bin} . ' stop',
      'ExecReload=' . $self->{perl_bin} . ' ' . $self->{dashboard_bin} . ' restart',
      q{},
      '[Install]',
      'WantedBy=' . $wanted_by,
      q{};
}

sub _plist_text {
    my ( $self, $scope ) = @_;
    my @env_lines = (
        '    <key>HOME</key>',
        '    <string>' . _xml_escape( $self->{home} ) . '</string>',
    );
    if ( $self->{perl5lib} ne q{} ) {
        push @env_lines,
          '    <key>PERL5LIB</key>',
          '    <string>' . _xml_escape( $self->{perl5lib} ) . '</string>';
    }

    return join "\n",
      qq{<?xml version="1.0" encoding="UTF-8"?>},
      qq{<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">},
      qq{<plist version="1.0">},
      qq{<dict>},
      qq{  <key>Label</key>},
      qq{  <string>} . _xml_escape( $self->{launchd_label} ) . qq{</string>},
      qq{  <key>ProgramArguments</key>},
      qq{  <array>},
      qq{    <string>} . _xml_escape( $self->{perl_bin} ) . qq{</string>},
      qq{    <string>} . _xml_escape( $self->{dashboard_bin} ) . qq{</string>},
      qq{    <string>restart</string>},
      qq{  </array>},
      qq{  <key>WorkingDirectory</key>},
      qq{  <string>} . _xml_escape( $self->{cwd} ) . qq{</string>},
      qq{  <key>EnvironmentVariables</key>},
      qq{  <dict>},
      @env_lines,
      qq{  </dict>},
      qq{  <key>RunAtLoad</key>},
      qq{  <true/>},
      qq{  <key>StandardOutPath</key>},
      qq{  <string>} . _xml_escape( $self->_logs_path($scope) ) . qq{</string>},
      qq{  <key>StandardErrorPath</key>},
      qq{  <string>} . _xml_escape( $self->_err_logs_path($scope) ) . qq{</string>},
      qq{</dict>},
      qq{</plist>},
      q{};
}

sub _systemctl_command {
    my ( $self, $scope, @rest ) = @_;
    return $scope eq 'system'
      ? ( $self->{systemctl_bin}, @rest )
      : ( $self->{systemctl_bin}, '--user', @rest );
}

sub _journalctl_command {
    my ( $self, $scope, @rest ) = @_;
    return $scope eq 'system'
      ? ( $self->{journalctl_bin}, @rest )
      : ( $self->{journalctl_bin}, '--user', @rest );
}

sub _launchctl_command {
    my ( $self, @rest ) = @_;
    return ( $self->{launchctl_bin}, @rest );
}

sub _launchd_domain {
    my ( $self, $scope ) = @_;
    return $scope eq 'system' ? 'system' : 'user/' . $self->{euid};
}

sub _launchd_disabled_domain {
    my ( $self, $scope ) = @_;
    return $scope eq 'system' ? 'system' : 'user/' . $self->{euid};
}

sub _launchd_service_target {
    my ( $self, $scope ) = @_;
    return $scope eq 'system'
      ? 'system/' . $self->{launchd_label}
      : 'user/' . $self->{euid} . '/' . $self->{launchd_label};
}

sub _logs_dir {
    my ( $self, $scope ) = @_;
    return $scope eq 'system' ? $self->{system_logs_dir} : $self->{user_logs_dir};
}

sub _logs_path {
    my ( $self, $scope ) = @_;
    return File::Spec->catfile( $self->_logs_dir($scope), $self->{launchd_label} . '.log' );
}

sub _err_logs_path {
    my ( $self, $scope ) = @_;
    return File::Spec->catfile( $self->_logs_dir($scope), $self->{launchd_label} . '.err.log' );
}

sub _require_tool {
    my ( $self, $tool ) = @_;
    my %map = (
        systemctl  => $self->{systemctl_bin},
        journalctl => $self->{journalctl_bin},
        launchctl  => $self->{launchctl_bin},
    );
    my $path = $map{$tool};
    die "$tool is required for ddstartup\n" if !$path;
    return $path;
}

sub _run_checked {
    my ( $self, @cmd ) = @_;
    my $result = $self->_run_capture(@cmd);
    die join( q{ }, @cmd ) . " failed: $result->{stderr}\n" if $result->{exit};
    return $result;
}

sub _run_capture {
    my ( $self, @cmd ) = @_;
    return $self->{runner}->(@cmd);
}

sub _auto_setup_supported {
    my ($self) = @_;
    return _command_exists( $self->{launchctl_bin} ) if $self->_is_macos;
    return _command_exists( $self->{systemctl_bin} );
}

sub _is_macos {
    my ($self) = @_;
    return $self->{osname} eq 'darwin';
}

sub _runtime_perl5lib {
    my ($dashboard_bin) = @_;
    my @paths;

    push @paths, _dashboard_perl_lib_paths($dashboard_bin);

    if ( defined $ENV{PERL5LIB} && $ENV{PERL5LIB} ne q{} ) {
        push @paths, split /:/, $ENV{PERL5LIB};
    }
    else {
        push @paths, grep { defined && !ref } @INC;
    }

    my %seen;
    @paths = grep { defined && $_ ne q{} && !$seen{$_}++ } @paths;
    return join q{:}, @paths;
}

sub _detect_dashboard_bin {
    my ($home) = @_;
    my @candidates = grep { defined && $_ ne q{} } (
        _which('dashboard'),
        ( defined $home && $home ne q{} ? File::Spec->catfile( $home, 'perl5', 'bin', 'dashboard' ) : () ),
        ( defined $home && $home ne q{} ? File::Spec->catfile( $home, 'bin', 'dashboard' ) : () ),
        '/usr/local/bin/dashboard',
        '/usr/bin/dashboard',
    );

    my %seen;
    for my $candidate (@candidates) {
        next if $seen{$candidate}++;
        return $candidate if -x $candidate;
    }

    return 'dashboard';
}

sub _detect_perl_bin {
    my ($dashboard_bin) = @_;
    my @candidates;

    if ( defined $dashboard_bin && $dashboard_bin ne q{} && $dashboard_bin =~ m{/} ) {
        my ( $volume, $directories ) = File::Spec->splitpath($dashboard_bin);
        my $perl_sibling = File::Spec->catfile( $volume, $directories, 'perl' );
        push @candidates, $perl_sibling;
    }

    push @candidates, grep { defined && $_ ne q{} } ( $^X, _which('perl') );

    my %seen;
    for my $candidate (@candidates) {
        next if $seen{$candidate}++;
        return $candidate if -x $candidate;
    }

    return 'perl';
}

sub _dashboard_perl_lib_paths {
    my ($dashboard_bin) = @_;
    return if !defined $dashboard_bin || $dashboard_bin eq q{};

    my ( $volume, $directories ) = File::Spec->splitpath($dashboard_bin);
    my @dirs = File::Spec->splitdir($directories);
    pop @dirs if @dirs;

    my $base = File::Spec->catdir( $volume, @dirs );
    $base = abs_path($base) || $base;

    my @candidates = (
        File::Spec->catdir( $base, File::Spec->updir(), 'lib', 'perl5' ),
        File::Spec->catdir( $base, File::Spec->updir(), 'lib' ),
    );

    my @paths;
    for my $candidate (@candidates) {
        my $resolved = abs_path($candidate) || $candidate;
        push @paths, $resolved if -d $resolved;
    }

    return @paths;
}

sub _tail_combined_logs {
    my ( $stdout_path, $stderr_path, $lines ) = @_;
    my @entries;
    push @entries, split /\n/, _slurp($stdout_path);
    push @entries, split /\n/, _slurp($stderr_path);
    @entries = grep { defined && $_ ne q{} } @entries;
    @entries = @entries > $lines ? @entries[ -$lines .. -1 ] : @entries if $lines;
    return @entries ? join( "\n", @entries ) . "\n" : q{};
}

sub _run {
    my (@cmd) = @_;
    my $stdout = qx{@cmd 2>/tmp/ddstartup.stderr.$$};
    my $exit = $? >> 8;
    my $stderr = q{};
    if ( open my $efh, '<', "/tmp/ddstartup.stderr.$$" ) {
        local $/;
        $stderr = <$efh>;
        close $efh;
        unlink "/tmp/ddstartup.stderr.$$";
    }
    return {
        exit   => $exit,
        stdout => $stdout,
        stderr => $stderr,
    };
}

sub _trim {
    my ($value) = @_;
    $value = q{} if !defined $value;
    $value =~ s/\A\s+//;
    $value =~ s/\s+\z//;
    return $value;
}

sub _write_file {
    my ( $path, $content ) = @_;
    open my $fh, '>', $path or die "Unable to write $path: $!";
    print {$fh} $content;
    close $fh or die "Unable to close $path: $!";
    return 1;
}

sub _slurp {
    my ($path) = @_;
    return q{} if !defined $path || !-e $path;
    open my $fh, '<', $path or die "Unable to read $path: $!";
    local $/;
    my $content = <$fh>;
    close $fh or die "Unable to close $path: $!";
    return defined $content ? $content : q{};
}

sub _which {
    my ($name) = @_;
    return if !$name;
    for my $dir ( split /:/, $ENV{PATH} || q{} ) {
        my $path = File::Spec->catfile( $dir, $name );
        return $path if -x $path;
    }
    return;
}

sub _command_exists {
    my ($name) = @_;
    return 0 if !$name;
    return -x $name ? 1 : 0 if $name =~ m{/};
    return defined _which($name) ? 1 : 0;
}

sub _strip_service_suffix {
    my ($name) = @_;
    $name =~ s/\.service\z// if defined $name;
    return $name;
}

sub _xml_escape {
    my ($value) = @_;
    $value = q{} if !defined $value;
    $value =~ s/&/&amp;/g;
    $value =~ s/</&lt;/g;
    $value =~ s/>/&gt;/g;
    $value =~ s/"/&quot;/g;
    $value =~ s/'/&apos;/g;
    return $value;
}

1;
