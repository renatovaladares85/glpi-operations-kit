# Bash Scripts Standard

## Objetivo

Padronizar scripts guiados para operacao em `Ubuntu/Linux`.

## Regras

- Usar `#!/usr/bin/env bash`
- Usar `set -euo pipefail`
- Centralizar funcoes comuns em `scripts/lib/common.sh`
- Explicar por que cada dado sensivel esta sendo pedido
- Informar onde o dado sera gravado
- Interromper quando faltar informacao critica

## Runtime secrets

- Gravar apenas em `.runtime/<environment>/`
- Nunca versionar `.runtime/`
- Nao ecoar segredos no terminal

## Fluxo padrao

- `check`
- `apply`
- `post-check`

## Erros obrigatorios

Quando faltar dado critico, o script deve informar:

- qual dado falta;
- por que ele e necessario;
- em que arquivo ou componente sera usado.
