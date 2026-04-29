# Apêndice: Checks Operacionais

Pre-flight obrigatório:

- `bash`
- `git`
- `ansible-playbook`
- `ansible-inventory`
- disco local livre >= 1 GB

Pre-flight opcional:

- `ssh`

Comandos:

```bash
command -v bash
command -v git
command -v ansible-playbook
command -v ansible-inventory
command -v ssh
df -Pk .
```

Checks pós-implantação:

```bash
ansible-inventory -i .runtime/staging/inventory.runtime.yml --list >/dev/null
sudo nginx -t
sudo php-fpm8.3 -t
sudo systemctl status nginx php8.3-fpm mariadb --no-pager
```

Higiene de runtime:

- manter `.runtime/`
- não versionar segredos
- usar `chmod 600` em arquivos de segredo
