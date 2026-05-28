# GLPI Operations Kit - Manual do Operador (PT-BR, Espelho)

Este manual é o espelho da versão canônica em EN.
Ele orienta uma instalação completa do GLPI Operations Kit em shell Linux e cobre preparação, preenchimento do `.env`, TLS, banco, aplicação, monitoramento, backup, validação e rollback.

Use esta página como roteador:

1. comece pela trilha guiada;
2. execute as etapas operacionais;
3. valide os resultados;
4. consulte apêndices técnicos apenas quando precisar de profundidade.

## Trilha Operacional (Guiada)

1. [Início e Prechecks](guide/01-start-and-prechecks.md)
2. [Ambiente e Topologia](guide/02-environment-and-topology.md)
3. [Deploy em Linux (Ubuntu + Nginx + PHP-FPM + MariaDB)](guide/03-deploy-linux-traditional.md)
4. [TLS e Certificados](guide/04-tls-and-certificates.md)
5. [Backup, Restore e Teste de Restore](guide/05-backup-restore-and-restore-test.md)
6. [Atualização In-Place do GLPI](guide/06-glpi-upgrade-in-place.md)
7. [Plugins e Marketplace (Fluxo Manual)](guide/07-plugins-and-marketplace.md)
8. [Validação e Troubleshooting](guide/08-validation-and-troubleshooting.md)
9. [Trilha de Referência Docker/Compose (Separada)](guide/09-docker-compose-reference.md)
10. [Cobertura da Automação](guide/10-automation-coverage.md)

## Atalhos por Intenção

- Quero instalar o GLPI: [Deploy em Linux](guide/03-deploy-linux-traditional.md)
- Quero configurar variáveis de ambiente: [Ambiente e Topologia](guide/02-environment-and-topology.md)
- Quero TLS/HTTPS: [TLS e Certificados](guide/04-tls-and-certificates.md)
- Quero backup: [Backup, Restore e Teste de Restore](guide/05-backup-restore-and-restore-test.md)
- Quero restore: [Backup, Restore e Teste de Restore](guide/05-backup-restore-and-restore-test.md)
- Quero atualizar o GLPI: [Atualização In-Place do GLPI](guide/06-glpi-upgrade-in-place.md)
- Quero validar serviços e saúde do ambiente: [Validação e Troubleshooting](guide/08-validation-and-troubleshooting.md)
- Estou com erro: [Validação e Troubleshooting](guide/08-validation-and-troubleshooting.md)
- Quero entender o que a automação faz: [Cobertura da Automação](guide/10-automation-coverage.md)
- Preciso de detalhes de comandos: [Referência de Comandos](appendices/command-reference.md)

## Referências Técnicas (Profundidade)

Use estes documentos quando precisar de explicações campo a campo ou detalhes técnicos avançados:

- [Índice de Apêndices](appendices/index.md)
- [Guia de Preenchimento do Ambiente](appendices/configuration-field-guide.md)
- [Modos TLS e Operações de Certificado](appendices/tls-modes.md)
- [Guia de Autenticação, SSO e Azure/Entra ID](appendices/auth-sso-guide.md)
- [Entradas e Arquivos de Runtime](appendices/runtime-input-reference.md)
- [Referência de Comandos](appendices/command-reference.md)
- [Checagens Operacionais](appendices/operational-checks.md)
- [Matriz de Troubleshooting](appendices/troubleshooting-matrix.md)

## Notas de Escopo

- EN permanece canônico.
- PT-BR espelha EN após atualização canônica.
- Docker/Compose está documentado como trilha de referência separada nesta fase.
