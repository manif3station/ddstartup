# ddstartup

## Description

`ddstartup` is a Developer Dashboard skill that installs and manages a systemd startup unit for Developer Dashboard so `dashboard restart` can be run automatically when the machine boots.

## Value

It gives the user a repeatable way to:

- install DD startup at user scope when they manage DD in their own home runtime
- install DD startup at system scope when root manages DD for the host
- inspect the managed service state with `systemctl`
- inspect the managed service logs with `journalctl`
- remove the startup wiring cleanly when it is no longer wanted

## Problem It Solves

Without a managed startup unit, users have to remember to bring DD back with `dashboard restart` after reboot. That is easy to forget and breaks the expectation that DD will already be alive when the user opens a shell or browser.

## What It Does To Solve It

`ddstartup` writes a systemd unit that runs `dashboard restart`, enables that unit through `systemctl`, exposes a status view backed by `systemctl`, exposes a logs view backed by `journalctl`, and can disable and remove the unit again.

It also preserves the Perl runtime library path needed by the installed `dashboard` executable so the generated unit can start successfully under systemd even when the interactive shell normally provides that path.

## Developer Dashboard Feature Added

This skill adds:

- `dashboard ddstartup.setup`
- `dashboard ddstartup.enable`
- `dashboard ddstartup.disable`
- `dashboard ddstartup.status`
- `dashboard ddstartup.logs`
- `dashboard ddstartup.remove`

## Layout

- `cli/` skill CLI entrypoints
- `lib/DDStartup/Manager.pm` implementation module
- `docs/` skill-local documentation
- `t/` skill-local tests
- `tickets/` project-management records
- `.env` skill-local version metadata
- `Changes` skill-local changelog

## Installation

Install the skill through Developer Dashboard from a git repository:

```bash
dashboard skills install <git-url-to-ddstartup-skill>
```

Example:

```bash
dashboard skills install git@github.com:manif3station/ddstartup.git
```

When this skill is installed through `dashboard skills install`, its `Makefile` install target automatically provisions the startup unit. The user does not need to run a separate setup command after installation.

## CLI Usage

Output mode:

- default output is a human-readable table
- pass `-o json` when you want machine-readable JSON

Normal user-scope setup:

```bash
dashboard ddstartup.setup
```

Explicit enable after a previous disable:

```bash
dashboard ddstartup.enable
```

Explicit user-scope setup:

```bash
dashboard ddstartup.setup --user
```

Explicit system-scope setup when running as root:

```bash
dashboard ddstartup.setup --system
```

Example setup result:

```text
FIELD              VALUE
-----------------  -----
scope              user
service_name       developer-dashboard-startup.service
unit_path          ~/.config/systemd/user/developer-dashboard-startup.service
dashboard          /usr/bin/dashboard
working_directory  ~
wanted_by          default.target
```

JSON form:

```bash
dashboard ddstartup.setup -o json
```

Check service state:

```bash
dashboard ddstartup.status
```

Example status result:

```text
FIELD         VALUE
------------  -----
scope         user
service_name  developer-dashboard-startup.service
unit_path     ~/.config/systemd/user/developer-dashboard-startup.service
enabled       enabled
active        active
```

Read recent logs:

```bash
dashboard ddstartup.logs
```

Default logs output is a table that includes the scope, unit name, requested line count, and the returned journal content.

Read a shorter log window:

```bash
dashboard ddstartup.logs --lines 20
```

JSON log output:

```bash
dashboard ddstartup.logs -o json --lines 20
```

Remove the startup unit:

```bash
dashboard ddstartup.remove
```

Disable auto-start but keep the unit definition for later restore:

```bash
dashboard ddstartup.disable
```

JSON disable output:

```bash
dashboard ddstartup.disable -o json
```

Then uninstall the skill itself if you no longer want it:

```bash
dashboard skills uninstall ddstartup
```

## Browser Interface

This skill does not add a browser interface. It is a CLI-only operational skill.

## Practical Examples

Normal case, install DD startup for a user-managed home runtime:

```bash
dashboard skills install git@github.com:manif3station/ddstartup.git
```

That install path automatically provisions the startup unit.

Normal case, inspect whether the unit is enabled and active:

```bash
dashboard ddstartup.status
```

Normal case, script against the same command:

```bash
dashboard ddstartup.status -o json
```

Normal case, inspect the latest service output:

```bash
dashboard ddstartup.logs --lines 50
```

Normal case, temporarily disable and later restore startup:

```bash
dashboard ddstartup.disable
dashboard ddstartup.enable
```

Normal case, remove the managed startup before uninstalling the skill:

```bash
dashboard ddstartup.remove
dashboard skills uninstall ddstartup
```

## Edge Cases

- if `systemctl` is not available, setup and status commands fail with a clear error
- if `journalctl` is not available, logs fail with a clear error
- if the skill is installed on a non-systemd host, the install step fails because the current release only supports `systemctl` and `journalctl`
- if a non-root user needs a system unit, they must run setup with the privileges required by systemd and the target unit directory
- if root runs setup without flags, the skill defaults to system scope
- if a normal user runs setup without flags, the skill defaults to user scope

## Documentation

See:

- `docs/overview.md`
- `docs/usage.md`
- `docs/changes/2026-04-28-ddstartup-bootstrap.md`
- `docs/changes/2026-04-28-runtime-env-fix.md`
