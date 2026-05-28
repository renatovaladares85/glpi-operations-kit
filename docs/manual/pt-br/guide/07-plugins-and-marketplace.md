# 07 - Plugins e Marketplace (Fluxo Manual)

O ciclo de vida de plugins é manual no baseline atual.

Regra operacional:

- não esperar instalação automática de plugin pelos scripts do repositório;
- usar Marketplace do GLPI ou processo manual definido pela política local;
- manter acesso de admin local disponível durante mudanças.

Fluxo seguro:

1. executar backup antes de alterar plugin;
2. instalar/atualizar um plugin por vez;
3. validar login e fluxos críticos;
4. documentar o que foi alterado.

Para plugins de autenticação, os fluxos `auth` do repositório validam e preparam contratos runtime, mas não instalam pacotes de plugin automaticamente.

Erro comum e ação rápida:

- erro: atualização de plugin quebra login
- ação: usar fallback admin local, desfazer mudança do plugin e revalidar auth

Próximo passo:

- [Guia de Autenticação, SSO e Azure/Entra ID](../appendices/auth-sso-guide.md)
- [Matriz de Troubleshooting](../appendices/troubleshooting-matrix.md)
