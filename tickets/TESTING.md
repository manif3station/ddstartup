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

- Date: 2026-04-28
- Functional test:
  - `docker compose -f ~/projects/skills/docker-compose.testing.yml run --rm perl-test bash -lc 'cd /workspace/skills/ddstartup && prove -lr t'`
  - Result: pass
  - Test count: `Files=4, Tests=144`
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
  - `~/.developer-dashboard/skills/ddstartup/cli/setup`
  - Result: pass, wrote `~/Library/LaunchAgents/developer-dashboard-startup.plist` and returned `activation=deferred` in the SSH session
  - `~/.developer-dashboard/skills/ddstartup/cli/status`
  - Result: pass, returned `enabled` and `active=configured`
  - `~/.developer-dashboard/skills/ddstartup/cli/logs --lines 2`
  - Result: pass, returned the trailing lines from `~/Library/Logs/developer-dashboard-startup.log` and `.err.log`
  - `~/.developer-dashboard/skills/ddstartup/cli/disable`
  - Result: pass
  - `~/.developer-dashboard/skills/ddstartup/cli/remove`
  - Result: pass, removed `~/Library/LaunchAgents/developer-dashboard-startup.plist`
- Cleanup:
  - `docker compose -f ~/projects/skills/docker-compose.testing.yml run --rm perl-test bash -lc 'rm -rf /workspace/skills/ddstartup/cover_db'`
  - Result: pass
