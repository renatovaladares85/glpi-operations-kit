# Appendix: Troubleshooting Matrix

## Missing `ansible-playbook` or `ansible-inventory`

- Symptom: pre-flight shows missing mandatory command and asks to install
- Likely cause: Ansible package not installed on execution host
- Check: `command -v ansible-playbook && command -v ansible-inventory`
- Fix path: accept script install prompt or run `sudo apt-get update && sudo apt-get install -y ansible`
- Safe resume: rerun `./scripts/deploy-staging.sh check`

## Auto-install prompt denied

- Symptom: pre-flight stops after missing mandatory command
- Likely cause: operator answered `n` to install prompt
- Check: review last pre-flight output
- Fix path: install dependencies manually
- Safe resume: rerun the same command that was interrupted

## Invalid SSH private key path

- Symptom: runtime input loop rejects path
- Likely cause: wrong path, missing file, or wrong permissions
- Check: `ls -l <path-to-key>`
- Fix path: use real key file and set `chmod 600 <path-to-key>`
- Safe resume: continue prompt loop with corrected path

## Invalid app/db host input

- Symptom: runtime input loop rejects host value
- Likely cause: malformed hostname or IP
- Check: verify syntax and DNS/IP correctness
- Fix path: provide valid hostname or IPv4
- Safe resume: continue prompt loop with corrected host

## TLS provided mode rejects certificate path

- Symptom: runtime input loop rejects cert/key path
- Likely cause: missing local files
- Check: `ls -l <cert-path> <key-path>`
- Fix path: provide existing files or switch to `self_signed` / `none`
- Safe resume: rerun `./scripts/manage-tls.sh install-provided staging`

## SSH remote access fails in dual-server mode

- Symptom: Ansible cannot connect to remote app or db host
- Likely cause: wrong user, wrong key, SSH blocked, missing sudo privilege
- Check: `ssh -i <key> <user>@<host> "hostname && id"`
- Fix path: correct user/key/network and ensure sudo access
- Safe resume: rerun `check`, then rerun failed `apply <target>`

## Package install fails during pre-flight auto-install

- Symptom: prompt accepted but dependency still missing
- Likely cause: apt lock, repository issue, insufficient privilege
- Check: `sudo apt-get update`
- Fix path: resolve apt issue, then `sudo apt-get install -y <package>`
- Safe resume: rerun original deployment command

## Nginx validation failure

- Symptom: app role fails on `nginx -t`
- Likely cause: invalid rendered template or TLS file mismatch
- Check: `sudo nginx -t` and inspect `/etc/nginx/sites-available/glpi.conf`
- Fix path: correct runtime TLS data and rerun app target
- Safe resume: `./scripts/deploy-staging.sh apply app`

## PHP-FPM validation failure

- Symptom: app role fails on `php-fpm8.3 -t`
- Likely cause: invalid php-fpm pool or ini config
- Check: `sudo php-fpm8.3 -t` and inspect `/etc/php/8.3/fpm/` configs and logs
- Fix path: correct runtime/app vars and rerun app target
- Safe resume: `./scripts/deploy-staging.sh apply app`

## DB credential mismatch

- Symptom: GLPI installer cannot connect to DB
- Likely cause: wrong db secrets provided at runtime
- Check: verify `.runtime/staging/db.secrets.yml` and DB user grants
- Fix path: rerun db target with correct credentials
- Safe resume: `./scripts/deploy-staging.sh apply db`, then retry installer

## App deployed but GLPI page does not load

- Symptom: HTTP/HTTPS endpoint unavailable
- Likely cause: service not running, firewall mismatch, wrong host/IP, or TLS mode issue
- Check: Nginx/PHP-FPM service status and network reachability
- Fix path: rerun pre-flight, verify runtime inventory, rerun base/app targets
- Safe resume: `./scripts/deploy-staging.sh apply base` then `./scripts/deploy-staging.sh apply app`
