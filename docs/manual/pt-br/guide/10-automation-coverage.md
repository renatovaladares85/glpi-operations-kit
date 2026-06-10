# 10 - Cobertura da Automação

Este capítulo mostra o que o repositório já automatiza e o que ainda é manual.

Contrato principal da CLI:

```bash
./scripts/glpictl.sh <environment> <deploy|certify|promote|tls|ops|audit|email> <action> [target] [scope]
```

Já coberto por automação:

- ciclo de deploy (`check`, `prepare`, `apply`, `post-check`, `rollback`)
- ciclo TLS (`check`, `prepare`, `apply`, `post-check`, `rollback`)
- e-mail pós-deploy com Mailpit (`check`, `prepare`, `install`, `post-check`, `rollback`)
- fluxos de certify/promotion gate
- fluxos ops/audit
- logs, estado, evidências e snapshots de domínio em runtime

Não automatizado como baseline operacional nesta fase:

- instalação automática de plugins
- fluxo dedicado de Let\'s Encrypt
- automação Docker/Compose além do serviço Mailpit pós-deploy

Próximo passo:

- [Referência de Comandos](../appendices/command-reference.md)
- [Entradas e Arquivos de Runtime](../appendices/runtime-input-reference.md)
- [Funcionalidades Postergadas](../appendices/deferred-features.md)
