# 07 - Plugins and Marketplace (Manual Flow)

Plugin lifecycle is manual in the current baseline.

Operational rule:

- do not expect automated plugin installation from repository scripts;
- use GLPI Marketplace or a manual process defined by local policy;
- keep local admin access available during changes.

Safe flow:

1. run backup before plugin change;
2. install/update one plugin at a time;
3. validate login and critical workflows;
4. document what changed.

For authentication plugins, repository `auth` workflows validate and prepare runtime contracts, but do not auto-install plugin packages.

Common error and quick action:

- error: plugin update breaks login
- action: use local admin fallback, rollback plugin change, re-validate auth flow

Go next:

- [Authentication, SSO, and Azure/Entra ID Guide](../appendices/auth-sso-guide.md)
- [Troubleshooting Matrix](../appendices/troubleshooting-matrix.md)
