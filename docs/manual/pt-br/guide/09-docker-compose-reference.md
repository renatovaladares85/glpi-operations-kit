# 09 - Trilha de Referência Docker/Compose (Separada)

Este capítulo é intencionalmente separado do fluxo operacional Linux tradicional.

Escopo atual da fase:

- stack Linux tradicional é o baseline operacional principal;
- Docker/Compose permanece separado do deploy principal;
- a automação nativa Docker/Compose cobre somente o serviço Mailpit pós-deploy via domínio `email`.

Como usar este capítulo:

1. tratar Docker/Compose como trilha alternativa;
2. não misturar instruções Docker com passos de deploy Linux tradicional;
3. manter decisões de produção alinhadas com arquitetura e política local.

Mailpit pós-deploy:

```bash
./scripts/glpictl.sh <environment> email check mailpit
./scripts/glpictl.sh <environment> email prepare mailpit
./scripts/glpictl.sh <environment> email install mailpit
./scripts/glpictl.sh <environment> email post-check mailpit
```

O comando exige Docker/Compose já instalado no host app, valida conflito de portas antes de aplicar mudanças e publica a UI em `EMAIL_MAILPIT_UI_PATH` seguindo HTTP ou HTTPS conforme `TLS_MODE`.

Próximo passo:

- [03 - Deploy em Linux](03-deploy-linux-traditional.md)
- [Plano de Implementação](../../../implementation-plan.md)
