# Repetitive Commands

Registre aqui comandos recorrentes que sejam seguros, reutilizaveis e economizem contexto.

## Formato

### Objetivo

### Comando

### Quando usar

### Pre-condicoes

### Riscos

## Comandos iniciais

### Objetivo

Validar estrutura de inventario Ansible.

### Comando

```bash
ansible-inventory --list -i ansible/inventories/staging/hosts.yml
```

### Quando usar

Antes de rodar playbooks ou ao alterar inventories.

### Pre-condicoes

- `ansible` instalado

### Riscos

- baixo risco; apenas leitura

### Objetivo

Validar sintaxe do playbook principal.

### Comando

```bash
ansible-playbook --syntax-check ansible/site.yml
```

### Quando usar

Antes de commitar mudancas em Ansible.

### Pre-condicoes

- `ansible` instalado

### Riscos

- baixo risco; nao altera estado remoto
