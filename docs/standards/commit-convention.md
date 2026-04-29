# Commit Convention

## Padrao oficial

O repositorio usa `Conventional Commits`.

Formato:

```text
tipo(escopo): descricao
```

## Tipos permitidos

- `feat`
- `fix`
- `docs`
- `refactor`
- `chore`
- `perf`
- `test`
- `build`
- `ci`

## Escopos iniciais recomendados

- `ansible-base`
- `ansible-app`
- `ansible-db`
- `monitoring`
- `backup`
- `scripts`
- `docs`
- `agents`
- `security`

## Quando criar commit

Crie commit apenas ao fechar um `bloco funcional validado`.

Definicao de bloco funcional validado:

- muda uma unidade coerente de comportamento;
- pode ser entendida e revertida de forma isolada;
- recebeu a validacao minima aplicavel;
- nao mistura objetivos ou riscos diferentes.

## Exemplos bons

- `docs(agents): cria catalogo de padroes para IA`
- `fix(scripts): corrige fluxo de secrets em runtime`
- `feat(ansible-app): adiciona template inicial do nginx do glpi`
- `chore(monitoring): adiciona exporters base para staging`

## Exemplos ruins

- `update files`
- `fix: varias coisas`
- `docs(ansible-app): muda scripts e monitoring`
- `feat(all): ajusta tudo`

## Regra de recuperacao

Cada commit deve permitir identificar rapidamente:

- o que mudou;
- qual area foi afetada;
- se o rollback pode ser feito sem mexer no restante.
