# Authentication, SSO, and Azure/Entra ID Guide (EN)

This guide is application-level only. SSO/SAML/OIDC is configured directly in GLPI and in the identity provider. The kit does not orchestrate IdP settings through `glpictl`.

## Scope

- Supported by this guide: manual SSO setup checklist in GLPI + IdP.
- Out of scope for scripts: automatic SSO provisioning, plugin wiring, claims mapping, JIT rule provisioning.

## Recommended sequence

1. Keep local admin access enabled and tested in GLPI.
2. Confirm the final public GLPI URL (`https://<GLPI_DOMAIN>` when TLS is enabled).
3. Install/enable the required authentication plugin in GLPI (if applicable).
4. Configure IdP metadata and endpoints in GLPI.
5. Configure claim mappings and JIT/group/profile mappings in GLPI.
6. Run pilot sign-in tests.
7. Validate local fallback login remains available.
8. Promote to broader user groups.

## Azure/Entra ID SAML checklist

Coordinate with IAM:

| Item | Expected value |
|---|---|
| Enterprise application name | Clear name, e.g. `GLPI - Production`. |
| Identifier / Entity ID | GLPI SP entity ID defined in GLPI plugin. |
| Reply URL / ACS URL | GLPI ACS URL configured in plugin. |
| Sign-on URL | Public GLPI URL. |
| Logout URL | GLPI logout URL configured in plugin (if used). |
| NameID format | Usually `emailAddress` unless IAM requires another format. |
| IdP public certificate | Public Entra ID certificate (no private key). |
| Groups | Group IDs/names authorized for GLPI. |

Typical claim mapping example:

| GLPI field | Common Entra ID source |
|---|---|
| email | `user.mail` |
| username | `user.userprincipalname` |
| firstname | `user.givenname` |
| lastname | `user.surname` |
| groups | `user.groups` |

## Security notes

- Do not commit IdP secrets, private keys, tokens, or sensitive exports.
- Keep plugin and IdP changes in operational evidence/checklists outside source control when required.
- If needed, keep legacy `AUTH_*` / `SSO_*` keys in old `.env` files; execution flows ignore them.

## Validation checklist

- GLPI URL is reachable with expected protocol (`http` or `https`).
- SSO login works for pilot users.
- Local admin fallback works.
- JIT/group/profile mapping behaves as expected.
- Logout flow is validated (if enabled).
