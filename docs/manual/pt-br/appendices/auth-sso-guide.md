# Guia de Autenticação, SSO e Azure/Entra ID (PT-BR)

Este guia é somente de aplicação. SSO/SAML/OIDC é configurado diretamente no GLPI e no provedor de identidade. O kit não orquestra configurações de IdP via `glpictl`.

## Escopo

- Coberto por este guia: checklist manual de configuração de SSO no GLPI + IdP.
- Fora do escopo dos scripts: provisionamento automático de SSO, configuração de plugin, mapeamento de claims, provisionamento de regras JIT.

## Sequência recomendada

1. Manter acesso de admin local habilitado e testado no GLPI.
2. Confirmar a URL pública final do GLPI (`https://<GLPI_DOMAIN>` quando TLS estiver habilitado).
3. Instalar/habilitar no GLPI o plugin de autenticação necessário (se aplicável).
4. Configurar metadados e endpoints do IdP no GLPI.
5. Configurar mapeamento de claims e regras de JIT/grupo/perfil no GLPI.
6. Executar testes piloto de login.
7. Validar fallback de login local.
8. Liberar para grupos maiores.

## Checklist Azure/Entra ID SAML

Alinhar com IAM:

| Item | Valor esperado |
|---|---|
| Nome da aplicação enterprise | Nome claro, ex.: `GLPI - Production`. |
| Identifier / Entity ID | Entity ID do SP definido no plugin do GLPI. |
| Reply URL / ACS URL | URL ACS do GLPI configurada no plugin. |
| Sign-on URL | URL pública do GLPI. |
| Logout URL | URL de logout configurada no plugin (se usada). |
| Formato NameID | Normalmente `emailAddress`, salvo exigência IAM. |
| Certificado público do IdP | Certificado público Entra ID (sem chave privada). |
| Groups | IDs/nomes de grupos autorizados no GLPI. |

Exemplo típico de mapeamento de claims:

| Campo GLPI | Origem comum no Entra ID |
|---|---|
| email | `user.mail` |
| username | `user.userprincipalname` |
| firstname | `user.givenname` |
| lastname | `user.surname` |
| groups | `user.groups` |

## Notas de segurança

- Não commitar segredos de IdP, chaves privadas, tokens ou exportações sensíveis.
- Registrar mudanças de plugin e IdP em evidências/checklists operacionais fora do versionamento quando necessário.
- Se necessário, mantenha chaves legadas `AUTH_*` / `SSO_*` em `.env` antigo; os fluxos de execução ignoram essas chaves.

## Checklist de validação

- URL do GLPI acessível com o protocolo esperado (`http` ou `https`).
- Login SSO funcionando para usuários piloto.
- Fallback de admin local funcionando.
- Mapeamento JIT/grupo/perfil conforme esperado.
- Fluxo de logout validado (se habilitado).
