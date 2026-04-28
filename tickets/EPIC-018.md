# EPIC-018

## Title

Fix `ddstartup` runtime environment in systemd units.

## Outcome

Make the generated unit preserve the Perl library environment that the installed `dashboard` entrypoint needs under systemd.

## Tickets

- `DD-045` Persist `PERL5LIB` into generated units
