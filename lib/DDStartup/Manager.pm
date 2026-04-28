package DDStartup::Manager;

use strict;
use warnings;

use Cwd qw(getcwd);
use File::Path qw(make_path);
use File::Spec;
use JSON::PP qw(encode_json);

sub new {
    my ( $class, %args ) = @_;
    my $self = bless {
        home            => exists $args{home} ? $args{home} : ( $ENV{HOME} || q{} ),
        cwd             => exists $args{cwd} ? $args{cwd} : ( $args{home} || $ENV{HOME} || getcwd() ),
        euid            => defined $args{euid} ? $args{euid} : ( defined $ENV{DDSTARTUP_EUID} ? $ENV{DDSTARTUP_EUID} : $> ),
        service_name    => $args{service_name} || 'developer-dashboard-startup.service',
        dashboard_bin   => exists $args{dashboard_bin} ? $args{dashboard_bin} : ( _which('dashboard') || 'dashboard' ),
        perl5lib        => exists $args{perl5lib} ? $args{perl5lib} : _runtime_perl5lib(),
        systemctl_bin   => exists $args{systemctl_bin} ? $args{systemctl_bin} : ( $ENV{DDSTARTUP_SYSTEMCTL_BIN} || _which('systemctl') ),
        journalctl_bin  => exists $args{journalctl_bin} ? $args{journalctl_bin} : ( $ENV{DDSTARTUP_JOURNALCTL_BIN} || _which('journalctl') ),
        user_unit_dir   => exists $args{user_unit_dir} ? $args{user_unit_dir} : ( $ENV{DDSTARTUP_USER_UNIT_DIR} || File::Spec->catdir( $ENV{HOME} || q{}, '.config', 'systemd', 'user' ) ),
        system_unit_dir => exists $args{system_unit_dir} ? $args{system_unit_dir} : ( $ENV{DDSTARTUP_SYSTEM_UNIT_DIR} || File::Spec->catdir( File::Spec->rootdir(), 'etc', 'systemd', 'system' ) ),
        runner          => $args{runner} || \&_run,
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
    $self->_require_tool('systemctl');
    my $scope = $self->scope_from_args(@args);
    my $unit_path = $self->unit_path($scope);
    make_path( $self->unit_dir($scope) );
    _write_file( $unit_path, $self->unit_text($scope) );
    $self->_run_checked( $self->_systemctl_command( $scope, 'daemon-reload' ) );
    $self->_run_checked( $self->_systemctl_command( $scope, 'enable', '--now', $self->{service_name} ) );
    return {
        scope             => $scope,
        service_name      => $self->{service_name},
        unit_path         => $unit_path,
        dashboard         => $self->{dashboard_bin},
        working_directory => $self->{cwd},
        wanted_by         => $scope eq 'system' ? 'multi-user.target' : 'default.target',
    };
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
        scope        => $scope,
        service_name => $self->{service_name},
        unit_path    => $unit_path,
        skipped      => 1,
        reason       => 'unit_exists',
    } if -e $unit_path;
    return $self->setup(@args);
}

sub status {
    my ( $self, @args ) = @_;
    $self->_require_tool('systemctl');
    my $scope = $self->scope_from_args(@args);
    return {
        scope        => $scope,
        service_name => $self->{service_name},
        unit_path    => $self->unit_path($scope),
        enabled      => _trim( $self->_run_capture( $self->_systemctl_command( $scope, 'is-enabled', $self->{service_name} ) )->{stdout} ),
        active       => _trim( $self->_run_capture( $self->_systemctl_command( $scope, 'is-active',  $self->{service_name} ) )->{stdout} ),
    };
}

sub logs {
    my ( $self, %args ) = @_;
    $self->_require_tool('journalctl');
    my $scope = $self->scope_from_args( @{ $args{argv} || [] } );
    my $lines = $args{lines} || 50;
    return $self->_run_checked(
        $self->_journalctl_command( $scope, '-u', $self->{service_name}, '--no-pager', '-n', $lines )
    )->{stdout};
}

sub disable {
    my ( $self, @args ) = @_;
    $self->_require_tool('systemctl');
    my $scope = $self->scope_from_args(@args);
    my $unit_path = $self->unit_path($scope);
    $self->_run_checked( $self->_systemctl_command( $scope, 'disable', '--now', $self->{service_name} ) );
    return {
        scope        => $scope,
        service_name => $self->{service_name},
        unit_path    => $unit_path,
        disabled     => 1,
        removed      => 0,
    };
}

sub remove {
    my ( $self, @args ) = @_;
    $self->_require_tool('systemctl');
    my $scope = $self->scope_from_args(@args);
    my $unit_path = $self->unit_path($scope);
    $self->_run_checked( $self->_systemctl_command( $scope, 'disable', '--now', $self->{service_name} ) );
    unlink $unit_path if -e $unit_path;
    $self->_run_checked( $self->_systemctl_command( $scope, 'daemon-reload' ) );
    return {
        scope        => $scope,
        service_name => $self->{service_name},
        unit_path    => $unit_path,
        removed      => -e $unit_path ? 0 : 1,
    };
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
    my @keys = grep { exists $data->{$_} } qw(scope service_name unit_path dashboard working_directory wanted_by enabled active disabled removed skipped reason);
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
        [ scope        => $data->{scope} ],
        [ service_name => $data->{service_name} ],
        [ lines        => $data->{lines} ],
        [ logs         => shift @lines ],
    );
    push @rows, map { [ q{}, $_ ] } @lines if @lines;
    my $width = length('service_name');
    my $text = sprintf "%-*s  %s\n", $width, 'FIELD', 'VALUE';
    $text .= sprintf "%-*s  %s\n", $width, '-' x $width, '-' x 5;
    for my $row (@rows) {
        my ( $key, $value ) = @{$row};
        $value = '' if !defined $value;
        $text .= sprintf "%-*s  %s\n", $width, $key, $value;
    }
    return $text;
}

sub unit_dir {
    my ( $self, $scope ) = @_;
    return $scope eq 'system' ? $self->{system_unit_dir} : $self->{user_unit_dir};
}

sub unit_path {
    my ( $self, $scope ) = @_;
    return File::Spec->catfile( $self->unit_dir($scope), $self->{service_name} );
}

sub unit_text {
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
      'ExecStart=' . $self->{dashboard_bin} . ' restart',
      'ExecStop=' . $self->{dashboard_bin} . ' stop',
      'ExecReload=' . $self->{dashboard_bin} . ' restart',
      q{},
      '[Install]',
      'WantedBy=' . $wanted_by,
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

sub _require_tool {
    my ( $self, $tool ) = @_;
    my $path = $tool eq 'systemctl' ? $self->{systemctl_bin} : $self->{journalctl_bin};
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

sub _runtime_perl5lib {
    return $ENV{PERL5LIB} if defined $ENV{PERL5LIB} && $ENV{PERL5LIB} ne q{};
    my @inc = grep { defined && !ref } @INC;
    return join q{:}, @inc;
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

sub _which {
    my ($name) = @_;
    return if !$name;
    for my $dir ( split /:/, $ENV{PATH} || q{} ) {
        my $path = File::Spec->catfile( $dir, $name );
        return $path if -x $path;
    }
    return;
}

1;
