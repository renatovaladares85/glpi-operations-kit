# Apêndice: Referência de Comandos

## 1. Instalação de dependências (Ubuntu)

```bash
sudo apt-get update
sudo apt-get install -y bash git openssh-client python3 python3-yaml ansible
```

Finalidade:

- instalar dependências locais obrigatórias para scripts e Ansible.

## 2. Primeiro comando obrigatório

```bash
bash scripts/bootstrap-permissions.sh
```

Finalidade:

- aplicar permissões de execução nos scripts;
- validar `sudo`;
- validar participação no grupo `glpiops`;
- preparar estrutura segura de `.runtime`.

Resultado esperado:

- `Bootstrap completed.`

## 3. Chaves SSH por ambiente (obrigatório em execução remota)

Gerar chave para staging:

```bash
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/glpi_staging_ed25519 -C "glpi-staging-ops"
chmod 600 ~/.ssh/glpi_staging_ed25519
chmod 644 ~/.ssh/glpi_staging_ed25519.pub
```

Gerar chave para produção:

```bash
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/glpi_production_ed25519 -C "glpi-production-ops"
chmod 600 ~/.ssh/glpi_production_ed25519
chmod 644 ~/.ssh/glpi_production_ed25519.pub
```

Distribuir chave pública:

```bash
ssh-copy-id -i ~/.ssh/glpi_staging_ed25519.pub ubuntu@APP_HOST
ssh-copy-id -i ~/.ssh/glpi_staging_ed25519.pub ubuntu@DB_HOST
```

Validar conectividade:

```bash
ssh -i ~/.ssh/glpi_staging_ed25519 ubuntu@APP_HOST "echo ok"
ssh -i ~/.ssh/glpi_staging_ed25519 ubuntu@DB_HOST "echo ok"
```

## 4. Sequência principal de deploy

```bash
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply db
./scripts/glpictl.sh staging deploy apply app
./scripts/glpictl.sh staging deploy apply monitoring
./scripts/glpictl.sh staging deploy apply backup
./scripts/glpictl.sh staging deploy post-check all
```

Finalidade:

- executar fluxo recomendado em ordem.
- quando `security.require_ordered_execution=true`:
  - em `SECURITY_MODE=secure`, chamadas fora de ordem bloqueiam;
  - em `SECURITY_MODE=permissive`, chamadas fora de ordem continuam com warning + evidência.

## 5. Certificação e prontidão

```bash
./scripts/glpictl.sh staging certify run
bash scripts/release-readiness.sh staging
```

Finalidade:

- gerar evidências de homologação e trilha de prontidão.

## 6. Comandos mutáveis com modo de segurança selecionável

```bash
./scripts/glpictl.sh production deploy check all
./scripts/glpictl.sh production deploy apply db
./scripts/glpictl.sh production deploy apply app
./scripts/glpictl.sh production deploy apply monitoring
./scripts/glpictl.sh production deploy apply backup
./scripts/glpictl.sh production deploy post-check all
```

Exemplo modo seguro:

```bash
SECURITY_MODE=secure ./scripts/glpictl.sh production deploy apply app
```

Exemplo modo permissivo:

```bash
SECURITY_MODE=permissive SECURITY_JUSTIFICATION="Janela de teste aprovada no CAB-0426" ./scripts/glpictl.sh production deploy apply app
```

Comportamento:

- `secure`: violações de política bloqueiam.
- `permissive`: violações viram warning e são registradas em `.runtime/<env>/state/security-mode-last.yml` e `.runtime/<env>/evidence/security-mode-*.yml`.

## 7. Operações TLS

```bash
./scripts/glpictl.sh staging tls disable
./scripts/glpictl.sh staging tls self-signed
./scripts/glpictl.sh staging tls install-provided
./scripts/glpictl.sh staging tls reload
```

Finalidade:

- alternar modo TLS e reaplicar role da aplicação com validação.

## 8. Operações day-2

```bash
./scripts/glpictl.sh staging ops users add os
./scripts/glpictl.sh staging ops users disable db
./scripts/glpictl.sh staging ops cert check
./scripts/glpictl.sh staging ops cert renew
./scripts/glpictl.sh staging ops audit
./scripts/glpictl.sh staging ops resume
```

Finalidade:

- manutenção pós-implantação com checkpoint e logs de execução.

## 9. Fallback manual com Ansible

```bash
ansible-inventory -i .runtime/staging/inventory.runtime.yml --list
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags db --extra-vars @.runtime/staging/public.runtime.yml --extra-vars @.runtime/staging/overrides.runtime.yml --extra-vars @.runtime/staging/secrets.yml
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags app --extra-vars @.runtime/staging/public.runtime.yml --extra-vars @.runtime/staging/overrides.runtime.yml --extra-vars @.runtime/staging/secrets.yml
```

Quando usar:

- quando a CLI principal estiver indisponível e for necessário fallback controlado.
