# Testing

## Policy

- tests run only inside Docker
- the shared test container definition lives at the workspace root
- this skill keeps its test files in `t/`

## Commands

```bash
docker compose -f ~/projects/skills/docker-compose.testing.yml run --rm perl-test bash -lc 'cd /workspace/skills/ddstartup && prove -lr t'
docker compose -f ~/projects/skills/docker-compose.testing.yml run --rm perl-test bash -lc 'cd /workspace/skills/ddstartup && cover -delete && HARNESS_PERL_SWITCHES=-MDevel::Cover prove -lr t && cover -report text -select_re "^lib/" -coverage statement -coverage subroutine'
```

## Latest Verification

- Date: 2026-04-29
- Functional test:
  - `docker compose -f ~/projects/skills/docker-compose.testing.yml run --rm perl-test bash -lc 'cd /workspace/skills/ddstartup && prove -lr t'`
  - Result: pass
  - Test count: `Files=4, Tests=150`
- Coverage test:
  - `docker compose -f ~/projects/skills/docker-compose.testing.yml run --rm perl-test bash -lc 'cd /workspace/skills/ddstartup && cover -delete && HARNESS_PERL_SWITCHES=-MDevel::Cover prove -lr t && cover -report text -select_re "^lib/" -coverage statement -coverage subroutine'`
  - Result: pass
  - Coverage: `100.0%` statement and `100.0%` subroutine for `lib/DDStartup/Manager.pm`
- Installed DD proof:
  - `dashboard ddstartup.setup`
  - Result: pass, rewrote `~/.config/systemd/user/developer-dashboard-startup.service` with `Environment=PERL5LIB=...`
  - `dashboard ddstartup.status`
  - Result: pass, returned default table output with `enabled` and `active`
  - `systemctl --user status developer-dashboard-startup.service --no-pager`
  - Result: pass, unit reported `Active: active (exited)` and `status=0/SUCCESS`
  - `journalctl --user -u developer-dashboard-startup.service --no-pager -n 20`
  - Result: pass, latest successful startup showed `dashboard restart` completing under systemd
- macOS proof through `ssh macdev`:
  - `zsh -lic 'dashboard ddstartup.setup'`
  - Result: pass, wrote `~/Library/LaunchAgents/developer-dashboard-startup.plist` with `ProgramArguments` pointing to the active login-shell Perl and `dashboard`, plus derived `PERL5LIB` entries
  - manual plist command proof:
  - `HOME=$HOME PERL5LIB=<plist-perl5lib> <plist-perl> <plist-dashboard> restart`
  - Result: pass, returned `rc=0` with no stderr
  - `zsh -lic 'dashboard ddstartup.status'`
  - Result: pass, returned `enabled` and `active=configured`
  - `zsh -lic 'dashboard ddstartup.logs --lines 5'`
  - Result: pass, returned the default logs table; the log payload was empty in the deferred SSH-session case
  - `zsh -lic 'dashboard ddstartup.disable'`
  - Result: pass
  - `zsh -lic 'dashboard ddstartup.remove'`
  - Result: pass, removed `~/Library/LaunchAgents/developer-dashboard-startup.plist`
- Cleanup:
  - `docker compose -f ~/projects/skills/docker-compose.testing.yml run --rm perl-test bash -lc 'rm -rf /workspace/skills/ddstartup/cover_db'`
  - Result: pass
