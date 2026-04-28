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
  - Test count: `Files=4, Tests=92`
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
- macOS unsupported-host proof:
  - `ssh macdev 'zsh -lic "cd /tmp/ddstartup-skill/ddstartup && make install"'`
  - Result: pass, install-time auto-setup exited cleanly without aborting on macOS
  - `ssh macdev 'zsh -lic "dashboard skills install /tmp/ddstartup-skill/ddstartup"'`
  - Result: pass, skill installed successfully on macOS
  - `ssh macdev 'zsh -lic "test -e ~/.config/systemd/user/developer-dashboard-startup.service; echo unit_exists=$?"'`
  - Result: pass, returned `unit_exists=0`, proving no unsupported systemd unit was created
- Cleanup:
  - `docker compose -f ~/projects/skills/docker-compose.testing.yml run --rm perl-test bash -lc 'rm -rf /workspace/skills/ddstartup/cover_db'`
  - Result: pass
