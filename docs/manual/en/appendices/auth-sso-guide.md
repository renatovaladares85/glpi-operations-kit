# Authentication, SSO, and Azure/Entra ID Guide (EN)

This guide covers the `auth` domain and the `AUTH_*` / `SSO_*` keys. The goal is to prepare and validate authentication without breaking local login, removing the local admin user, or installing plugins automatically.

## What the kit does

| Action | Behavior |
|---|---|
| `auth check` | Validates `local|ldap|saml|oidc`, public URL, HTTPS when applicable, detectable SAML plugin, and evidence without changing the system. |
| `auth prepare` | Derives missing SAML URLs, prepares runtime/evidence, and avoids destructive changes. |
| `auth apply` | Creates domain backup and applies only safe state/evidence. It does not write plugin configuration directly into the DB. |
| `auth post-check` | Validates final consistency, sensitive-file exposure, and evidence. |
| `auth rollback` | Restores the local `auth` domain snapshot. |

## Authentication modes

| Mode | When to use | Notes |
|---|---|---|
| `AUTH_MODE=local` | No SSO/LDAP/OIDC. | Keeps current behavior and does not remove local/admin login. |
| `AUTH_MODE=ldap` | Approved LDAP directory. | Kit prepares/validates the contract; bind password stays in `.runtime/<env>/secrets.yml`. |
| `AUTH_MODE=saml` | SAML SSO, such as Azure/Entra ID. | Requires public HTTPS URL when enabled. SAML plugin is installed manually from Marketplace. |
| `AUTH_MODE=oidc` | Architecture-approved OIDC. | Kit does not install paid plugins and does not implement SCIM. Client secret stays in runtime secrets. |

## Azure/Entra ID SAML checklist

Ask or confirm with IAM:

| Item | Expected value |
|---|---|
| Enterprise application name | Clear name, e.g. `GLPI - Production`. |
| Identifier / Entity ID | `https://glpi.company.com` or `AUTH_SAML_ENTITY_ID`. |
| Reply URL / ACS URL | `https://glpi.company.com/front/saml.php` or `AUTH_SAML_ACS_URL`. |
| Sign-on URL | `https://glpi.company.com`. |
| Logout URL | `https://glpi.company.com/front/saml_logout.php` or `AUTH_SAML_LOGOUT_URL`. |
| NameID Format | `urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress`. |
| IdP public certificate | Public Entra ID X.509 certificate, without private key. |
| Groups | Group IDs or names allowed to use GLPI. |

Recommended claims:

| GLPI claim | Typical Entra ID source |
|---|---|
| `email` | `user.mail` |
| `username` | `user.userprincipalname` |
| `firstname` | `user.givenname` |
| `lastname` | `user.surname` |
| `groups` | `user.groups` |

## Public `.env` keys

```env
AUTH_MODE=saml
AUTH_EXTERNAL_ENABLED=true
AUTH_SAML_ENABLED=true
AUTH_OIDC_ENABLED=false
AUTH_LDAP_ENABLED=false
SSO_PROVIDER=Azure Entra ID
SSO_PROTOCOL=saml
SSO_PUBLIC_URL=https://glpi.company.com
SSO_REQUIRE_PUBLIC_URL=true
AUTH_SAML_PLUGIN_EXPECTED=true
AUTH_SAML_PLUGIN_NAME=saml
AUTH_SAML_ENTITY_ID=
AUTH_SAML_ACS_URL=
AUTH_SAML_LOGOUT_URL=
AUTH_SAML_NAMEID_FORMAT=urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress
AUTH_SAML_IDP_ENTITY_ID=https://sts.windows.net/11111111-2222-3333-4444-555555555555/
AUTH_SAML_IDP_SSO_URL=https://login.microsoftonline.com/11111111-2222-3333-4444-555555555555/saml2
AUTH_SAML_IDP_SLO_URL=
AUTH_SAML_CLAIM_EMAIL=email
AUTH_SAML_CLAIM_USERNAME=username
AUTH_SAML_CLAIM_FIRSTNAME=firstname
AUTH_SAML_CLAIM_LASTNAME=lastname
AUTH_SAML_CLAIM_GROUPS=groups
AUTH_JIT_ENABLED=true
AUTH_DEFAULT_PROFILE=Self-Service
AUTH_GROUP_ADMIN=GLPI-Admins
AUTH_GROUP_TECHNICIAN=GLPI-Technicians
AUTH_GROUP_USER=GLPI-Users
SECURITY_SSO_ENABLED=false
```

Leave `AUTH_SAML_ENTITY_ID`, `AUTH_SAML_ACS_URL`, and `AUTH_SAML_LOGOUT_URL` empty when `auth prepare` should derive them from `SSO_PUBLIC_URL`.

## Runtime secrets

Create or update `.runtime/<environment>/secrets.yml` with restricted permissions. Filled example with non-real values:

```yaml
auth_saml_x509_certificate: "MIIC...EXAMPLE_PUBLIC_CERT...AB"
ldap_bind_password: "kit-demo-Ldap8@vT2pQ5"
oidc_client_secret: "kit-demo-Oidc6#nR4xW9"
```

Do not put SAML private keys, client secrets, LDAP passwords, tokens, or private certificates in `config/<environment>.env`, evidence, logs, or Git.

## SAML plugin

The kit does not install the SAML plugin. The operator must install it manually through GLPI Marketplace or the approved procedure. `auth check` only tries to detect the plugin by `AUTH_SAML_PLUGIN_NAME`.

Manual GLPI checklist:

1. Confirm local login remains enabled.
2. Confirm local admin remains accessible.
3. Install SAML plugin from Marketplace.
4. Configure Entity ID, ACS, Logout, IdP Entity ID, SSO URL, and IdP public certificate.
5. Configure claims and group mappings.
6. Test SSO with a pilot user.
7. Test fallback with a local user.
8. Only then set `SECURITY_SSO_ENABLED=true` if policy requires it.

## Validation

```bash
./scripts/glpictl.sh staging auth check
./scripts/glpictl.sh staging auth prepare
./scripts/glpictl.sh staging auth apply
./scripts/glpictl.sh staging auth post-check
```

Evidence is stored under `.runtime/<environment>/evidence/auth/` and must not contain secrets.

## Rollback

```bash
./scripts/glpictl.sh staging auth rollback
```

The `auth` domain rollback restores local runtime/evidence/state for the domain. Manual changes made inside GLPI or in IAM must follow the owning team's operational rollback checklist because the kit does not write unsafe plugin configuration directly to the plugin database.
