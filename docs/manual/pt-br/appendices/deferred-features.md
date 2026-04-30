# Apêndice: Funcionalidades Postergadas

Não implementado:

- integração LDAP/AD
- integração SMTP
- provisionamento centralizado de Prometheus/Grafana/Alertmanager
- orquestração de HA/replicação

Parcialmente implementado:

- ciclo de vida de TLS (troca de modo e aplicação de certificado existem; automação completa de CA corporativa continua postergada)
- baseline de backup/agendamento (pipeline avançado de criptografia e gestão de chaves continua postergado)

Implementado no modelo atual:

- relatório de precheck com classificação obrigatório/opcional/condicional
- modo de política por execução (`SECURITY_MODE=secure|permissive`)
- enforcement de ordem de deploy por política (`security.require_ordered_execution`)
- enforcement de gate de promoção por política (`security.require_promotion_gate`)
