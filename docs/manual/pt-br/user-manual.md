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
./scripts/glpictl.sh staging deploy check all
```

2. Deploy por etapa:

```bash
./scripts/glpictl.sh staging deploy apply db
./scripts/glpictl.sh staging deploy apply app
./scripts/glpictl.sh staging deploy apply monitoring
./scripts/glpictl.sh staging deploy apply backup
```

### 3.1 Certificacao de staging e gate para producao (obrigatorio)

Antes de qualquer deploy em producao:

```bash
./scripts/glpictl.sh staging certify run
```

Comportamento esperado:

- gera evidencias em `.runtime/staging/evidence/<timestamp>/`
- grava aprovacao em `.runtime/promotion/staging-certified.yml`
- bloqueia promocao para producao se algum check obrigatorio falhar

## 4. Operacoes Day-2 (pos-implementacao)

Usuarios:

- `./scripts/glpictl.sh staging ops users add`
- `./scripts/glpictl.sh staging ops users disable`
- `./scripts/glpictl.sh staging ops users remove`

Certificados:

- `./scripts/glpictl.sh staging ops cert check`
- `./scripts/glpictl.sh staging ops cert renew`
- `./scripts/glpictl.sh staging ops cert apply`

Auditoria e continuidade:

- `./scripts/glpictl.sh staging audit check`
- `./scripts/glpictl.sh staging ops resume`

Persistencia operacional:

- logs: `.runtime/<environment>/logs/`
- checkpoints/estado: `.runtime/<environment>/state/`

Politica de certificado:

- alerta quando faltarem `<= 30` dias para expirar.

## 6. Rollout de producao (apos gate aprovado)

Execute somente apos `certify-staging.sh` com sucesso:

```bash
./scripts/glpictl.sh production deploy check all
./scripts/glpictl.sh production deploy apply db
./scripts/glpictl.sh production deploy apply app
./scripts/glpictl.sh production deploy apply monitoring
./scripts/glpictl.sh production deploy apply backup
./scripts/glpictl.sh production deploy post-check all
```

`apply` em producao e bloqueado se `.runtime/promotion/staging-certified.yml` estiver ausente ou sem status aprovado.

## 7. Referencias

- [Indice multilingua](../README.md)
- [Indice de apendices PT-BR](appendices/index.md)
