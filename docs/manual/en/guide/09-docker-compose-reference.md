# 09 - Docker/Compose Reference Track (Separated)

This chapter is intentionally separate from the traditional Linux operational flow.

Current phase scope:

- Linux traditional stack is the primary operational baseline;
- Docker/Compose remains separate from the main deployment;
- repository-native Docker/Compose automation covers only the post-deploy Mailpit service through the `email` domain.

How to use this chapter:

1. treat Docker/Compose as an alternative track;
2. do not mix Docker instructions with Linux traditional deployment steps;
3. keep production decisions aligned with local architecture and policy.

Post-deploy Mailpit:

```bash
./scripts/glpictl.sh <environment> email check mailpit
./scripts/glpictl.sh <environment> email prepare mailpit
./scripts/glpictl.sh <environment> email install mailpit
./scripts/glpictl.sh <environment> email post-check mailpit
```

The command requires Docker/Compose to already be installed on the app host, validates port conflicts before changing anything, and exposes the UI at `EMAIL_MAILPIT_UI_PATH` using HTTP or HTTPS according to `TLS_MODE`.

Go next:

- [03 - Deploy on Linux](03-deploy-linux-traditional.md)
- [Implementation Plan](../../../implementation-plan.md)
