# 2026-04-28 ddstartup bootstrap

## Summary

Created the first `ddstartup` release for systemd-managed DD startup.

## What Changed

- added setup, status, logs, and remove commands
- added enable and disable commands
- added a Makefile install target so skill installation auto-provisions the startup unit
- added user-scope and system-scope unit generation
- added Docker verification with mocked `systemctl` and `journalctl`

## Why

DD needs a repeatable startup path so users do not have to remember a manual `dashboard restart` after every reboot.
