# Manual do Usuario GLPI SoEnergy

## 1. Visao geral

Este manual e um runbook para operadores instalarem, validarem e manterem o GLPI em staging.

## 2. Pre-requisitos

- executar a partir de host alvo (app ou db)
- ferramentas obrigatorias: `bash`, `git`, `ansible-playbook`, `ansible-inventory`
- usuario operador no grupo `glpiops`
- privilegio sudo valido

Setup obrigatorio:

```bash
sudo groupadd -f glpiops
sudo usermod -aG glpiops "$USER"
newgrp glpiops
sudo -v
```

## 3. Fluxo de implantacao

0. Bootstrap de permissoes:

```bash
bash scripts/bootstrap-permissions.sh
```

1. Precheck e coleta:

```bash
./scripts/deploy-staging.sh check
```

2. Deploy por etapa:

```bash
./scripts/deploy-staging.sh apply db
./scripts/deploy-staging.sh apply app
./scripts/deploy-staging.sh apply monitoring
./scripts/deploy-staging.sh apply backup
```

## 4. Operacoes Day-2 (pos-implementacao)

Usuarios:

- `bash scripts/ops-maintenance.sh users staging add os`
- `bash scripts/ops-maintenance.sh users staging disable db`
- `bash scripts/ops-maintenance.sh users staging remove glpi`

Certificados:

- `bash scripts/ops-maintenance.sh cert staging check`
- `bash scripts/ops-maintenance.sh cert staging renew`
- `bash scripts/ops-maintenance.sh cert staging apply`

Auditoria e continuidade:

- `bash scripts/ops-maintenance.sh audit staging check`
- `bash scripts/ops-maintenance.sh resume staging`

Persistencia operacional:

- logs: `.runtime/<environment>/logs/`
- checkpoints/estado: `.runtime/<environment>/state/`

Politica de certificado:

- alerta quando faltarem `<= 30` dias para expirar.

## 5. Referencias

- [Indice multilingua](../README.md)
- [Indice de apendices PT-BR](appendices/index.md)
