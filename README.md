# ddstartup

## Description

`ddstartup` is a Developer Dashboard skill that installs and manages native startup definitions for Developer Dashboard so `dashboard restart` can be run automatically when the machine boots.

## Value

It gives the user a repeatable way to:

- install DD startup at user scope when they manage DD in their own home runtime
- install DD startup at system scope when root manages DD for the host
- use `systemctl` and `journalctl` on systemd hosts
- use `launchctl` and launch agent or daemon plists on macOS
- inspect macOS startup logs through dedicated files under `~/Library/Logs/`
- remove the startup wiring cleanly when it is no longer wanted

## Problem It Solves

Without a managed startup unit, users have to remember to bring DD back with `dashboard restart` after reboot. That is easy to forget and breaks the expectation that DD will already be alive when the user opens a shell or browser.

## What It Does To Solve It

`ddstartup` writes the native startup definition for the current host:

- on systemd hosts it writes a `.service` unit and manages it through `systemctl` and `journalctl`
- on macOS it writes a launchd `.plist`, manages it through `launchctl`, and reads dedicated startup logs from `~/Library/Logs/`

It also derives and preserves the Perl runtime library paths needed by the installed `dashboard` executable, including dashboard-adjacent directories such as sibling `lib/perl5`, and it runs `dashboard` through the active Perl interpreter captured at setup time so the generated startup definition can work outside an interactive shell.

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

When this skill is installed through `dashboard skills install`, its `Makefile` install target automatically provisions startup on supported hosts:

- systemd hosts get a managed `.service` unit
- macOS hosts get a managed launchd `.plist`

In non-GUI macOS sessions such as an SSH shell, launchd may defer immediate loading even though the plist is installed and enabled. In that case `ddstartup` reports `activation=deferred` during setup and `active=configured` in status.

## License

`ddstartup` is released under the MIT License.

See [LICENSE](LICENSE).

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
platform           systemd
scope              user
service_name       developer-dashboard-startup.service
unit_path          ~/.config/systemd/user/developer-dashboard-startup.service
dashboard          /usr/bin/dashboard
working_directory  ~
wanted_by          default.target
```

Example macOS setup result from a non-GUI shell:

```text
FIELD              VALUE
-----------------  -----
platform           macos
scope              user
service_name       developer-dashboard-startup
unit_path          ~/Library/LaunchAgents/developer-dashboard-startup.plist
dashboard          /usr/bin/dashboard
working_directory  ~
wanted_by          launchd
domain             user/<uid>
log_path           ~/Library/Logs/developer-dashboard-startup.log
activation         deferred
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
platform      systemd
scope         user
service_name  developer-dashboard-startup.service
unit_path     ~/.config/systemd/user/developer-dashboard-startup.service
enabled       enabled
active        active
```

Example macOS status result from an SSH shell:

```text
FIELD         VALUE
------------  -----
platform      macos
scope         user
service_name  developer-dashboard-startup
unit_path     ~/Library/LaunchAgents/developer-dashboard-startup.plist
domain        user/<uid>
log_path      ~/Library/Logs/developer-dashboard-startup.log
enabled       enabled
active        configured
```

Read recent logs:

```bash
dashboard ddstartup.logs
```

Default logs output is a table that includes the platform, scope, service name, requested line count, and the returned log content.

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

Normal case, install DD startup for a user-managed home runtime on Linux:

```bash
dashboard skills install git@github.com:manif3station/ddstartup.git
```

That install path automatically provisions the startup unit.

Normal case, install DD startup for a macOS user runtime:

```bash
dashboard skills install git@github.com:manif3station/ddstartup.git
```

That install path writes `~/Library/LaunchAgents/developer-dashboard-startup.plist`.

Normal case, inspect whether the unit is enabled and active:

```bash
dashboard ddstartup.status
```

Normal case, script against the same command:

```bash
dashboard ddstartup.status -o json
```

Normal case, inspect the latest service output on systemd:

```bash
dashboard ddstartup.logs --lines 50
```

Normal case, inspect the latest startup log file on macOS through the same command:

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

- if `systemctl` is not available on a systemd-targeted host, setup and status commands fail with a clear error
- if `journalctl` is not available on a systemd-targeted host, logs fail with a clear error
- if `launchctl` can enable the launch agent but the current macOS shell cannot load it immediately, setup still writes and enables the plist and reports `activation=deferred`
- if macOS status is read from a shell that cannot show the launchd job as live, `active` is reported as `configured` instead of `active`
- if a non-root user needs a system unit, they must run setup with the privileges required by systemd and the target unit directory
- if root runs setup without flags, the skill defaults to system scope
- if a normal user runs setup without flags, the skill defaults to user scope

## Documentation

See:

- `docs/overview.md`
- `docs/usage.md`
- `docs/changes/2026-04-28-macos-launchd-support.md`
- `docs/changes/2026-04-28-ddstartup-bootstrap.md`
- `docs/changes/2026-04-28-runtime-env-fix.md`
- `docs/changes/2026-04-28-install-skip-on-unsupported-hosts.md`
