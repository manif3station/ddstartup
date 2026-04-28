# 2026-04-28 Install Skip On Unsupported Hosts

## Summary

`ddstartup` now installs cleanly on unsupported hosts such as macOS by skipping its Makefile auto-setup step instead of aborting the skill install.

## Problem

The install hook always tried to auto-provision a systemd unit. On unsupported hosts, that could break `dashboard skills install ddstartup` even though the host was never capable of running `systemctl` in the first place.

## Fix

- detect whether `systemctl` is actually runnable before auto-setup
- return a skipped result with reason `unsupported_host` when install-time auto-setup is not supported
- keep explicit `ddstartup.setup` and `ddstartup.enable` strict so they still fail clearly when the host cannot run `systemctl`

## Verification

- Docker functional tests passed
- Docker coverage passed at `100.0%` statement and `100.0%` subroutine for `lib/DDStartup/Manager.pm`
- macOS proof passed through `ssh macdev`:
  - `make install`
  - `dashboard skills install /tmp/ddstartup-skill/ddstartup`
  - no `~/.config/systemd/user/developer-dashboard-startup.service` was created
