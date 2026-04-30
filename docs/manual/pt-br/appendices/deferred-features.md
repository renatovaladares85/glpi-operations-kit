# Apêndice: Funcionalidades Postergadas

Não implementado:

- integração LDAP/AD;
- integração SMTP;
- provisionamento centralizado de Prometheus/Grafana/Alertmanager;
- orquestração de HA/replicação.

Parcialmente implementado:

- operações de ciclo de vida de TLS (troca de modo e aplicação de certificado existem; automação corporativa completa de CA ainda está postergada);
- baseline de backup e agendamento (gestão avançada de chaves e pipeline criptográfico ainda está postergada).

Implementado e obrigatório no modelo atual:

- relatório de precheck com classificação obrigatório/opcional/condicional;
- modo de política selecionável por execução (`SECURITY_MODE=secure|permissive`);
- enforcement de ordem de deploy controlado por política (`security.require_ordered_execution`);
- enforcement de gate de promoção controlado por política (`security.require_promotion_gate`).
