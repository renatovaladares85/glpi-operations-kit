# GLPI Operations Kit Manuals

This folder contains the operator manuals and appendices in mirrored English and Portuguese (Brazilian) structure.

## Start here

- English: [User Manual](en/user-manual.md)
- Português (Brasil): [Manual do Usuário](pt-br/user-manual.md)

## Installation and configuration references

- English: [Appendices Index](en/appendices/index.md)
- Português (Brasil): [Índice de Apêndices](pt-br/appendices/index.md)

Most operators should read in this order:

1. User Manual.
2. Configuration Field Guide.
3. TLS Modes and Certificate Operations.
4. Authentication, SSO, and Azure/Entra ID Guide, if external authentication is required.
5. Environment Examples.
6. Command Reference.
7. Troubleshooting Matrix.

## Runtime and secrets rule

- Public values: `config/<environment>.env`.
- Deployment secrets read from environment config: `DATABASE_PASSWORD`, `DATABASE_ROOT_PASSWORD`, `MONITORING_MYSQLD_EXPORTER_PASSWORD`.
- Auth secrets: `.runtime/<environment>/secrets.yml` only.
- Never commit `.runtime/`, private keys, tokens, real passwords, or customer-sensitive evidence.
