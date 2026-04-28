# 2026-04-28 Runtime Environment Fix

## Summary

`ddstartup` now writes `PERL5LIB` into the generated systemd unit so `dashboard restart` can start correctly under systemd.

## Problem

`dashboard ddstartup.setup` could create a valid-looking unit file that still failed at boot or manual start time because the `dashboard` executable depended on Perl library paths that were available in an interactive shell but not present in the systemd service environment.

## Fix

- preserve `PERL5LIB` when it is already set
- fall back to the current Perl `@INC` when `PERL5LIB` is unset during `dashboard ddstartup.setup`
- write that runtime path into the generated unit as `Environment=PERL5LIB=...`

## Verification

- Docker functional tests passed
- Docker coverage passed at `100.0%` statement and `100.0%` subroutine for `lib/DDStartup/Manager.pm`
- installed-host proof passed:
  - `dashboard ddstartup.setup`
  - `dashboard ddstartup.status`
  - `systemctl --user status developer-dashboard-startup.service --no-pager`

## Result

The managed user unit now reports `active` instead of `failed` when the DD runtime depends on non-system Perl library paths.
