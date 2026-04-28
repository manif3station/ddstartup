# ddstartup Usage

## Install

```bash
dashboard skills install git@github.com:manif3station/ddstartup.git
```

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

## Unit Paths

- user scope: `~/.config/systemd/user/developer-dashboard-startup.service`
- system scope: `/etc/systemd/system/developer-dashboard-startup.service`

## Edge Cases

- if `systemctl` is missing, setup, status, and remove fail
- if `journalctl` is missing, logs fail
- if the skill is installed on a non-systemd host, the install-time Makefile target fails because this release only supports `systemctl` and `journalctl`
- if the host is not systemd-based, this skill is not the right startup manager yet
