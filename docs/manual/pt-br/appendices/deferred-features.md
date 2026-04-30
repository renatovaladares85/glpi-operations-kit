# Apêndice: Funcionalidades Postergadas

Não implementado:

- integração LDAP/AD;
- integração SMTP;
- provisionamento centralizado de Prometheus/Grafana/Alertmanager;
- orquestração de HA/replicação.

Parcialmente implementado:

- operações de ciclo de vida de TLS (troca de modo e aplicação de certificado existem; automação corporativa completa de CA ainda está postergada);
- baseline de backup e agendamento (gestão avançada de chaves e pipeline criptográfico ainda está postergada).

Implementado e já obrigatório:

- relatório de precheck com classificação obrigatório/opcional/condicional;
- gate de produção por configuração para TLS/HTTPS/SSO;
- bloqueio por ordem obrigatória de deploy;
- gate de certificação de staging para promoção à produção.
