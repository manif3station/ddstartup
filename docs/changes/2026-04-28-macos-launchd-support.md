# 2026-04-28 macOS launchd Support

## Summary

`ddstartup` now supports both systemd hosts and macOS hosts.

## What Changed

- systemd hosts still use `.service` units, `systemctl`, and `journalctl`
- macOS hosts now use launchd `.plist` files and `launchctl`
- macOS startup logs are read from dedicated files under `~/Library/Logs/`
- macOS setup reports whether immediate activation was loaded or deferred

## macOS Paths

- user plist: `~/Library/LaunchAgents/developer-dashboard-startup.plist`
- system plist: `/Library/LaunchDaemons/developer-dashboard-startup.plist`
- user stdout log: `~/Library/Logs/developer-dashboard-startup.log`
- user stderr log: `~/Library/Logs/developer-dashboard-startup.err.log`

## Status Meaning

- `enabled` means the launchd label is enabled
- `active=active` means the current session can prove the job is loaded
- `active=configured` means the job is installed and enabled but the current session did not prove an immediately loaded job
- `activation=deferred` from setup means the plist was written and enabled but immediate activation was deferred in the current session

## Verification

- Docker functional tests passed
- Docker coverage passed at `100.0%` statement and `100.0%` subroutine for `lib/DDStartup/Manager.pm`
- live systemd proof passed on Linux
- live macOS proof passed through `ssh macdev`
