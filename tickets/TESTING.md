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
  - Test count: `Files=4, Tests=86`
- Coverage test:
  - `docker compose -f ~/projects/skills/docker-compose.testing.yml run --rm perl-test bash -lc 'cd /workspace/skills/ddstartup && cover -delete && HARNESS_PERL_SWITCHES=-MDevel::Cover prove -lr t && cover -report text -select_re "^lib/" -coverage statement -coverage subroutine'`
  - Result: pass
  - Coverage: `100.0%` statement and `100.0%` subroutine for `lib/DDStartup/Manager.pm`
- Installed DD proof:
  - `dashboard skills install /home/mv/projects/skills/skills/ddstartup` with mocked `systemctl` and `journalctl`
  - Result: pass, install auto-provisioned `developer-dashboard-startup.service`
  - `dashboard ddstartup.status`
  - Result: pass, returned default table output with `enabled` and `active`
  - `dashboard ddstartup.status -o json`
  - Result: pass, returned JSON
  - `dashboard ddstartup.logs --lines 5`
  - Result: pass, returned default table output with mocked journal output
  - `dashboard ddstartup.logs -o json --lines 5`
  - Result: pass, returned JSON
  - `dashboard ddstartup.disable`
  - Result: pass, returned default table output and disabled the unit without deleting it
  - `dashboard ddstartup.enable`
  - Result: pass, returned default table output and restored the unit
  - `dashboard ddstartup.remove`
  - Result: pass, returned default table output, removed the unit file, and reloaded the daemon
- Cleanup:
  - `docker compose -f ~/projects/skills/docker-compose.testing.yml run --rm perl-test bash -lc 'rm -rf /workspace/skills/ddstartup/cover_db'`
  - Result: pass
