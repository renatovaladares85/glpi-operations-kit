# Final Compliance Report - GLPI Install, Assets, and Routes (Linux)

This report consolidates the current compliance status for GLPI install/access behavior with `public` web root and Linux web engines (`nginx`, `apache`, `lighttpd`).

Baseline reference used for expected behavior:
- GLPI install documentation model with `public` document root and router-based rewrite flow.
- Installer compatibility expectation for environments that redirect to `/install/install.php`.

## Compliance Table

| Required | Implemented | Divergence | Fix | Severity |
|---|---|---|---|---|
| `public` as web root | Yes (`{{ glpi_install_dir }}/public` in all engine templates) | None | Keep enforced in templates and post-check | Low |
| Root route `/` reachable | Yes (automated `uri` checks) | None | Keep in app checks | Low |
| Installer route compatibility (`/install/install.php`) when installer is expected | Yes for Nginx (explicit compatibility rewrite to router); Apache/lighttpd covered by rewrite-if-not-file model | None in template logic | Keep check gated by installer link detection in root content | Medium |
| JS/CSS assets reachable | Yes (automated extraction of representative `.js/.css` paths and HTTP checks) | Limited sample scope (top 3 discovered assets) | Expand sample size if needed per customer QA profile | Medium |
| Sensitive paths blocked (`/config`, `/files`, `/vendor`) | Yes (explicit blocked-path checks) | None | Keep in post-check/apply checks | High |
| Arbitrary direct PHP outside router blocked | Yes (`/should-not-exist.php` must be blocked) | None | Keep enforced in checks | High |
| One engine per host (`WEB_SERVER_TYPE`) | Yes (secure-mode blocking / permissive warning with evidence) | None | Keep policy + evidence behavior | High |

## Engine Result Summary

| Engine | Status | Notes |
|---|---|---|
| nginx | Implemented and validated in code path | Includes explicit `/install/install.php` compatibility rewrite and direct PHP restriction. |
| apache | Implemented and validated in code path | Uses rewrite rules to route non-file requests to `index.php`. |
| lighttpd | Implemented and validated in code path | Uses `url.rewrite-if-not-file` to route to `index.php`. |

## Install Flow Verdict

- Verdict: **Compliant in code path after fix**.
- Redirect/install behavior now validated with automated checks:
  - root endpoint check;
  - conditional installer route check when installer path is referenced by the root page;
  - failure if installer path returns incompatible behavior.

## Asset Verdict

- Verdict: **Compliant with representative sampling**.
- Current automation discovers representative JS/CSS assets from page content and validates successful HTTP responses.

## Security Verdict

- Verdict: **Compliant for baseline hardening**.
- Sensitive non-public paths are expected to return deny/not-found, and arbitrary direct PHP path outside router is blocked.

## Prioritized Action List

### Critical
- None open in current implementation block.

### High
- Maintain one-engine enforcement in every mutable run and keep conflict evidence in permissive mode.

### Medium
- Expand asset sampling coverage for stricter customer acceptance tests (for example, validate module-specific assets when enabled).
- Add optional deep route matrix checks as a dedicated `audit` subcommand profile.

