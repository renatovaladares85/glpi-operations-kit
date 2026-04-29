# Apendice: Referencia de Comandos

## 1. Dependencias Ubuntu

```bash
sudo apt-get update
sudo apt-get install -y bash git openssh-client ansible
```

## 2. Bootstrap obrigatorio

```bash
bash scripts/bootstrap-permissions.sh
```

## 3. Deploy staging

```bash
./scripts/deploy-staging.sh check
./scripts/deploy-staging.sh apply all
```

## 4. TLS

```bash
./scripts/manage-tls.sh disable staging
./scripts/manage-tls.sh install-provided staging
```

## 5. Operacoes Day-2

```bash
bash scripts/ops-maintenance.sh users staging add os
bash scripts/ops-maintenance.sh cert staging check
bash scripts/ops-maintenance.sh audit staging check
bash scripts/ops-maintenance.sh resume staging
```
