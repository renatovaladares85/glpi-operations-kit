# Appendix: Deferred Features

Not implemented:

- LDAP/AD integration workflow
- SMTP integration workflow
- centralized Prometheus/Grafana/Alertmanager deployment
- HA/replication orchestration

Partially implemented:

- TLS lifecycle operations (mode switch and certificate apply are implemented; full corporate CA automation is deferred)
- backup baseline and scheduling (advanced key management and encrypted backup pipeline are deferred)

Implemented and enforced now:

- environment-specific precheck report with mandatory/optional/conditional items
- selectable policy mode per execution (`SECURITY_MODE=secure|permissive`)
- ordered deploy enforcement controlled by policy (`SECURITY_REQUIRE_ORDERED_EXECUTION`)
- promotion gate enforcement controlled by policy (`SECURITY_REQUIRE_PROMOTION_GATE`)
