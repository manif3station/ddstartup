# ddstartup Overview

## Summary

`ddstartup` is a cross-platform DD skill for wiring `dashboard restart` into native startup management.

## User Value

It helps users keep DD alive across reboots without remembering a manual restart step.

## Current Features

- writes a user or system systemd unit for `dashboard restart`
- writes a user or system launchd plist for `dashboard restart` on macOS
- auto-provisions that startup definition during `dashboard skills install` through the skill `Makefile` install target
- restores the unit through `dashboard ddstartup.enable`
- disables startup through `dashboard ddstartup.disable`
- enables and starts that unit through `systemctl` on Linux
- enables and loads that plist through `launchctl` on macOS
- reports unit state through `systemctl` on Linux
- reports launch agent state through `launchctl` on macOS
- reports unit logs through `journalctl` on Linux
- reports launch-agent startup logs through dedicated files on macOS
- renders human-readable tables by default and `-o json` on demand
- disables and removes the unit again
