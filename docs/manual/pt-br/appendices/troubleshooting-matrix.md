# Apêndice: Matriz de Troubleshooting

## `Permission denied` em `./scripts/*.sh`

- Sintoma: shell retorna `Permission denied` ao executar script diretamente.
- Causa provável: falta de execute bit.
- Verificação: `ls -l scripts/*.sh`
- Correção: `bash scripts/bootstrap-permissions.sh` ou `chmod +x scripts/*.sh`

## Marcador de bootstrap ausente

- Sintoma: script exige bootstrap antes de continuar.
- Causa provável: bootstrap não foi executado.
- Verificação: `ls -l .runtime/bootstrap.completed`
- Correção: `bash scripts/bootstrap-permissions.sh`

## Usuário fora do grupo `glpiops`

- Sintoma: pre-flight obrigatório falha na checagem de grupo.
- Verificação: `id -nG | tr ' ' '\n' | grep -Fx glpiops`
- Correção: `sudo groupadd -f glpiops && sudo usermod -aG glpiops "$USER"` e novo login.

## Falha de validação do sudo

- Sintoma: pre-flight obrigatório falha em sudo/root.
- Verificação: `sudo -v`
- Correção: ajustar política sudo mínima para o operador.
