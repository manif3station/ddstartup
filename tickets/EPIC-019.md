# EPIC-019

## Title

Harden `ddstartup` install-time auto setup.

## Outcome

Allow `ddstartup` to install on unsupported hosts by skipping its Makefile auto-setup path when the host cannot run `systemctl`, while keeping the explicit management commands strict.

## Tickets

- `DD-046` Skip install-time auto-setup on unsupported hosts
