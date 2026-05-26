# Guia de Autenticação, SSO e Azure/Entra ID (PT-BR)

Este guia cobre o domínio `auth` do `glpictl` e o preenchimento das chaves `AUTH_*` e `SSO_*`. O objetivo é preparar e validar autenticação sem quebrar login local, sem remover o usuário admin local e sem instalar plugin automaticamente.

## O que o kit faz

| Ação | Comportamento |
|---|---|
| `auth check` | Valida contrato `local|ldap|saml|oidc`, URL pública, HTTPS quando aplicável, plugin SAML detectável e evidências sem alterar sistema. |
| `auth prepare` | Deriva URLs SAML quando faltam, prepara runtime/evidências e não faz alteração destrutiva. |
| `auth apply` | Gera backup de domínio e aplica apenas estado/evidência seguro. Não configura plugin diretamente no banco. |
| `auth post-check` | Valida consistência final, exposição de arquivos sensíveis e evidências. |
| `auth rollback` | Restaura snapshot local do domínio `auth`. |

## Modos de autenticação

| Modo | Quando usar | Observações |
|---|---|---|
| `AUTH_MODE=local` | Sem SSO/LDAP/OIDC. | Mantém comportamento atual e não remove login local/admin. |
| `AUTH_MODE=ldap` | Diretório LDAP aprovado. | O kit prepara/valida contrato; senha bind fica em `.runtime/<env>/secrets.yml`. |
| `AUTH_MODE=saml` | SSO SAML, como Azure/Entra ID. | Exige URL pública HTTPS quando habilitado. Plugin SAML é instalado manualmente via Marketplace. |
| `AUTH_MODE=oidc` | OIDC aprovado pela arquitetura. | O kit não instala plugin pago nem implementa SCIM. Segredo client fica em runtime secrets. |

## Checklist para Azure/Entra ID SAML

Solicite ou confirme com a equipe IAM:

| Item | Valor esperado |
|---|---|
| Nome da aplicação enterprise | Nome claro, por exemplo `GLPI - Production`. |
| Identifier / Entity ID | `https://glpi.company.com` ou valor de `AUTH_SAML_ENTITY_ID`. |
| Reply URL / ACS URL | `https://glpi.company.com/front/saml.php` ou valor de `AUTH_SAML_ACS_URL`. |
| Sign-on URL | `https://glpi.company.com`. |
| Logout URL | `https://glpi.company.com/front/saml_logout.php` ou valor de `AUTH_SAML_LOGOUT_URL`. |
| NameID Format | `urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress`. |
| Certificado público do IdP | Certificado X.509 público do Entra ID, sem chave privada. |
| Groups | IDs ou nomes de grupos liberados para GLPI. |

Claims recomendados:

| Claim no GLPI | Origem Entra ID típica |
|---|---|
| `email` | `user.mail` |
| `username` | `user.userprincipalname` |
| `firstname` | `user.givenname` |
| `lastname` | `user.surname` |
| `groups` | `user.groups` |

## Chaves públicas no `.env`

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
AUTH_SAML_IDP_ENTITY_ID=https://sts.windows.net/<tenant-id>/
AUTH_SAML_IDP_SSO_URL=https://login.microsoftonline.com/<tenant-id>/saml2
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

Deixe `AUTH_SAML_ENTITY_ID`, `AUTH_SAML_ACS_URL` e `AUTH_SAML_LOGOUT_URL` vazios quando quiser que `auth prepare` derive automaticamente a partir de `SSO_PUBLIC_URL`.

## Segredos em runtime

Crie ou atualize `.runtime/<environment>/secrets.yml` com permissão restrita. Exemplo estrutural, sem valores reais:

```yaml
auth_saml_x509_certificate: "<paste-idp-public-x509-certificate>"
ldap_bind_password: "<ldap-bind-password-if-used>"
oidc_client_secret: "<oidc-client-secret-if-used>"
```

Não coloque chave privada SAML, client secret, senha LDAP, token ou certificado privado em `config/<environment>.env`, evidência, log ou Git.

## Plugin SAML

O kit não instala plugin SAML. O operador deve instalar manualmente via Marketplace do GLPI ou procedimento aprovado. O `auth check` apenas tenta detectar o plugin pelo nome configurado em `AUTH_SAML_PLUGIN_NAME`.

Checklist manual no GLPI:

1. Confirmar que login local continua habilitado.
2. Confirmar que usuário admin local continua acessível.
3. Instalar plugin SAML pelo Marketplace.
4. Configurar Entity ID, ACS, Logout, IdP Entity ID, SSO URL e certificado público do IdP.
5. Configurar claims e mapeamento de grupos.
6. Testar login SSO com usuário piloto.
7. Testar fallback com usuário local.
8. Só então ajustar `SECURITY_SSO_ENABLED=true`, se a política exigir.

## Validação

```bash
./scripts/glpictl.sh staging auth check
./scripts/glpictl.sh staging auth prepare
./scripts/glpictl.sh staging auth apply
./scripts/glpictl.sh staging auth post-check
```

As evidências ficam em `.runtime/<environment>/evidence/auth/`. Elas não devem conter segredos.

## Rollback

```bash
./scripts/glpictl.sh staging auth rollback
```

Rollback do domínio `auth` restaura runtime/evidências/estado local do domínio. Alterações manuais feitas dentro do GLPI ou no provedor IAM devem seguir checklist operacional da equipe responsável, porque o kit não escreve configuração insegura direto no banco do plugin.
