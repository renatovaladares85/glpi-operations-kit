# GLPI Product Audit

## Objective

Assess whether this repository can be sold and reused as a generic GLPI deployment product.

## Current Product Readiness

Current status: `partially ready`

Why:

- strong automation baseline exists
- scripts, Ansible roles, monitoring exporters, backups, and runbooks already exist
- new central public configuration model improves reuse
- secrets remain outside Git
- promotion gate exists between staging and production

## Product Strengths

- reusable Ubuntu + Ansible + Nginx + PHP-FPM + MariaDB baseline
- separate app and db host model already supported
- single-server fallback supported
- runtime secrets isolated under `.runtime/`
- day-2 operations, checkpoints, and logs already present
- operator runbook substantially improved

## Product Blockers

- runtime overrides are not yet fully modeled for every mutable operational change
  - example: TLS action flow still needs a cleaner long-term override strategy
- scripts still rely on generated runtime intermediates instead of consuming product config directly everywhere
- duplicate/legacy documentation trees still exist and should be rationalized
- centralized monitoring stack remains blueprint-only
- restore drill documentation exists conceptually but still needs a stronger product evidence workflow

## Usability Issues

- some manual appendices still reflect the older runtime file model
- legacy docs such as `docs/user-manual.md` and `docs/manual-appendices/*` need consolidation or deprecation
- direct script behavior is strong, but public config precedence needs to be more visible in all docs

## Maintainability Issues

- inventory defaults and generated runtime values coexist, which can confuse future maintainers
- public runtime generation is now standardized, but Ansible group vars still act as a fallback layer
- some product naming remains repository-scoped rather than purely generic

## Future Enhancements

- split secret prompting by domain (`db`, `app`, `monitoring`)
- add config schema validation command for operators
- add product packaging docs for customer onboarding
- add central monitoring stack deployment profile
- add stronger backup encryption/key management workflow

## Can This Be Sold Now?

Answer: `not yet as a polished commercial product`, but `yes as a strong implementation accelerator`.

What blocks direct commercial handoff:

- configuration layer still needs full adoption across all docs and flows
- blueprint areas still need implementation or explicit product packaging language
- documentation duplication needs cleanup

## What Should Be Simplified First?

1. Eliminate old runtime-file references from remaining manuals and appendices.
2. Complete public-config-first flow in every script path.
3. Add domain-scoped secret prompting to reduce operator noise.

## What Should Be Templated First?

1. customer identity and branding
2. environment host/domain values
3. resource profiles
4. monitoring thresholds and labels
5. backup policy defaults

## Recommendation

Position the repository as:

- a reusable GLPI operations kit
- customer-adaptable by `config/<environment>.yml`
- secrets injected at runtime
- ready for controlled enterprise delivery after one more cleanup/refinement cycle
