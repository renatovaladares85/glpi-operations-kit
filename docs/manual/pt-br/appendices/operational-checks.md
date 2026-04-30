# Apêndice: Checks Operacionais

## 1. Saídas do precheck

Após `deploy check`, validar:

- `.runtime/<env>/state/precheck-report-latest.yml`
- `.runtime/<env>/evidence/precheck-report-latest.md`

Esses artefatos classificam cada item como obrigatório, opcional, condicional, ou não aplicável.

## 2. Controle de sequência de deploy

Arquivo de estado:

- `.runtime/<env>/state/deploy-sequence.yml`

Ordem recomendada:

1. `deploy check all`
2. `deploy apply db`
3. `deploy apply app`
4. `deploy apply monitoring`
5. `deploy apply backup`
6. `deploy post-check all`

Comportamento:

- com `security.require_ordered_execution=true` e `SECURITY_MODE=secure`, execução fora de ordem bloqueia;
- com `SECURITY_MODE=permissive`, continua com warning e trilha de evidência.

## 3. Checks de serviço após apply

```bash
ansible-inventory -i .runtime/staging/inventory.runtime.yml --list >/dev/null
sudo nginx -t
sudo php-fpm8.3 -t
sudo systemctl status nginx php8.3-fpm mariadb --no-pager
```

## 4. Evidências de certificação e prontidão

```bash
./scripts/glpictl.sh staging certify run
bash scripts/release-readiness.sh staging
```

Artefatos esperados:

- `.runtime/staging/evidence/readiness-report.md`
- `.runtime/staging/evidence/readiness-report.json`
- `.runtime/promotion/staging-certified.yml` (quando gate estiver habilitado)

## 5. Evidências de operação day-2

Validar:

- `.runtime/<env>/logs/*.log`
- `.runtime/<env>/logs/*.summary.yml`
- `.runtime/<env>/state/*.state.yml`
- `.runtime/<env>/state/security-mode-last.yml` (modo permissivo)
- `.runtime/<env>/evidence/security-mode-*.yml` (modo permissivo)

Esses arquivos suportam auditoria, validação e investigação.
