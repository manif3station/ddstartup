# 2026-04-29 dashboard layout runtime fix

## Summary

`ddstartup` now derives Perl library paths from the installed `dashboard` layout before it writes a systemd unit or a macOS launchd plist.

## Why

Some installs run `dashboard` from a path like `~/perl5/bin/dashboard` while the required DD modules live under sibling directories such as `~/perl5/lib/perl5`. In those cases a startup manager cannot rely on the interactive shell to provide `PERL5LIB`.

## What changed

- `ddstartup` now checks the installed `dashboard` path and prepends existing sibling library directories such as `../lib/perl5` and `../lib`
- `ddstartup` now runs `dashboard` through the active Perl interpreter captured at setup time instead of relying on `#!/usr/bin/env perl` at boot
- the derived paths are written into both systemd `Environment=PERL5LIB=...` lines and macOS launchd `EnvironmentVariables`
- regression coverage now proves the generated startup definition for a dashboard tree that uses `bin/`, `lib/`, and `lib/perl5/`

## Result

Generated startup definitions can restart DD on hosts whose installed dashboard runtime depends on dashboard-adjacent Perl library directories.
