# ddstartup Usage

## Install

```bash
dashboard skills install git@github.com:manif3station/ddstartup.git
```

Install auto-provisions startup on supported hosts:

- systemd hosts get a `.service` unit
- macOS hosts get a launchd `.plist`

In non-GUI macOS sessions such as SSH shells, install and setup can report deferred activation while still writing and enabling the launch agent.

## Commands

Output mode:

- default output is a readable table
- `-o json` switches any `ddstartup` command to JSON

Set up a startup unit:

```bash
dashboard ddstartup.setup
```

Restore or create the startup unit explicitly:

```bash
dashboard ddstartup.enable
```

Disable startup without deleting the unit file:

```bash
dashboard ddstartup.disable
```

Force user scope:

```bash
dashboard ddstartup.setup --user
```

Force system scope:

```bash
dashboard ddstartup.setup --system
```

Inspect unit state:

```bash
dashboard ddstartup.status
```

Inspect the same state as JSON:

```bash
dashboard ddstartup.status -o json
```

Read recent logs:

```bash
dashboard ddstartup.logs
```

Read a shorter log window:

```bash
dashboard ddstartup.logs --lines 20
```

Read logs as JSON:

```bash
dashboard ddstartup.logs -o json --lines 20
```

Remove the unit:

```bash
dashboard ddstartup.remove
```

Get remove confirmation as JSON:

```bash
dashboard ddstartup.remove -o json
```

## Scope Rules

- root defaults to system scope
- non-root defaults to user scope
- `--system` forces system scope
- `--user` forces user scope

## Runtime Environment

`ddstartup` writes the active DD Perl library path into the generated unit so `dashboard restart` can run under systemd without depending on shell-only `PERL5LIB` setup.

On macOS, the generated plist carries the same `HOME` and `PERL5LIB` information through launchd `EnvironmentVariables`.

## Unit Paths

- user scope: `~/.config/systemd/user/developer-dashboard-startup.service`
- system scope: `/etc/systemd/system/developer-dashboard-startup.service`

## macOS Paths

- user scope: `~/Library/LaunchAgents/developer-dashboard-startup.plist`
- system scope: `/Library/LaunchDaemons/developer-dashboard-startup.plist`
- user logs: `~/Library/Logs/developer-dashboard-startup.log`
- user stderr logs: `~/Library/Logs/developer-dashboard-startup.err.log`

## macOS Status Semantics

- `enabled` means the launchd label is enabled in the user or system domain
- `active=active` means the current session can prove the launchd job is loaded
- `active=configured` means the plist is installed and enabled but the current shell did not prove a live loaded job
- `activation=deferred` from setup means the plist was written and enabled but immediate loading was not proven in the current session

## Edge Cases

- if `systemctl` is missing on a systemd-targeted host, setup, status, and remove fail
- if `journalctl` is missing on a systemd-targeted host, logs fail
- if `launchctl` can enable the launch agent but the current macOS shell cannot load it immediately, setup reports deferred activation instead of failing
- if the host is neither systemd-based nor macOS, install-time auto-setup skips that host because there is no supported startup backend yet
