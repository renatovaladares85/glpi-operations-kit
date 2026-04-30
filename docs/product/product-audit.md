# GLPI Product Audit

## Objective

Assess whether this repository can be sold and reused as a generic GLPI deployment product.

## Current Product Readiness

Current status: `partially ready`

Why:

- strong automation baseline exists
- scripts, Ansible roles, monitoring exporters, backups, and runbooks already exist
- new central public configuration model improves reuse
- runtime override layer exists for mutable operational settings
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

- real staging E2E evidence is still required for final release declaration
- scripts still rely on generated runtime intermediates as the execution contract
- duplicate/legacy documentation trees still exist and should be rationalized
- centralized monitoring stack remains blueprint-only
- restore drill documentation exists conceptually but still needs a stronger product evidence workflow

## Usability Issues

- legacy docs such as `docs/user-manual.md` and `docs/manual-appendices/*` need consolidation or deprecation
- readiness acceptance still depends on running full staging E2E and collecting real evidence

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

1. Consolidate legacy doc trees into one canonical structure per language.
2. Add domain-scoped secret prompting to reduce operator noise.
3. Expand readiness evidence automation for restore drill execution proof.

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
