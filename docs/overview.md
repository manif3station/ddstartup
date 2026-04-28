# ddstartup Overview

## Summary

`ddstartup` is a systemd-oriented DD skill for wiring `dashboard restart` into startup management.

## User Value

It helps users keep DD alive across reboots without remembering a manual restart step.

## Current Features

- writes a user or system systemd unit for `dashboard restart`
- auto-provisions that unit during `dashboard skills install` through the skill `Makefile` install target
- restores the unit through `dashboard ddstartup.enable`
- disables startup through `dashboard ddstartup.disable`
- enables and starts that unit through `systemctl`
- reports unit state through `systemctl`
- reports unit logs through `journalctl`
- disables and removes the unit again
