# Appendix: Troubleshooting Matrix

## Missing `ansible-playbook`

- Symptom: pre-flight fails with command not found
- Likely cause: Ansible not installed on operator machine
- Check: `command -v ansible-playbook`
- Fix path: install Ansible and rerun `deploy-staging.sh check`

## Missing `ansible-inventory`

- Symptom: pre-flight check fails in staging orchestrator
- Likely cause: incomplete Ansible install
- Check: `command -v ansible-inventory`
- Fix path: install required Ansible components and rerun check

## Invalid SSH private key path

- Symptom: runtime input loop rejects path
- Likely cause: wrong local path or missing key file
- Check: `ls -l <path>`
- Fix path: provide real key path with read permission

## Invalid app/db host input

- Symptom: runtime input loop rejects host value
- Likely cause: malformed hostname or IP
- Check: verify syntax and DNS/IP correctness
- Fix path: provide valid hostname or IPv4

## TLS provided mode rejects certificate path

- Symptom: runtime input loop rejects cert/key path
- Likely cause: missing local files
- Check: `ls -l <cert-path> <key-path>`
- Fix path: provide existing files or switch to `self_signed` / `none`

## Nginx validation failure

- Symptom: app role fails on `nginx -t`
- Likely cause: invalid rendered template or TLS file mismatch
- Check: inspect `/etc/nginx/sites-available/glpi.conf`
- Fix path: correct runtime TLS data and rerun app target

## PHP-FPM validation failure

- Symptom: app role fails on `php-fpm8.3 -t`
- Likely cause: invalid php-fpm pool or ini config
- Check: inspect `/etc/php/8.3/fpm/` configs and logs
- Fix path: correct runtime/app vars and rerun app target

## DB credential mismatch

- Symptom: GLPI installer cannot connect to DB
- Likely cause: wrong db secrets provided at runtime
- Check: verify `.runtime/staging/db.secrets.yml` and DB user grants
- Fix path: rerun db target with correct credentials

## App deployed but GLPI page does not load

- Symptom: HTTP/HTTPS endpoint unavailable
- Likely cause: service not running, firewall mismatch, wrong host/IP, or TLS mode issue
- Check: Nginx/PHP-FPM service status and network reachability
- Fix path: rerun pre-flight, verify runtime inventory, rerun base/app targets
