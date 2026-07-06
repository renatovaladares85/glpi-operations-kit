#!/usr/bin/env python3
"""Safe environment file synchronization tool.

Exit codes:
0 = success without critical error
1 = validation or execution error
2 = differences found in report mode
3 = manual review required found
4 = permission or backup error
"""

from __future__ import annotations

import argparse
import importlib.util
import os
import re
import shutil
import sys
import tempfile
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable

SUPPORTED_POLICIES = {"protected", "managed", "review_required", "deprecated"}
SECRET_NAME_HINTS = (
    "PASSWORD",
    "PASS",
    "SECRET",
    "TOKEN",
    "PRIVATE",
    "CREDENTIAL",
    "CLIENT_SECRET",
    "AUTH",
    "APP_KEY",
)
SECRET_MASK = "********"

EXIT_SUCCESS = 0
EXIT_ERROR = 1
EXIT_DIFF = 2
EXIT_REVIEW_REQUIRED = 3
EXIT_PERMISSION = 4

DEFAULT_TEMPLATE_PATH = Path("config/.env.example")
DEFAULT_GENERATED_RULES_PATH = Path(".env.sync.generated.yml")
DEFAULT_PUBLISHED_RULES_PATH = Path(".env.sync.yml")
DEFAULT_REPORT_PATH = Path("docs/env-sync-contract-report.md")
DEFAULT_RULES_DEFAULTS = {
    "add_missing": True,
    "remove_extra": False,
    "backup": True,
    "default_mode": "report",
    "apply_managed_changes": False,
    "validate_rule_keys_in_source": True,
    "backup_dir": ".env-backups",
}

KEY_PATTERN = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
TEMPLATE_KEY_PATTERN = re.compile(r"[A-Z_][A-Z0-9_]*")
RENDER_KEY_USAGE_PATTERN = re.compile(r'(?:read_value|require_value)\(values,\s*"([A-Z0-9_]+)"')

MANAGED_KEYS = {"PRODUCT_NAME"}
REVIEW_REQUIRED_KEYS = {
    "EXECUTION_MODE",
    "EXECUTION_HOST_ROLE_DEFAULT",
    "TOPOLOGY_MODE",
    "NETWORK_DATABASE_APP_ACCESS_HOST",
    "NETWORK_DATABASE_ACCESS_MODE",
    "NETWORK_DATABASE_ALLOWED_SOURCE_HOSTS",
    "GLPI_VERSION",
    "WEB_SERVER_TYPE",
    "WEB_HTTP_PORT",
    "WEB_HTTPS_PORT",
    "TLS_MODE",
    "GLPI_REDIS_CACHE_PREFIX",
    "GLPI_REDIS_SESSION_LOCKING",
    "GLPI_REDIS_MAXMEMORY",
    "GLPI_REDIS_MAXMEMORY_POLICY",
    "OPERATIONS_TIMEZONE",
    "RESOURCE_PROFILE_ACTIVE",
    "DATABASE_DEPLOYMENT_MODE",
    "MONITORING_PROFILE",
    "MONITORING_PROMETHEUS_ENABLED",
    "MONITORING_PROMETHEUS_BIND_HOST",
    "MONITORING_PROMETHEUS_PORT",
    "MONITORING_PROMETHEUS_RETENTION_TIME",
    "MONITORING_PROMETHEUS_RETENTION_SIZE",
    "MONITORING_GRAFANA_ENABLED",
    "MONITORING_GRAFANA_ADMIN_USER",
    "MONITORING_GRAFANA_BIND_HOST",
    "MONITORING_GRAFANA_PORT",
    "MONITORING_GRAFANA_PUBLIC_MODE",
    "MONITORING_GRAFANA_PUBLIC_PATH",
    "MONITORING_GRAFANA_PUBLIC_FQDN",
    "MONITORING_GRAFANA_DOMAIN",
    "MONITORING_GRAFANA_REQUIRE_AUTH",
    "MONITORING_GRAFANA_REQUIRE_HTTPS",
    "MONITORING_EXPORTER_BIND_HOST",
    "MONITORING_EXPORTER_ALLOWED_SOURCE_HOSTS",
    "MONITORING_NODE_EXPORTER_ENABLED",
    "MONITORING_MYSQLD_EXPORTER_ENABLED",
    "MONITORING_NGINX_EXPORTER_ENABLED",
    "MONITORING_PHP_FPM_EXPORTER_ENABLED",
    "MONITORING_BLACKBOX_EXPORTER_ENABLED",
    "MONITORING_BLACKBOX_TARGETS_JSON",
    "MONITORING_GLPI_CUSTOM_METRICS_ENABLED",
    "MONITORING_GLPI_CUSTOM_METRICS_INTERVAL_SECONDS",
    "MONITORING_GLPI_METRICS_DB_USER",
    "MONITORING_GLPI_BACKUP_FRESHNESS_ENABLED",
    "MONITORING_GLPI_BACKUP_MAX_AGE_HOURS",
    "ALERTMANAGER_ENABLED",
    "MONITORING_ALERTMANAGER_BIND_HOST",
    "MONITORING_ALERTMANAGER_PORT",
    "GLPI_TIMEZONE_DB_MODE",
    "GLPI_TIMEZONE_SUPPORT_ENABLED",
    "GLPI_TIMEZONE_DB_LEGACY_GRANT",
}
EXPLICIT_SECRET_KEYS = {
    "DATABASE_USER",
    "MONITORING_MYSQLD_EXPORTER_USER",
}
CONDITIONAL_REQUIRED_REASON = {
    "DATABASE_ROOT_PASSWORD": "Obrigatória quando DATABASE_DEPLOYMENT_MODE=self_hosted.",
    "MONITORING_MYSQLD_EXPORTER_PASSWORD": "Legada. Prefira mysqld_exporter_password em .runtime/<environment>/secrets.yml.",
    "DATABASE_MANAGED_ADMIN_PASSWORD": "Opcional para fallback de conectividade no modo managed.",
}
SAFE_DEFAULT_KEYS = {
    "PRODUCT_NAME",
    "ENVIRONMENT_NAME",
    "WEB_SERVER_TYPE",
    "WEB_HTTP_PORT",
    "WEB_HTTPS_PORT",
    "TLS_MODE",
    "OPERATIONS_TIMEZONE",
    "RESOURCE_PROFILE_ACTIVE",
    "NETWORK_DATABASE_ACCESS_MODE",
    "DATABASE_DEPLOYMENT_MODE",
    "GLPI_TIMEZONE_DB_MODE",
}

REVIEW_REQUIRED_DETAILS = {
    "EXECUTION_MODE": {
        "reason": "Muda o modelo operacional (local/ssh) e pré-requisitos de execução.",
        "impact": "Valor incorreto pode quebrar orquestração e impedir deploy/check.",
        "validation": [
            "Validar modo com a topologia operacional do ambiente.",
            "Para ssh, validar usuário/chave e conectividade.",
            "Executar deploy check após alteração.",
        ],
    },
    "EXECUTION_HOST_ROLE_DEFAULT": {
        "reason": "Controla escopo de ações mutáveis em execução local.",
        "impact": "Papel incorreto pode aplicar etapas no host errado.",
        "validation": [
            "Confirmar se o host atual é app, db ou all.",
            "Executar deploy check com escopo correspondente.",
            "Validar sequência operacional no runbook.",
        ],
    },
    "TOPOLOGY_MODE": {
        "reason": "Altera fluxo entre single-server e dual-server.",
        "impact": "Modo incorreto pode executar roles fora da topologia real.",
        "validation": [
            "Confirmar topologia real do ambiente alvo.",
            "Validar aliases e endpoints app/db.",
            "Executar pré-checks e smoke tests após alteração.",
        ],
    },
    "NETWORK_DATABASE_APP_ACCESS_HOST": {
        "reason": "Define origem de acesso APP->DB e impacta grants/firewall.",
        "impact": "Valor incorreto bloqueia conexão com o banco.",
        "validation": [
            "Validar host de origem efetivo da aplicação.",
            "Validar grants e firewall após alteração.",
            "Executar teste de conectividade APP -> DB.",
        ],
    },
    "NETWORK_DATABASE_ACCESS_MODE": {
        "reason": "Altera modelo de exposição de rede e escopo de firewall/grants.",
        "impact": "Configuração incorreta pode bloquear a aplicação ou ampliar exposição do banco.",
        "validation": [
            "Validar regras de firewall e grants após alteração.",
            "Validar conectividade APP -> DB com testes de deploy.",
            "Quando open, manter NETWORK_DATABASE_ALLOWED_SOURCE_HOSTS vazio.",
        ],
    },
    "NETWORK_DATABASE_ALLOWED_SOURCE_HOSTS": {
        "reason": "Afeta superfície de acesso ao banco e depende de topologia/rede real.",
        "impact": "Valor incorreto pode causar indisponibilidade ou exposição indevida.",
        "validation": [
            "Revisar lista de origens com equipe de rede.",
            "Confirmar que hosts autorizados correspondem ao ambiente alvo.",
            "Executar teste de conectividade após alteração.",
        ],
    },
    "GLPI_VERSION": {
        "reason": "Troca de versão implica mudança de release e potencial impacto funcional.",
        "impact": "Versão incompatível pode causar falha de upgrade/deploy ou regressão.",
        "validation": [
            "Validar compatibilidade da versão com o runbook e plugins.",
            "Executar deploy check e smoke tests após alteração.",
            "Validar plano de rollback antes de promover.",
        ],
    },
    "WEB_SERVER_TYPE": {
        "reason": "Muda pacotes e templates aplicados no host de aplicação.",
        "impact": "Escolha incorreta pode quebrar roteamento web e serviço HTTP(S).",
        "validation": [
            "Validar compatibilidade com o host alvo.",
            "Executar validação de configuração web após deploy.",
            "Executar smoke test de acesso à aplicação.",
        ],
    },
    "WEB_HTTP_PORT": {
        "reason": "Mudança de porta pode exigir ajuste de firewall, proxy e health checks.",
        "impact": "Porta incorreta pode tornar a aplicação inacessível.",
        "validation": [
            "Verificar bind da porta no host da aplicação.",
            "Validar regras de firewall e proxy reverso.",
            "Executar smoke test HTTP após alteração.",
        ],
    },
    "WEB_HTTPS_PORT": {
        "reason": "Mudança de porta TLS impacta certificados, firewall e acesso externo.",
        "impact": "Porta incorreta pode quebrar acesso seguro e validação de TLS.",
        "validation": [
            "Verificar bind da porta TLS no host da aplicação.",
            "Validar firewall e balanceador/proxy.",
            "Executar validação de certificado e acesso HTTPS.",
        ],
    },
    "TLS_MODE": {
        "reason": "Altera fluxo operacional de certificados e exposição HTTPS.",
        "impact": "Modo incorreto pode interromper acesso seguro ou falhar validações de segurança.",
        "validation": [
            "Validar pré-requisitos do modo selecionado (arquivos/certificados).",
            "Executar check de TLS e smoke test HTTPS.",
            "Validar política de segurança do ambiente.",
        ],
    },
    "OPERATIONS_TIMEZONE": {
        "reason": "Afeta agendamentos, logs e consistência temporal operacional.",
        "impact": "Timezone incorreta pode causar inconsistência de logs e execução em horário indevido.",
        "validation": [
            "Validar timezone no SO e no runtime após alteração.",
            "Confirmar impacto em janelas operacionais e cron.",
            "Revisar evidências e timestamps pós-deploy.",
        ],
    },
    "RESOURCE_PROFILE_ACTIVE": {
        "reason": "Muda limites de recursos e tuning de runtime.",
        "impact": "Perfil inadequado pode degradar performance ou estabilidade.",
        "validation": [
            "Validar capacidade de CPU/memória do host.",
            "Executar check de serviços após alteração de perfil.",
            "Monitorar métricas e erros após deploy.",
        ],
    },
    "DATABASE_DEPLOYMENT_MODE": {
        "reason": "Alterna entre fluxo self-hosted e managed com diferenças operacionais relevantes.",
        "impact": "Modo incorreto pode acionar automações incompatíveis com a infraestrutura.",
        "validation": [
            "Confirmar modelo de banco do ambiente alvo.",
            "Validar conectividade e credenciais para o modo escolhido.",
            "Executar checks completos de deploy após alteração.",
        ],
    },
    "MONITORING_NODE_EXPORTER_ENABLED": {
        "reason": "Ativa/desativa componente operacional de monitoramento.",
        "impact": "Configuração incorreta pode reduzir observabilidade ou gerar ruído.",
        "validation": [
            "Validar política de monitoramento do ambiente.",
            "Confirmar status do exporter após alteração.",
            "Validar scrape e alertas relacionados.",
        ],
    },
    "MONITORING_MYSQLD_EXPORTER_ENABLED": {
        "reason": "Ativa/desativa exporter de banco com dependência de credenciais e grants.",
        "impact": "Configuração incorreta pode ocultar métricas críticas de banco.",
        "validation": [
            "Validar modo de banco e necessidade do exporter.",
            "Confirmar credenciais/grants quando habilitado.",
            "Validar scrape e alertas relacionados ao banco.",
        ],
    },
}

ANSI = {
    "green": "\033[32m",
    "yellow": "\033[33m",
    "red": "\033[31m",
    "blue": "\033[34m",
    "gray": "\033[90m",
    "reset": "\033[0m",
}


class EnvSyncError(Exception):
    """Base exception for env-sync errors."""


class ValidationError(EnvSyncError):
    """Raised when an input validation fails."""


class PermissionErrorSync(EnvSyncError):
    """Raised for permission or backup failures."""


@dataclass
class EnvLine:
    line_type: str
    original_line: str
    line_number: int
    key: str | None = None
    value: str | None = None
    prefix: str | None = None
    suffix: str = ""
    quote_style: str = "none"


@dataclass
class ParsedEnv:
    path: Path
    lines: list[EnvLine]
    trailing_newline: bool
    key_indices: dict[str, int]
    values: dict[str, str]
    duplicates: set[str]
    commented_key_indices: dict[str, int]
    commented_values: dict[str, str]
    key_order: list[str]


@dataclass
class KeyRule:
    description: str
    required: bool
    policy: str
    auto_apply: bool = False
    default: str | None = None
    allowed_values: list[str] | None = None
    secret: bool = False
    reason: str | None = None
    impact: str | None = None
    validation: list[str] | None = None


@dataclass
class RulesConfig:
    version: int
    defaults: dict[str, Any]
    keys: dict[str, KeyRule]


@dataclass
class SyncPlan:
    mode: str
    added: list[dict[str, Any]]
    changed: list[dict[str, Any]]
    kept_target_values: list[dict[str, Any]]
    preserved_protected: list[dict[str, Any]]
    review_required: list[dict[str, Any]]
    required_missing: list[dict[str, Any]]
    extra_in_target: list[dict[str, Any]]
    deprecated: list[dict[str, Any]]
    ambiguous: list[dict[str, Any]]
    validation_errors: list[str]
    ok_count: int
    applied_changes: int
    updates: dict[str, str]
    additions: list[tuple[str, str]]
    removals: list[str]
    source_key_order: list[str]
    backup_path: Path | None = None


@dataclass
class TemplateKey:
    key: str
    value: str
    description: str
    line_number: int
    commented: bool


@dataclass
class PostCheckResult:
    target: Path
    exists: bool
    exit_code: int
    summary: str
    missing_keys: list[str] = field(default_factory=list)
    review_required_keys: list[str] = field(default_factory=list)
    extra_keys: list[str] = field(default_factory=list)
    ambiguous_keys: list[str] = field(default_factory=list)
    validation_errors: list[str] = field(default_factory=list)


class ReportBuilder:
    def __init__(self, use_color: bool) -> None:
        self.use_color = use_color

    def color(self, text: str, tone: str) -> str:
        if not self.use_color or tone not in ANSI:
            return text
        return f"{ANSI[tone]}{text}{ANSI['reset']}"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Sync environment files and generate .env.sync.yml contracts.",
        epilog=(
            "Exit codes: 0=success, 1=validation/execution error, "
            "2=differences in report mode, 3=manual review required, 4=permission/backup error"
        ),
    )
    parser.add_argument("--source", help="Reference env file (example: config/.env.example)")
    parser.add_argument("--target", help="Real environment file to analyze/apply")
    parser.add_argument("--rules", help="YAML rules file (.env.sync.yml)")
    parser.add_argument("--mode", choices=["report", "apply"], default="report", help="Execution mode")
    parser.add_argument("--only", default="", help="Comma-separated keys to analyze/apply")
    parser.add_argument(
        "--allow-managed",
        action="store_true",
        help="Compatibility flag; apply now adds missing non-deprecated keys and preserves existing target values.",
    )
    parser.add_argument(
        "--force-reviewed",
        default="",
        help="Compatibility validation for review_required keys; existing target values are preserved.",
    )
    parser.add_argument("--write-report", default="", help="Optional report output file")
    parser.add_argument("--no-color", action="store_true", help="Disable colored output")
    parser.add_argument("--verbose", action="store_true", help="Show extra validation context")
    parser.add_argument(
        "--reconcile-interactive",
        action="store_true",
        help="Interactive reconcile in apply mode: add missing keys, prompt for divergent values, and handle extra keys.",
    )
    parser.add_argument(
        "--extra-action",
        choices=["comment", "remove"],
        default="comment",
        help="How to handle extras in --reconcile-interactive; normal apply removes active keys absent from source.",
    )
    parser.add_argument(
        "--generate-contract",
        action="store_true",
        help="Generate env-sync contract from config/.env.example and discovered config/<environment>.env files.",
    )
    parser.add_argument(
        "--output",
        default=str(DEFAULT_GENERATED_RULES_PATH),
        help="Output path for generated contract (default: .env.sync.generated.yml).",
    )
    parser.add_argument(
        "--publish",
        action="store_true",
        help="Copy generated contract to .env.sync.yml after generation.",
    )
    parser.add_argument(
        "--report-output",
        default=str(DEFAULT_REPORT_PATH),
        help="Markdown report output path (default: docs/env-sync-contract-report.md).",
    )
    parser.add_argument(
        "--no-report",
        action="store_true",
        help="Disable markdown report generation in --generate-contract mode.",
    )
    parser.add_argument(
        "--strict-post-checks",
        action="store_true",
        help="Fail generation when post-check report finds differences or review-required items.",
    )
    return parser.parse_args()


def ensure_readable_file(path: Path, label: str) -> None:
    if not path.exists():
        raise ValidationError(f"Missing {label} file: {path}")
    if not path.is_file():
        raise ValidationError(f"Invalid {label} path (not a file): {path}")
    if not os.access(path, os.R_OK):
        raise PermissionErrorSync(f"Read permission denied for {label} file: {path}")


def parse_key_list(raw: str) -> set[str]:
    keys = {token.strip() for token in raw.split(",") if token.strip()}
    return keys


def normalize_rule_value(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def load_yaml_module() -> Any:
    try:
        import yaml
    except ModuleNotFoundError as exc:
        raise ValidationError("Missing dependency: PyYAML.\nInstall with: pip install pyyaml") from exc
    return yaml


def render_contract_script_path() -> Path:
    return Path(__file__).resolve().parent / "lib" / "render_product_config.py"


def load_render_contract_module() -> Any:
    script_path = render_contract_script_path()
    if not script_path.is_file():
        raise ValidationError(f"Missing render contract script: {script_path}")

    spec = importlib.util.spec_from_file_location("render_product_config_contract", script_path)
    if spec is None or spec.loader is None:
        raise ValidationError(f"Unable to load render contract metadata: {script_path}")

    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def discover_environment_files(config_dir: Path) -> list[Path]:
    if not config_dir.is_dir():
        return []
    env_files = [
        path
        for path in sorted(config_dir.glob("*.env"))
        if path.name != ".env.example"
    ]
    return env_files


def extract_template_description(raw_lines: list[str], line_index: int) -> str:
    comments: list[str] = []
    cursor = line_index - 1
    while cursor >= 0:
        raw = raw_lines[cursor]
        stripped = raw.strip()
        if stripped == "":
            if comments:
                break
            cursor -= 1
            continue
        if not stripped.startswith("#"):
            break
        comments.append(stripped[1:].strip())
        cursor -= 1

    for text in reversed(comments):
        lowered = text.lower()
        if not text:
            continue
        if lowered.startswith("format:") or lowered.startswith("example:"):
            continue
        if text.startswith("---"):
            continue
        return text
    return ""


def parse_template_assignment_line(raw_line: str, line_number: int) -> tuple[str, str] | None:
    stripped = raw_line.strip()
    if not stripped:
        return None

    normalized = stripped
    if normalized.startswith("#"):
        normalized = normalized[1:].lstrip()
    if "=" not in normalized:
        return None

    left = normalized.split("=", 1)[0].strip()
    if not TEMPLATE_KEY_PATTERN.fullmatch(left):
        return None

    parsed = parse_env_line(normalized, line_number)
    if parsed.line_type != "key_value" or parsed.key is None:
        return None
    return parsed.key, parsed.value or ""


def extract_template_keys(source_path: Path) -> tuple[list[TemplateKey], set[str]]:
    raw_lines = source_path.read_text(encoding="utf-8").splitlines()
    keys: list[TemplateKey] = []
    seen: dict[str, int] = {}
    duplicated: set[str] = set()

    for idx, raw_line in enumerate(raw_lines):
        parsed = parse_template_assignment_line(raw_line, idx + 1)
        if parsed is None:
            continue

        key, value = parsed
        commented = raw_line.strip().startswith("#")
        description = extract_template_description(raw_lines, idx)
        if key in seen:
            existing = keys[seen[key]]
            if existing.commented and not commented:
                keys[seen[key]] = TemplateKey(
                    key=key,
                    value=value,
                    description=description,
                    line_number=idx + 1,
                    commented=commented,
                )
            elif not existing.commented and not commented:
                duplicated.add(key)
            continue
        seen[key] = len(keys)
        keys.append(
            TemplateKey(
                key=key,
                value=value,
                description=description,
                line_number=idx + 1,
                commented=commented,
            )
        )

    if not keys:
        raise ValidationError(f"No KEY=value entries found in template: {source_path}")
    return keys, duplicated


def key_usage_from_render_code() -> set[str]:
    script_path = render_contract_script_path()
    code = script_path.read_text(encoding="utf-8")
    return set(RENDER_KEY_USAGE_PATTERN.findall(code))


def allowed_values_map(render_module: Any) -> dict[str, list[str]]:
    allowed: dict[str, list[str]] = {}

    def sorted_values(name: str) -> list[str]:
        values = getattr(render_module, name, set())
        return sorted(str(item) for item in values)

    allowed["TLS_MODE"] = sorted_values("TLS_MODES")
    allowed["WEB_SERVER_TYPE"] = sorted_values("WEB_SERVER_TYPES")
    allowed["NETWORK_DATABASE_ACCESS_MODE"] = sorted_values("DB_ACCESS_MODES")
    allowed["DATABASE_DEPLOYMENT_MODE"] = sorted_values("DB_DEPLOYMENT_MODES")
    allowed["GLPI_TIMEZONE_DB_MODE"] = sorted_values("GLPI_TIMEZONE_DB_MODES")
    allowed["EXECUTION_MODE"] = sorted_values("EXECUTION_MODES")
    allowed["EXECUTION_HOST_ROLE_DEFAULT"] = sorted_values("HOST_ROLES")
    allowed["TOPOLOGY_MODE"] = sorted_values("TOPOLOGY_MODES")
    allowed["RESOURCE_PROFILE_ACTIVE"] = ["small", "medium", "large"]
    allowed["GLPI_REDIS_SESSION_LOCKING"] = ["0", "1"]
    allowed["MONITORING_PROFILE"] = sorted_values("MONITORING_PROFILES")
    allowed["MONITORING_GRAFANA_PUBLIC_MODE"] = sorted_values("MONITORING_GRAFANA_PUBLIC_MODES")

    bool_keys = set(getattr(render_module, "BOOL_KEYS", set()))
    for key in bool_keys:
        allowed[key] = ["true", "false"]

    return {key: values for key, values in allowed.items() if values}


def derive_description(key: str, template_description: str, required_public_keys: dict[str, Any]) -> str:
    if template_description:
        return template_description
    metadata = required_public_keys.get(key)
    if metadata and isinstance(metadata, dict):
        purpose = str(metadata.get("purpose", "")).strip()
        if purpose:
            return purpose
    return f"Configuração da variável de ambiente {key}."


def key_is_secret(key: str) -> bool:
    if key in EXPLICIT_SECRET_KEYS:
        return True
    upper = key.upper()
    return any(hint in upper for hint in SECRET_NAME_HINTS)


def determine_policy(key: str, secret: bool) -> str:
    if secret:
        return "protected"
    if key in MANAGED_KEYS:
        return "managed"
    if key in REVIEW_REQUIRED_KEYS:
        return "review_required"
    return "protected"


def determine_required(key: str, required_public_keys: dict[str, Any]) -> bool:
    return key in required_public_keys


def should_include_default(key: str, value: str, secret: bool, policy: str) -> bool:
    if not value or secret:
        return False
    if policy == "protected":
        return key in SAFE_DEFAULT_KEYS
    return True


def example_for_key(key: str, value: str) -> str | None:
    upper = key.upper()
    if upper.endswith("_URL"):
        return "https://example.com"
    if "DOMAIN" in upper:
        return "glpi.example.internal"
    if upper.endswith("_HOST"):
        return "192.0.2.10"
    if upper.endswith("_ALIAS"):
        return "app-node"
    if "TIMEZONE" in upper:
        return "America/Sao_Paulo"
    if upper.endswith("_NAME") and "ENVIRONMENT" in upper:
        return "staging"
    if value and KEY_PATTERN.fullmatch(value):
        return value
    return None


def review_details_for_key(key: str) -> dict[str, Any]:
    details = REVIEW_REQUIRED_DETAILS.get(key)
    if details is not None:
        return details
    return {
        "reason": f"Alterar {key} pode exigir revisão operacional do ambiente.",
        "impact": "Configuração incorreta pode causar falha de deploy, indisponibilidade ou regressão.",
        "validation": [
            "Executar pré-checks e validações operacionais após a alteração.",
            "Revisar conectividade e serviços dependentes do valor alterado.",
            "Validar logs e smoke tests no ambiente alvo.",
        ],
    }


def build_rule_entry(
    item: TemplateKey,
    required_public_keys: dict[str, Any],
    allowed_values: dict[str, list[str]],
) -> dict[str, Any]:
    key = item.key
    secret = key_is_secret(key)
    policy = determine_policy(key, secret)
    required = determine_required(key, required_public_keys)
    if key in CONDITIONAL_REQUIRED_REASON:
        required = False

    entry: dict[str, Any] = {
        "description": derive_description(key, item.description, required_public_keys),
        "required": required,
        "policy": policy,
    }

    if policy == "managed":
        entry["auto_apply"] = True

    defaults = item.value.strip()
    if should_include_default(key, defaults, secret, policy):
        entry["default"] = defaults

    if key in allowed_values:
        entry["allowed_values"] = allowed_values[key]

    if secret:
        entry["secret"] = True

    if policy == "review_required":
        details = review_details_for_key(key)
        entry["reason"] = details["reason"]
        entry["impact"] = details["impact"]
        entry["validation"] = details["validation"]
    elif key in CONDITIONAL_REQUIRED_REASON:
        entry["reason"] = CONDITIONAL_REQUIRED_REASON[key]

    if policy == "protected":
        example = example_for_key(key, defaults)
        if example:
            entry["example"] = example

    return entry


def build_generated_rules_document(
    template_items: list[TemplateKey],
    required_public_keys: dict[str, Any],
    allowed_values: dict[str, list[str]],
) -> dict[str, Any]:
    generated_keys: dict[str, Any] = {}
    for item in template_items:
        generated_keys[item.key] = build_rule_entry(
            item=item,
            required_public_keys=required_public_keys,
            allowed_values=allowed_values,
        )
    defaults = dict(DEFAULT_RULES_DEFAULTS)
    # Generated contracts include keys that can stay commented in template.
    defaults["validate_rule_keys_in_source"] = False
    return {
        "version": 1,
        "defaults": defaults,
        "keys": generated_keys,
    }


def validate_generated_rules_document(rules_doc: dict[str, Any], template_keys: list[str]) -> None:
    if rules_doc.get("version") != 1:
        raise ValidationError("Generated contract has invalid version (expected 1).")
    if not isinstance(rules_doc.get("defaults"), dict):
        raise ValidationError("Generated contract has invalid defaults mapping.")
    keys = rules_doc.get("keys")
    if not isinstance(keys, dict) or not keys:
        raise ValidationError("Generated contract has empty or invalid keys mapping.")

    missing_from_contract = sorted(set(template_keys) - set(keys.keys()))
    if missing_from_contract:
        raise ValidationError(
            "Generated contract missing template keys: " + ", ".join(missing_from_contract)
        )

    for key, meta in keys.items():
        if not isinstance(meta, dict):
            raise ValidationError(f"Generated contract key '{key}' is not a mapping.")
        for field in ("description", "required", "policy"):
            if field not in meta:
                raise ValidationError(f"Generated contract key '{key}' missing field: {field}")
        if meta["policy"] not in SUPPORTED_POLICIES:
            raise ValidationError(f"Generated contract key '{key}' has invalid policy: {meta['policy']}")
        if meta["policy"] == "review_required":
            for field in ("reason", "impact", "validation"):
                if field not in meta:
                    raise ValidationError(
                        f"Generated contract key '{key}' missing review field: {field}"
                    )


def analyze_env_files(
    env_files: list[Path],
    template_keys: set[str],
) -> tuple[dict[str, list[str]], dict[str, list[str]], dict[str, list[str]], dict[str, list[str]], set[str]]:
    extras_by_env: dict[str, list[str]] = {}
    missing_by_env: dict[str, list[str]] = {}
    duplicates_by_env: dict[str, list[str]] = {}
    values_by_key: dict[str, list[str]] = {}
    env_extra_keys: set[str] = set()

    for env_path in env_files:
        parsed = parse_env_file(env_path, f"environment {env_path.name}")
        all_keys = set(parsed.values.keys()) | parsed.duplicates
        extras = sorted(all_keys - template_keys)
        missing = sorted(template_keys - set(parsed.values.keys()))
        duplicates = sorted(parsed.duplicates)

        extras_by_env[env_path.name] = extras
        missing_by_env[env_path.name] = missing
        duplicates_by_env[env_path.name] = duplicates
        env_extra_keys.update(extras)

        for key, value in parsed.values.items():
            if value == "":
                continue
            values_by_key.setdefault(key, [])
            if value not in values_by_key[key]:
                values_by_key[key].append(value)

    return extras_by_env, missing_by_env, duplicates_by_env, values_by_key, env_extra_keys


def detect_value_variations(values_by_key: dict[str, list[str]]) -> list[str]:
    return sorted([key for key, values in values_by_key.items() if len(values) > 1])


def run_post_check(
    source_path: Path,
    target_path: Path,
    rules_path: Path,
    verbose: bool,
) -> PostCheckResult:
    if not target_path.exists():
        return PostCheckResult(
            target=target_path,
            exists=False,
            exit_code=EXIT_SUCCESS,
            summary="target-not-found",
        )

    rules = load_rules(rules_path)
    source = parse_env_file(source_path, "source")
    target = parse_env_file(target_path, "target")
    # Post-checks operate over keys that are active in source. This keeps
    # compatibility with templates where optional keys remain commented.
    only_active_keys = set(source.values.keys())
    plan = build_sync_plan(
        source=source,
        target=target,
        rules=rules,
        mode="report",
        only_keys=only_active_keys,
        allow_managed=False,
        force_reviewed=set(),
        verbose=verbose,
    )
    exit_code = compute_exit_code(plan)
    summary = (
        f"code={exit_code}; missing={len(plan.required_missing)}; review_required="
        f"{len([item for item in plan.review_required if not item.get('forced')])}; "
        f"validation_errors={len(plan.validation_errors)}; extras={len(plan.extra_in_target)}; "
        f"ambiguous={len(plan.ambiguous)}"
    )
    return PostCheckResult(
        target=target_path,
        exists=True,
        exit_code=exit_code,
        summary=summary,
        missing_keys=sorted(item["key"] for item in plan.required_missing),
        review_required_keys=sorted(
            item["key"] for item in plan.review_required if not item.get("forced")
        ),
        extra_keys=sorted(item["key"] for item in plan.extra_in_target),
        ambiguous_keys=sorted(item["key"] for item in plan.ambiguous),
        validation_errors=list(plan.validation_errors),
    )


def write_yaml_file(path: Path, data: dict[str, Any]) -> None:
    yaml = load_yaml_module()
    try:
        if path.parent != Path("."):
            path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(yaml.safe_dump(data, sort_keys=False, allow_unicode=True), encoding="utf-8")
    except OSError as exc:
        raise PermissionErrorSync(f"Unable to write YAML file: {path}") from exc


def publish_generated_contract(source_path: Path, publish_path: Path) -> None:
    try:
        shutil.copy2(source_path, publish_path)
    except OSError as exc:
        raise PermissionErrorSync(f"Unable to publish generated contract to: {publish_path}") from exc


def render_generate_report(
    source_template: Path,
    generated_output: Path,
    published_output: Path | None,
    env_files: list[Path],
    rules_doc: dict[str, Any],
    sensitive_keys: list[str],
    review_required_keys: list[str],
    missing_in_template_from_code: list[str],
    extras_by_env: dict[str, list[str]],
    missing_by_env: dict[str, list[str]],
    duplicates_by_env: dict[str, list[str]],
    duplicate_in_template: set[str],
    varying_keys: list[str],
    env_extra_keys_used_by_code: list[str],
    env_extra_keys_without_usage: list[str],
    post_checks: list[PostCheckResult],
) -> str:
    policy_counts = {"protected": 0, "managed": 0, "review_required": 0, "deprecated": 0}
    for item in rules_doc["keys"].values():
        policy_counts[item["policy"]] += 1

    lines: list[str] = [
        "# Relatório do contrato de ambiente",
        "",
        "## Fonte oficial",
        "",
        f"- `{source_template}`",
        "",
        "## Arquivos reais analisados",
        "",
    ]
    if env_files:
        for env_path in env_files:
            lines.append(f"- `{env_path}`")
    else:
        lines.append("- Nenhum `config/<ambiente>.env` encontrado.")

    lines.extend(
        [
            "",
            "## Arquivos criados/atualizados",
            "",
            f"- `{generated_output}`",
        ]
    )
    if published_output is not None:
        lines.append(f"- `{published_output}`")

    lines.extend(
        [
            "",
            "## Quantidade de variáveis",
            "",
            f"- total no template oficial: {len(rules_doc['keys'])}",
            f"- total no contrato gerado: {len(rules_doc['keys'])}",
            f"- protected: {policy_counts['protected']}",
            f"- managed: {policy_counts['managed']}",
            f"- review_required: {policy_counts['review_required']}",
            f"- deprecated: {policy_counts['deprecated']}",
            f"- secret: {len(sensitive_keys)}",
            "",
            "## Variáveis sensíveis identificadas",
            "",
        ]
    )

    if sensitive_keys:
        lines.extend([f"- `{key}`" for key in sensitive_keys])
    else:
        lines.append("- Nenhuma.")

    lines.extend(["", "## Variáveis com revisão manual", ""])
    if review_required_keys:
        lines.extend([f"- `{key}`" for key in review_required_keys])
    else:
        lines.append("- Nenhuma.")

    lines.extend(["", "## Ambiguidades", ""])
    if duplicate_in_template:
        lines.append("- Duplicidades no template oficial:")
        lines.extend([f"  - `{key}`" for key in sorted(duplicate_in_template)])
    else:
        lines.append("- Duplicidades no template oficial: nenhuma.")

    if missing_in_template_from_code:
        lines.append("- Variáveis usadas no código e ausentes no template:")
        lines.extend([f"  - `{key}`" for key in missing_in_template_from_code])
    else:
        lines.append("- Variáveis usadas no código e ausentes no template: nenhuma.")

    if env_extra_keys_used_by_code:
        lines.append("- Variáveis extras em ambientes e com uso detectado no código:")
        lines.extend([f"  - `{key}`" for key in env_extra_keys_used_by_code])
    else:
        lines.append("- Variáveis extras em ambientes e com uso detectado no código: nenhuma.")

    if env_extra_keys_without_usage:
        lines.append("- Variáveis extras em ambientes sem uso claro no código (candidatas a deprecated):")
        lines.extend([f"  - `{key}`" for key in env_extra_keys_without_usage])
    else:
        lines.append("- Variáveis extras em ambientes sem uso claro no código: nenhuma.")

    has_env_ambiguous = False
    for env_name, extras in extras_by_env.items():
        duplicates = duplicates_by_env.get(env_name, [])
        if extras or duplicates:
            has_env_ambiguous = True
            lines.append(f"- `{env_name}`:")
            if extras:
                lines.append("  - extras ausentes no template:")
                lines.extend([f"    - `{key}`" for key in extras])
            if duplicates:
                lines.append("  - chaves duplicadas:")
                lines.extend([f"    - `{key}`" for key in duplicates])
    if not has_env_ambiguous:
        lines.append("- Sem ambiguidades por arquivo de ambiente.")

    if varying_keys:
        lines.append("- Chaves com variação de valor entre ambientes:")
        lines.extend([f"  - `{key}`" for key in varying_keys])
    else:
        lines.append("- Chaves com variação de valor entre ambientes: nenhuma detectada.")

    lines.extend(["", "## Cobertura por ambiente", ""])
    if env_files:
        for env_path in env_files:
            missing = missing_by_env.get(env_path.name, [])
            lines.append(f"- `{env_path.name}`: {len(missing)} chaves do template ausentes.")
    else:
        lines.append("- Não aplicável (nenhum ambiente real disponível).")

    lines.extend(["", "## Pós-geração: env-sync report", ""])
    for item in post_checks:
        if not item.exists:
            lines.append(f"- `{item.target}`: target não encontrado.")
            continue
        lines.append(f"- `{item.target}`: {item.summary}")
        if item.missing_keys:
            lines.append("  - required missing keys:")
            lines.extend([f"    - `{key}`" for key in item.missing_keys])
        if item.review_required_keys:
            lines.append("  - review_required keys:")
            lines.extend([f"    - `{key}`" for key in item.review_required_keys])
        if item.extra_keys:
            lines.append("  - extra keys:")
            lines.extend([f"    - `{key}`" for key in item.extra_keys])
        if item.ambiguous_keys:
            lines.append("  - ambiguous keys:")
            lines.extend([f"    - `{key}`" for key in item.ambiguous_keys])
        if item.validation_errors:
            lines.append("  - validation errors:")
            lines.extend([f"    - {message}" for message in item.validation_errors])

    lines.extend(
        [
            "",
            "## Validações executadas",
            "",
            "- Validação estrutural do YAML gerado (campos obrigatórios e políticas permitidas): OK.",
            "- Cobertura de chaves do template no contrato gerado: OK.",
            "- Pós-checks `env-sync` em modo report: executado para template oficial e ambientes encontrados.",
        ]
    )

    return "\n".join(lines) + "\n"

def load_rules(path: Path) -> RulesConfig:
    yaml = load_yaml_module()

    ensure_readable_file(path, "rules")
    try:
        loaded = yaml.safe_load(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise ValidationError(f"Invalid YAML in rules file: {path}") from exc

    if loaded is None:
        raise ValidationError("Rules file is empty.")
    if not isinstance(loaded, dict):
        raise ValidationError("Rules file root must be a mapping.")

    if "version" not in loaded:
        raise ValidationError("Rules file must define 'version'.")
    version = loaded["version"]
    if version != 1:
        raise ValidationError(f"Unsupported rules version: {version}")

    raw_defaults = loaded.get("defaults") or {}
    if not isinstance(raw_defaults, dict):
        raise ValidationError("'defaults' must be a mapping when provided.")

    defaults: dict[str, Any] = dict(DEFAULT_RULES_DEFAULTS)
    defaults.update(raw_defaults)

    keys = loaded.get("keys")
    if not isinstance(keys, dict) or not keys:
        raise ValidationError("Rules file must define non-empty 'keys' mapping.")

    parsed_keys: dict[str, KeyRule] = {}
    errors: list[str] = []

    for key, spec in keys.items():
        if not isinstance(spec, dict):
            errors.append(f"Rule '{key}' must be a mapping.")
            continue

        missing_fields = [field for field in ("description", "required", "policy") if field not in spec]
        if missing_fields:
            errors.append(f"Rule '{key}' is missing fields: {', '.join(missing_fields)}")
            continue

        policy = str(spec.get("policy"))
        if policy not in SUPPORTED_POLICIES:
            errors.append(f"Rule '{key}' has unsupported policy: {policy}")

        required = spec.get("required")
        if not isinstance(required, bool):
            errors.append(f"Rule '{key}' field 'required' must be boolean.")

        allowed_values = spec.get("allowed_values")
        if allowed_values is not None and not isinstance(allowed_values, list):
            errors.append(f"Rule '{key}' field 'allowed_values' must be a list.")

        validation = spec.get("validation")
        if validation is not None and not isinstance(validation, list):
            errors.append(f"Rule '{key}' field 'validation' must be a list.")

        auto_apply = spec.get("auto_apply", False)
        if not isinstance(auto_apply, bool):
            errors.append(f"Rule '{key}' field 'auto_apply' must be boolean when provided.")
            auto_apply = False

        secret = spec.get("secret", False)
        if not isinstance(secret, bool):
            errors.append(f"Rule '{key}' field 'secret' must be boolean when provided.")
            secret = False

        if errors:
            # Continue collecting as many validation errors as possible.
            pass

        parsed_keys[key] = KeyRule(
            description=str(spec.get("description", "")),
            required=bool(spec.get("required", False)),
            policy=policy,
            auto_apply=auto_apply,
            default=normalize_rule_value(spec["default"])
            if "default" in spec and spec["default"] is not None
            else None,
            allowed_values=[normalize_rule_value(item) for item in allowed_values]
            if isinstance(allowed_values, list)
            else None,
            secret=secret,
            reason=str(spec["reason"]) if spec.get("reason") is not None else None,
            impact=str(spec["impact"]) if spec.get("impact") is not None else None,
            validation=[str(item) for item in validation] if isinstance(validation, list) else None,
        )

    if errors:
        joined = "\n".join(f"- {item}" for item in errors)
        raise ValidationError(f"Invalid rules file:\n{joined}")

    return RulesConfig(version=1, defaults=defaults, keys=parsed_keys)


def parse_env_file(path: Path, label: str) -> ParsedEnv:
    ensure_readable_file(path, label)
    try:
        raw_text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError as exc:
        raise ValidationError(f"{label} file must be UTF-8 encoded: {path}") from exc

    trailing_newline = raw_text.endswith("\n")
    raw_lines = raw_text.splitlines()

    parsed_lines: list[EnvLine] = []
    key_occurrences: dict[str, list[int]] = {}
    commented_key_occurrences: dict[str, list[int]] = {}
    key_order: list[str] = []
    key_order_seen: set[str] = set()

    for number, line in enumerate(raw_lines, start=1):
        parsed = parse_env_line(line, number)
        parsed_lines.append(parsed)
        if parsed.line_type == "key_value" and parsed.key is not None:
            key_occurrences.setdefault(parsed.key, []).append(len(parsed_lines) - 1)
        elif parsed.line_type == "commented_key_value" and parsed.key is not None:
            commented_key_occurrences.setdefault(parsed.key, []).append(len(parsed_lines) - 1)

        if parsed.key is not None and parsed.line_type in {"key_value", "commented_key_value"}:
            if parsed.key not in key_order_seen:
                key_order_seen.add(parsed.key)
                key_order.append(parsed.key)

    duplicates = {key for key, indices in key_occurrences.items() if len(indices) > 1}
    key_indices = {key: indices[0] for key, indices in key_occurrences.items() if len(indices) == 1}
    values = {key: parsed_lines[index].value or "" for key, index in key_indices.items()}
    commented_key_indices = {
        key: indices[0]
        for key, indices in commented_key_occurrences.items()
        if key not in key_indices
    }
    commented_values = {
        key: parsed_lines[index].value or ""
        for key, index in commented_key_indices.items()
    }

    return ParsedEnv(
        path=path,
        lines=parsed_lines,
        trailing_newline=trailing_newline,
        key_indices=key_indices,
        values=values,
        duplicates=duplicates,
        commented_key_indices=commented_key_indices,
        commented_values=commented_values,
        key_order=key_order,
    )


def parse_env_line(line: str, line_number: int) -> EnvLine:
    stripped = line.strip()
    if stripped == "":
        return EnvLine("empty", line, line_number)
    if line.lstrip().startswith("#"):
        commented = parse_commented_assignment_line(line, line_number)
        if commented is not None:
            return commented
        return EnvLine("comment", line, line_number)

    if "=" not in line:
        return EnvLine("raw", line, line_number)

    left, right = line.split("=", 1)
    key = left.strip()
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key):
        return EnvLine("raw", line, line_number)

    ws_prefix_len = len(right) - len(right.lstrip(" \t"))
    ws_prefix = right[:ws_prefix_len]
    rhs = right[ws_prefix_len:]

    if rhs.startswith("'"):
        value, suffix = parse_single_quoted(rhs)
        quote_style = "single"
    elif rhs.startswith('"'):
        value, suffix = parse_double_quoted(rhs)
        quote_style = "double"
    else:
        value, suffix = parse_unquoted(rhs)
        quote_style = "none"

    return EnvLine(
        line_type="key_value",
        original_line=line,
        line_number=line_number,
        key=key,
        value=value,
        prefix=f"{left}={ws_prefix}",
        suffix=suffix,
        quote_style=quote_style,
    )


def parse_commented_assignment_line(line: str, line_number: int) -> EnvLine | None:
    leading_len = len(line) - len(line.lstrip(" \t"))
    leading = line[:leading_len]
    after_hash = line[leading_len + 1 :]
    after_hash_ws_len = len(after_hash) - len(after_hash.lstrip(" \t"))
    after_hash_ws = after_hash[:after_hash_ws_len]
    candidate = after_hash[after_hash_ws_len:]

    if "=" not in candidate:
        return None

    parsed = parse_env_line(candidate, line_number)
    if parsed.line_type != "key_value" or parsed.key is None:
        return None

    return EnvLine(
        line_type="commented_key_value",
        original_line=line,
        line_number=line_number,
        key=parsed.key,
        value=parsed.value,
        prefix=f"{leading}#{after_hash_ws}{parsed.prefix}",
        suffix=parsed.suffix,
        quote_style=parsed.quote_style,
    )


def parse_single_quoted(raw: str) -> tuple[str, str]:
    closing = raw.find("'", 1)
    if closing == -1:
        return raw[1:], ""
    token = raw[: closing + 1]
    suffix = raw[closing + 1 :]
    return token[1:-1], suffix


def parse_double_quoted(raw: str) -> tuple[str, str]:
    escaped = False
    closing = -1
    for idx in range(1, len(raw)):
        char = raw[idx]
        if escaped:
            escaped = False
            continue
        if char == "\\":
            escaped = True
            continue
        if char == '"':
            closing = idx
            break

    if closing == -1:
        token = raw[1:]
        suffix = ""
    else:
        token = raw[1:closing]
        suffix = raw[closing + 1 :]
    return decode_escaped(token), suffix


def decode_escaped(value: str) -> str:
    out: list[str] = []
    escaped = False
    for char in value:
        if escaped:
            out.append({"n": "\n", "r": "\r", "t": "\t", "\\": "\\", '"': '"'}.get(char, char))
            escaped = False
            continue
        if char == "\\":
            escaped = True
            continue
        out.append(char)
    if escaped:
        out.append("\\")
    return "".join(out)


def parse_unquoted(raw: str) -> tuple[str, str]:
    comment_idx = None
    for idx, char in enumerate(raw):
        if char == "#" and idx > 0 and raw[idx - 1].isspace():
            comment_idx = idx
            break

    if comment_idx is None:
        return raw.strip(), ""

    before = raw[:comment_idx]
    trailing_ws = before[len(before.rstrip(" \t")) :]
    value = before.strip()
    suffix = f"{trailing_ws}{raw[comment_idx:]}"
    return value, suffix


def is_secret_key(key: str, rule: KeyRule | None) -> bool:
    if rule is not None and rule.secret:
        return True
    upper = key.upper()
    return any(hint in upper for hint in SECRET_NAME_HINTS)


def mask_value(key: str, value: str, rule: KeyRule | None) -> str:
    if is_secret_key(key, rule):
        return SECRET_MASK
    return value


def choose_missing_value(key: str, source_value: str, rule: KeyRule) -> str:
    if is_secret_key(key, rule):
        if rule.default in (None, ""):
            return ""
        # Conservative behavior: secret defaults are only considered safe when explicitly empty.
        return ""

    if source_value != "":
        return source_value
    if rule.default is not None:
        return rule.default
    return ""


def can_apply_managed(rule: KeyRule, allow_managed: bool, defaults: dict[str, Any]) -> bool:
    if rule.policy != "managed":
        return False
    if not rule.auto_apply:
        return False
    return bool(allow_managed or defaults.get("apply_managed_changes") is True)


def known_env_keys(parsed: ParsedEnv) -> set[str]:
    return set(parsed.values.keys()) | set(parsed.commented_values.keys()) | parsed.duplicates


def active_env_keys(parsed: ParsedEnv) -> set[str]:
    return set(parsed.values.keys()) | parsed.duplicates


def contract_value(parsed: ParsedEnv, key: str) -> str | None:
    if key in parsed.values:
        return parsed.values[key]
    return parsed.commented_values.get(key)


def source_order_index(parsed: ParsedEnv) -> dict[str, int]:
    return {key: index for index, key in enumerate(parsed.key_order)}


def sort_by_env_order(keys: Iterable[str], parsed: ParsedEnv) -> list[str]:
    order = source_order_index(parsed)
    return sorted(keys, key=lambda key: (order.get(key, len(order)), key))


def build_sync_plan(
    source: ParsedEnv,
    target: ParsedEnv,
    rules: RulesConfig,
    mode: str,
    only_keys: set[str],
    allow_managed: bool,
    force_reviewed: set[str],
    verbose: bool,
) -> SyncPlan:
    validation_errors: list[str] = []
    ambiguous: list[dict[str, Any]] = []
    added: list[dict[str, Any]] = []
    changed: list[dict[str, Any]] = []
    kept_target_values: list[dict[str, Any]] = []
    preserved_protected: list[dict[str, Any]] = []
    review_required: list[dict[str, Any]] = []
    required_missing: list[dict[str, Any]] = []
    extra_in_target: list[dict[str, Any]] = []
    deprecated: list[dict[str, Any]] = []

    updates: dict[str, str] = {}
    additions: list[tuple[str, str]] = []
    removals: list[str] = []
    applied_changes = 0
    ok_count = 0

    source_keys_all = known_env_keys(source)
    target_active_keys = active_env_keys(target)

    if only_keys:
        unknown_only = sorted([key for key in only_keys if key not in source_keys_all])
        for key in unknown_only:
            validation_errors.append(f"Key from --only not found in source: {key}")
        keys_to_process = sort_by_env_order(
            [key for key in only_keys if key in source_keys_all],
            source,
        )
    else:
        keys_to_process = sort_by_env_order(source_keys_all, source)

    scope_for_global_checks = set(keys_to_process) if only_keys else source_keys_all

    for key in sorted(source.duplicates):
        if key in scope_for_global_checks:
            ambiguous.append({"key": key, "reason": "duplicated in source"})

    for key in sorted(target.duplicates):
        if (not only_keys) or (key in scope_for_global_checks):
            ambiguous.append({"key": key, "reason": "duplicated in target"})

    for key in sorted(source.values.keys()):
        if key in scope_for_global_checks and key not in rules.keys:
            ambiguous.append({"key": key, "reason": "no rule in .env.sync.yml"})

    validate_rule_keys_in_source = bool(rules.defaults.get("validate_rule_keys_in_source", True))
    if not only_keys and validate_rule_keys_in_source:
        for key in sorted(rules.keys.keys()):
            if key not in source_keys_all:
                validation_errors.append(f"Rule key '{key}' not found in source file.")

    if force_reviewed:
        for key in sorted(force_reviewed):
            if key not in rules.keys:
                validation_errors.append(f"Key from --force-reviewed not found in rules: {key}")
                continue
            if rules.keys[key].policy != "review_required":
                validation_errors.append(
                    f"Key from --force-reviewed is not review_required: {key}"
                )

    add_missing = bool(rules.defaults.get("add_missing", True))

    for key in keys_to_process:
        if key in source.duplicates or key in target.duplicates:
            continue

        source_value = contract_value(source, key)
        if source_value is None:
            continue

        rule = rules.keys.get(key)
        if rule is None:
            continue

        target_has_key = key in target.values
        target_value = target.values.get(key, "")
        target_missing_or_empty = not target_has_key or (rule.required and target_value == "")

        if rule.required and target_missing_or_empty:
            required_missing.append({"key": key})

        if target_has_key and rule.allowed_values and target_value not in rule.allowed_values and target_value != "":
            allowed = ", ".join(rule.allowed_values)
            validation_errors.append(
                f"{key} has invalid value in target: {mask_value(key, target_value, rule)} (allowed: {allowed})"
            )

        if target_missing_or_empty:
            should_consider_missing = key in source.values or rule.required or rule.policy == "review_required"
            if add_missing and should_consider_missing:
                new_value = choose_missing_value(key, source_value, rule)
                should_apply = False
                apply_reason = "report mode"

                if mode == "apply":
                    if rule.policy == "deprecated":
                        apply_reason = "deprecated key is not auto-added"
                    elif new_value == "":
                        apply_reason = "missing key has no non-empty source/default value"
                    else:
                        should_apply = True
                        apply_reason = "missing key added from source"

                if rule.allowed_values and new_value not in ("", *rule.allowed_values):
                    allowed = ", ".join(rule.allowed_values)
                    validation_errors.append(
                        f"{key} has invalid value for add: {mask_value(key, new_value, rule)} (allowed: {allowed})"
                    )
                    should_apply = False

                added.append(
                    {
                        "key": key,
                        "value": new_value,
                        "applied": should_apply,
                        "reason": apply_reason,
                    }
                )

                if should_apply:
                    if target_has_key:
                        updates[key] = new_value
                    else:
                        additions.append((key, new_value))
                    applied_changes += 1
            continue

        if source_value == target_value:
            ok_count += 1
            if rule.policy == "deprecated":
                deprecated.append({"key": key, "reason": "deprecated key present"})
            continue

        if rule.policy == "protected":
            kept_target_values.append(
                {
                    "key": key,
                    "current": target_value,
                    "incoming": source_value,
                    "policy": rule.policy,
                }
            )
            continue

        if rule.policy == "managed":
            reason = "environment value preserved"
            if rule.allowed_values and source_value not in rule.allowed_values:
                allowed = ", ".join(rule.allowed_values)
                validation_errors.append(
                    f"{key} has invalid source value: {mask_value(key, source_value, rule)} (allowed: {allowed})"
                )
                reason = "invalid source value"

            kept_target_values.append(
                {
                    "key": key,
                    "current": target_value,
                    "incoming": source_value,
                    "reason": reason,
                    "policy": "managed",
                }
            )
            continue

        if rule.policy == "review_required":
            if rule.allowed_values and source_value not in rule.allowed_values:
                allowed = ", ".join(rule.allowed_values)
                validation_errors.append(
                    f"{key} has invalid source value: {mask_value(key, source_value, rule)} (allowed: {allowed})"
                )

            kept_target_values.append(
                {
                    "key": key,
                    "current": target_value,
                    "incoming": source_value,
                    "policy": "review_required",
                }
            )
            continue

        if rule.policy == "deprecated":
            deprecated.append(
                {
                    "key": key,
                    "reason": "deprecated key differs and must be reviewed manually",
                }
            )
            continue

    if not only_keys:
        for key in sorted(target_active_keys):
            if key in source_keys_all:
                continue

            rule = rules.keys.get(key)
            applied = mode == "apply"
            extra_in_target.append(
                {
                    "key": key,
                    "applied": applied,
                    "action": "remove" if applied else "remove on apply",
                    "reason": "key absent from source contract",
                }
            )
            if applied:
                applied_changes += 1
                removals.append(key)
            if rule and rule.policy == "deprecated":
                deprecated.append({"key": key, "reason": "deprecated extra key in target"})

    applied_missing_keys = {key for key, _value in additions} | set(updates.keys())
    if applied_missing_keys:
        required_missing = [item for item in required_missing if item["key"] not in applied_missing_keys]

    if verbose and not keys_to_process:
        validation_errors.append("No keys available to process after filters.")

    return SyncPlan(
        mode=mode,
        added=added,
        changed=changed,
        kept_target_values=kept_target_values,
        preserved_protected=preserved_protected,
        review_required=review_required,
        required_missing=required_missing,
        extra_in_target=extra_in_target,
        deprecated=deprecated,
        ambiguous=ambiguous,
        validation_errors=validation_errors,
        ok_count=ok_count,
        applied_changes=applied_changes,
        updates=updates,
        additions=additions,
        removals=removals,
        source_key_order=source.key_order,
    )


def collect_divergent_keys(
    source: ParsedEnv,
    target: ParsedEnv,
    rules: RulesConfig,
    only_keys: set[str],
) -> list[tuple[str, str, str, str]]:
    source_keys = set(source.values.keys())
    target_keys = set(target.values.keys())
    scope = set(only_keys) if only_keys else (source_keys & target_keys)

    divergences: list[tuple[str, str, str, str]] = []
    for key in sorted(scope):
        if key in source.duplicates or key in target.duplicates:
            continue
        rule = rules.keys.get(key)
        if rule is None:
            continue
        source_value = source.values.get(key)
        target_value = target.values.get(key)
        if source_value is None or target_value is None:
            continue
        if source_value == target_value:
            continue
        divergences.append((key, source_value, target_value, rule.policy))
    return divergences


def prompt_reconcile_choice(
    key: str,
    source_value: str,
    target_value: str,
    rule: KeyRule,
) -> str:
    masked_source = mask_value(key, source_value, rule)
    masked_target = mask_value(key, target_value, rule)

    print("")
    print(f"[RECONCILE] Divergence detected for '{key}'")
    print(f"  source (.env.example): {masked_source}")
    print(f"  target (environment): {masked_target}")

    while True:
        try:
            answer = input("  Keep which value in target? [s=source/t=target]: ").strip().lower()
        except EOFError as exc:
            raise ValidationError(
                f"Interactive input required for key '{key}' in --reconcile-interactive mode."
            ) from exc

        if answer in {"s", "source"}:
            return "source"
        if answer in {"t", "target"}:
            return "target"
        print("  Invalid choice. Use 's' (source) or 't' (target).")


def apply_reconcile_interactive(
    plan: SyncPlan,
    source: ParsedEnv,
    target: ParsedEnv,
    rules: RulesConfig,
    only_keys: set[str],
    extra_action: str,
) -> None:
    if plan.validation_errors:
        raise ValidationError("Cannot start interactive reconcile with validation errors in current plan.")

    additions_index = {key: idx for idx, (key, _value) in enumerate(plan.additions)}
    for item in plan.added:
        key = item["key"]
        value = source.values.get(key, item["value"])
        item["value"] = value
        if key in additions_index:
            index = additions_index[key]
            plan.additions[index] = (key, value)
        else:
            plan.additions.append((key, value))
            plan.applied_changes += 1
            additions_index[key] = len(plan.additions) - 1
        item["applied"] = True
        item["reason"] = "reconcile: missing key added from source"

    if additions_index:
        plan.required_missing = [item for item in plan.required_missing if item["key"] not in additions_index]

    divergence_choices: dict[str, str] = {}
    for key, source_value, target_value, _policy in collect_divergent_keys(source, target, rules, only_keys):
        rule = rules.keys[key]
        choice = prompt_reconcile_choice(
            key=key,
            source_value=source_value,
            target_value=target_value,
            rule=rule,
        )
        divergence_choices[key] = choice
        if choice == "source":
            if key not in plan.updates:
                plan.applied_changes += 1
            plan.updates[key] = source_value
            found_change = False
            for changed in plan.changed:
                if changed["key"] == key:
                    changed["applied"] = True
                    changed["reason"] = "reconcile: chose source value"
                    found_change = True
                    break
            if not found_change:
                plan.changed.append(
                    {
                        "key": key,
                        "from": target_value,
                        "to": source_value,
                        "applied": True,
                        "reason": "reconcile: chose source value",
                        "policy": rule.policy,
                    }
                )
        else:
            if key in plan.updates:
                del plan.updates[key]
                if plan.applied_changes > 0:
                    plan.applied_changes -= 1
            found_change = False
            for changed in plan.changed:
                if changed["key"] == key:
                    changed["applied"] = False
                    changed["reason"] = "reconcile: kept target value"
                    found_change = True
                    break
            if not found_change:
                plan.changed.append(
                    {
                        "key": key,
                        "from": target_value,
                        "to": source_value,
                        "applied": False,
                        "reason": "reconcile: kept target value",
                        "policy": rule.policy,
                    }
                )

    if divergence_choices:
        chosen_keys = set(divergence_choices.keys())
        plan.preserved_protected = [item for item in plan.preserved_protected if item["key"] not in chosen_keys]
        plan.review_required = [item for item in plan.review_required if item["key"] not in chosen_keys]
        plan.kept_target_values = [
            item for item in plan.kept_target_values if item["key"] not in chosen_keys
        ]

    if plan.extra_in_target:
        for item in plan.extra_in_target:
            was_applied = bool(item.get("applied"))
            item["applied"] = True
            item["action"] = extra_action
            item["reason"] = f"reconcile: {extra_action} key absent from source"
            if item["key"] not in plan.removals:
                plan.removals.append(item["key"])
            if not was_applied:
                plan.applied_changes += 1


def render_value_for_line(value: str, quote_style: str) -> str:
    if quote_style == "single" and "'" not in value:
        return f"'{value}'"
    if quote_style == "double":
        return '"' + escape_double(value) + '"'
    return render_value_for_new_key(value)


def render_value_for_new_key(value: str) -> str:
    if value == "":
        return ""

    safe = re.fullmatch(r"[A-Za-z0-9_./:=@+-]+", value)
    if safe:
        return value
    return '"' + escape_double(value) + '"'


def escape_double(value: str) -> str:
    return (
        value.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t")
    )


def render_assignment_line(key: str, value: str) -> str:
    return f"{key}={render_value_for_new_key(value)}"


def target_insertion_start(target: ParsedEnv, output_lines: list[str | None], index: int) -> int:
    cursor = index
    while cursor > 0:
        previous = target.lines[cursor - 1]
        if output_lines[cursor - 1] is None or previous.line_type != "comment":
            break
        cursor -= 1
    return cursor


def insertion_index_for_addition(
    key: str,
    target: ParsedEnv,
    output_lines: list[str | None],
    source_order: dict[str, int],
) -> int | None:
    key_order = source_order.get(key)
    if key_order is None:
        return None

    for index, line in enumerate(target.lines):
        if output_lines[index] is None:
            continue
        if line.line_type not in {"key_value", "commented_key_value"} or line.key is None:
            continue
        line_order = source_order.get(line.key)
        if line_order is not None and line_order > key_order:
            return target_insertion_start(target, output_lines, index)
    return None


def apply_changes_to_target(target: ParsedEnv, plan: SyncPlan) -> str:
    output_lines: list[str | None] = [line.original_line for line in target.lines]

    for key, new_value in plan.updates.items():
        index = target.key_indices[key]
        line = target.lines[index]
        if line.prefix is None:
            continue
        rendered = render_value_for_line(new_value, line.quote_style)
        output_lines[index] = f"{line.prefix}{rendered}{line.suffix}"

    for item in plan.extra_in_target:
        if not item.get("applied"):
            continue
        action = item.get("action")
        if action not in {"comment", "remove"}:
            continue
        key = item["key"]
        for index, line in enumerate(target.lines):
            if line.line_type != "key_value" or line.key != key:
                continue
            current = output_lines[index]
            if current is None:
                continue
            if action == "comment":
                output_lines[index] = f"# Removed by env-sync (not in source): {current}"
            else:
                output_lines[index] = None

    source_order = {key: index for index, key in enumerate(plan.source_key_order)}
    additions_to_insert: list[tuple[str, str]] = []
    if plan.additions:
        for key, value in plan.additions:
            if key in target.commented_key_indices:
                index = target.commented_key_indices[key]
                output_lines[index] = render_assignment_line(key, value)
                continue
            additions_to_insert.append((key, value))

    insertion_map: dict[int, list[str]] = {}
    append_lines: list[str] = []
    for key, value in sorted(
        additions_to_insert,
        key=lambda item: (source_order.get(item[0], len(source_order)), item[0]),
    ):
        rendered = render_assignment_line(key, value)
        insertion_index = insertion_index_for_addition(key, target, output_lines, source_order)
        if insertion_index is None:
            append_lines.append(rendered)
        else:
            insertion_map.setdefault(insertion_index, []).append(rendered)

    output_lines_compact: list[str] = []
    for index, line in enumerate(output_lines):
        output_lines_compact.extend(insertion_map.get(index, []))
        if line is not None:
            output_lines_compact.append(line)

    if append_lines:
        if output_lines_compact and output_lines_compact[-1].strip() != "":
            output_lines_compact.append("")
        output_lines_compact.extend(append_lines)

    rendered_text = "\n".join(output_lines_compact)
    if target.trailing_newline:
        rendered_text += "\n"
    return rendered_text


def create_backup(target_path: Path, backup_dir: Path) -> Path:
    try:
        backup_dir.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        raise PermissionErrorSync(f"Unable to create backup directory: {backup_dir}") from exc

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_file = backup_dir / f"{target_path.name}.backup.{stamp}"

    try:
        shutil.copy2(target_path, backup_file)
    except OSError as exc:
        raise PermissionErrorSync(f"Unable to create backup file: {backup_file}") from exc

    return backup_file


def write_atomic(target_path: Path, content: str) -> None:
    temp_fd = None
    temp_path = None
    try:
        temp_fd, temp_path = tempfile.mkstemp(prefix=f".{target_path.name}.", dir=str(target_path.parent))
        with os.fdopen(temp_fd, "w", encoding="utf-8") as handle:
            handle.write(content)
        temp_fd = None

        original_mode = target_path.stat().st_mode & 0o777
        os.chmod(temp_path, original_mode)
        os.replace(temp_path, target_path)
        temp_path = None
    except OSError as exc:
        raise PermissionErrorSync(f"Unable to write target file: {target_path}") from exc
    finally:
        if temp_fd is not None:
            try:
                os.close(temp_fd)
            except OSError:
                pass
        if temp_path is not None:
            try:
                os.unlink(temp_path)
            except OSError:
                pass


def render_report(
    plan: SyncPlan,
    source_path: Path,
    target_path: Path,
    rules_path: Path,
    rules: RulesConfig,
    use_color: bool,
    verbose: bool,
) -> str:
    painter = ReportBuilder(use_color=use_color)
    lines: list[str] = []

    lines.append("ENV SYNC REPORT")
    lines.append("")
    lines.append("SOURCE:")
    lines.append(str(source_path))
    lines.append("")
    lines.append("TARGET:")
    lines.append(str(target_path))
    lines.append("")
    lines.append("RULES:")
    lines.append(str(rules_path))
    lines.append("")
    lines.append("MODE:")
    lines.append(plan.mode)

    append_section(lines, "ADDED", [
        f"+ {item['key']}={mask_value(item['key'], item['value'], rules.keys.get(item['key']))}"
        + ("" if item.get("applied") or plan.mode == "report" else f" (not applied: {item.get('reason')})")
        for item in plan.added
    ])

    append_section(lines, "CHANGED", [
        f"~ {item['key']}: {mask_value(item['key'], item['from'], rules.keys.get(item['key']))} -> "
        f"{mask_value(item['key'], item['to'], rules.keys.get(item['key']))}"
        + (
            " (applied)"
            if item.get("applied")
            else f" (kept target: {item.get('reason', 'environment value preserved')})"
        )
        for item in plan.changed
    ])

    append_section(lines, "KEPT TARGET VALUES", [
        f"= {item['key']} kept target "
        f"{mask_value(item['key'], item['current'], rules.keys.get(item['key']))}"
        f" (source: {mask_value(item['key'], item['incoming'], rules.keys.get(item['key']))})"
        for item in plan.kept_target_values
    ])

    append_section(lines, "PRESERVED / PROTECTED", [
        f"= {item['key']} kept"
        for item in plan.preserved_protected
    ])

    review_lines: list[str] = []
    for item in plan.review_required:
        line = (
            f"! {item['key']}: "
            f"{mask_value(item['key'], item['from'], rules.keys.get(item['key']))} -> "
            f"{mask_value(item['key'], item['to'], rules.keys.get(item['key']))}"
        )
        if item.get("forced"):
            line += " (forced apply)"
        elif item.get("kept"):
            line += " (kept target value)"
        review_lines.append(line)
        if item.get("reason"):
            review_lines.append(f"  Reason: {item['reason']}")
        if item.get("impact"):
            review_lines.append(f"  Impact: {item['impact']}")
        validations = item.get("validation") or []
        if validations:
            review_lines.append("  Validation:")
            for step in validations:
                review_lines.append(f"  - {step}")

    append_section(lines, "REVIEW REQUIRED", review_lines)

    append_section(lines, "REQUIRED MISSING", [
        f"! {item['key']} is missing or empty"
        for item in plan.required_missing
    ])

    append_section(lines, "EXTRA IN TARGET", [
        (
            f"? {item['key']} exists in target but not in source ({item.get('action', 'review')})"
            if not item.get("applied")
            else f"? {item['key']} exists in target but not in source ({item.get('action', 'handled')})"
        )
        for item in plan.extra_in_target
    ])

    append_section(lines, "DEPRECATED", [
        f"? {item['key']} is deprecated and should be reviewed manually"
        for item in plan.deprecated
    ])

    append_section(lines, "AMBIGUOUS", [
        f"? {item['key']} {item['reason']}"
        for item in plan.ambiguous
    ])

    append_section(lines, "VALIDATION ERRORS", [
        f"! {item}"
        for item in plan.validation_errors
    ])

    lines.append("")
    lines.append("BACKUP:")
    if plan.backup_path is None:
        if plan.mode == "report":
            lines.append("Not created because mode is report.")
        else:
            lines.append("Not created because no changes were applied.")
    else:
        lines.append(str(plan.backup_path))

    lines.append("")
    lines.append("RESULT:")
    lines.append(f"Mode: {plan.mode}")
    lines.append(f"Applied changes: {plan.applied_changes}")
    lines.append(f"Added keys: {len(plan.added)}")
    lines.append(f"Changed keys: {len([item for item in plan.changed if item.get('applied')])}")
    lines.append(f"Kept target values: {len(plan.kept_target_values)}")
    lines.append(f"Protected keys preserved: {len(plan.preserved_protected)}")
    lines.append(
        f"Manual review required: {len([item for item in plan.review_required if not item.get('forced')])}"
    )
    lines.append(f"Required missing: {len(plan.required_missing)}")
    lines.append(f"Extra keys: {len(plan.extra_in_target)}")
    lines.append(f"Deprecated keys: {len(plan.deprecated)}")
    lines.append(f"Ambiguities: {len(plan.ambiguous)}")
    lines.append(f"Validation errors: {len(plan.validation_errors)}")
    lines.append(f"Equal keys: {plan.ok_count}")

    if verbose:
        lines.append("")
        lines.append("VERBOSE:")
        lines.append(f"Rules version: {rules.version}")
        lines.append(f"defaults.add_missing: {bool(rules.defaults.get('add_missing', True))}")
        lines.append(
            f"defaults.apply_managed_changes: {bool(rules.defaults.get('apply_managed_changes', False))}"
        )
        lines.append(f"defaults.backup_dir: {rules.defaults.get('backup_dir', '.env-backups')}")

    report = "\n".join(lines)

    if not use_color:
        return report

    report = report.replace("ENV SYNC REPORT", painter.color("ENV SYNC REPORT", "blue"))
    report = report.replace("VALIDATION ERRORS", painter.color("VALIDATION ERRORS", "red"))
    report = report.replace("REVIEW REQUIRED", painter.color("REVIEW REQUIRED", "yellow"))
    return report


def append_section(lines: list[str], title: str, entries: list[str]) -> None:
    lines.append("")
    lines.append(f"{title}:")
    if not entries:
        lines.append("(none)")
        return
    lines.extend(entries)


def write_report(path: Path, content: str) -> None:
    try:
        if path.parent != Path("."):
            path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content + "\n", encoding="utf-8")
    except OSError as exc:
        raise PermissionErrorSync(f"Unable to write report file: {path}") from exc


def has_differences(plan: SyncPlan) -> bool:
    return any(
        [
            plan.added,
            plan.changed,
            plan.kept_target_values,
            plan.preserved_protected,
            plan.review_required,
            plan.required_missing,
            plan.extra_in_target,
            plan.deprecated,
            plan.ambiguous,
        ]
    )


def compute_exit_code(plan: SyncPlan) -> int:
    if plan.validation_errors:
        return EXIT_ERROR

    unresolved_review = any(not item.get("forced") for item in plan.review_required)
    if unresolved_review:
        return EXIT_REVIEW_REQUIRED

    if plan.mode == "report" and has_differences(plan):
        return EXIT_DIFF

    return EXIT_SUCCESS


def run_generate_contract_mode(args: argparse.Namespace) -> int:
    source_template = DEFAULT_TEMPLATE_PATH
    output_path = Path(args.output)
    publish_path = DEFAULT_PUBLISHED_RULES_PATH if args.publish else None
    report_path = Path(args.report_output)

    ensure_readable_file(source_template, "official template")

    render_module = load_render_contract_module()
    required_public_keys = getattr(render_module, "REQUIRED_PUBLIC_KEYS", {})
    if not isinstance(required_public_keys, dict):
        raise ValidationError("Invalid REQUIRED_PUBLIC_KEYS metadata in render_product_config.py")

    template_items, template_duplicates = extract_template_keys(source_template)
    template_key_list = [item.key for item in template_items]
    template_key_set = set(template_key_list)
    allowed_values = allowed_values_map(render_module)

    rules_doc = build_generated_rules_document(
        template_items=template_items,
        required_public_keys=required_public_keys,
        allowed_values=allowed_values,
    )
    validate_generated_rules_document(rules_doc, template_key_list)

    write_yaml_file(output_path, rules_doc)
    # Secondary parse validation to ensure generated file is consumable by sync flow.
    load_rules(output_path)

    env_files = discover_environment_files(source_template.parent)
    extras_by_env, missing_by_env, duplicates_by_env, values_by_key, env_extra_keys = analyze_env_files(
        env_files=env_files,
        template_keys=template_key_set,
    )
    varying_keys = detect_value_variations(values_by_key)

    code_usage_keys = key_usage_from_render_code()
    missing_in_template_from_code = sorted(code_usage_keys - template_key_set)
    env_extra_keys_used_by_code = sorted(env_extra_keys & code_usage_keys)
    env_extra_keys_without_usage = sorted(env_extra_keys - code_usage_keys)

    post_checks: list[PostCheckResult] = [
        run_post_check(
            source_path=source_template,
            target_path=source_template,
            rules_path=output_path,
            verbose=args.verbose,
        )
    ]
    for env_path in env_files:
        post_checks.append(
            run_post_check(
                source_path=source_template,
                target_path=env_path,
                rules_path=output_path,
                verbose=args.verbose,
            )
        )

    if publish_path is not None:
        publish_generated_contract(output_path, publish_path)

    sensitive_keys = sorted([key for key, meta in rules_doc["keys"].items() if meta.get("secret") is True])
    review_required_keys = sorted(
        [key for key, meta in rules_doc["keys"].items() if meta.get("policy") == "review_required"]
    )

    if not args.no_report:
        report = render_generate_report(
            source_template=source_template,
            generated_output=output_path,
            published_output=publish_path,
            env_files=env_files,
            rules_doc=rules_doc,
            sensitive_keys=sensitive_keys,
            review_required_keys=review_required_keys,
            missing_in_template_from_code=missing_in_template_from_code,
            extras_by_env=extras_by_env,
            missing_by_env=missing_by_env,
            duplicates_by_env=duplicates_by_env,
            duplicate_in_template=template_duplicates,
            varying_keys=varying_keys,
            env_extra_keys_used_by_code=env_extra_keys_used_by_code,
            env_extra_keys_without_usage=env_extra_keys_without_usage,
            post_checks=post_checks,
        )
        write_report(report_path, report.rstrip("\n"))

    strict_failures = [
        item
        for item in post_checks
        if item.exists and item.exit_code != EXIT_SUCCESS and item.target != source_template
    ]

    print("ENV CONTRACT GENERATION RESULT")
    print(f"Template: {source_template}")
    print(f"Generated contract: {output_path}")
    if publish_path is not None:
        print(f"Published contract: {publish_path}")
    if args.no_report:
        print("Report: disabled (--no-report)")
    else:
        print(f"Report: {report_path}")
    print(f"Discovered environments: {len(env_files)}")
    print(f"Template keys: {len(template_key_list)}")
    print(f"Sensitive keys: {len(sensitive_keys)}")
    print(f"Review required keys: {len(review_required_keys)}")
    print(f"Template duplicates: {len(template_duplicates)}")
    print(f"Code keys missing in template: {len(missing_in_template_from_code)}")
    print(f"Env extras without code usage: {len(env_extra_keys_without_usage)}")
    print(f"Post-check failures: {len(strict_failures)}")
    if not env_files:
        print("Warning: no config/<environment>.env files discovered; strict gate skipped for environment files.")

    if args.strict_post_checks and strict_failures:
        for item in strict_failures:
            print(f"Strict post-check failed for {item.target}: {item.summary}", file=sys.stderr)
            if item.missing_keys:
                print(
                    "  missing keys: " + ", ".join(item.missing_keys),
                    file=sys.stderr,
                )
            if item.review_required_keys:
                print(
                    "  review_required keys: " + ", ".join(item.review_required_keys),
                    file=sys.stderr,
                )
            if item.extra_keys:
                print(
                    "  extra keys: " + ", ".join(item.extra_keys),
                    file=sys.stderr,
                )
            if item.ambiguous_keys:
                print(
                    "  ambiguous keys: " + ", ".join(item.ambiguous_keys),
                    file=sys.stderr,
                )
            if item.validation_errors:
                print("  validation errors:", file=sys.stderr)
                for message in item.validation_errors:
                    print(f"    - {message}", file=sys.stderr)
        return EXIT_ERROR

    return EXIT_SUCCESS


def run_sync_mode(args: argparse.Namespace) -> int:
    missing: list[str] = []
    if not args.source:
        missing.append("--source")
    if not args.target:
        missing.append("--target")
    if not args.rules:
        missing.append("--rules")
    if missing:
        raise ValidationError(
            "Missing required arguments for sync mode: "
            + ", ".join(missing)
            + ". Use --generate-contract for contract generation mode."
        )

    source_path = Path(args.source)
    target_path = Path(args.target)
    rules_path = Path(args.rules)

    ensure_readable_file(source_path, "source")
    ensure_readable_file(target_path, "target")

    rules = load_rules(rules_path)

    source = parse_env_file(source_path, "source")
    target = parse_env_file(target_path, "target")

    only_keys = parse_key_list(args.only)
    force_reviewed = parse_key_list(args.force_reviewed)

    plan = build_sync_plan(
        source=source,
        target=target,
        rules=rules,
        mode=args.mode,
        only_keys=only_keys,
        allow_managed=args.allow_managed,
        force_reviewed=force_reviewed,
        verbose=args.verbose,
    )

    if args.reconcile_interactive:
        if args.mode != "apply":
            raise ValidationError("--reconcile-interactive requires --mode apply.")
        apply_reconcile_interactive(
            plan=plan,
            source=source,
            target=target,
            rules=rules,
            only_keys=only_keys,
            extra_action=args.extra_action,
        )

    has_extra_actions = any(item.get("applied") and item.get("action") for item in plan.extra_in_target)
    if args.mode == "apply" and not plan.validation_errors and (plan.updates or plan.additions or has_extra_actions):
        backup_dir = Path(str(rules.defaults.get("backup_dir", ".env-backups")))
        plan.backup_path = create_backup(target_path, backup_dir)
        new_content = apply_changes_to_target(target, plan)
        write_atomic(target_path, new_content)

    report = render_report(
        plan=plan,
        source_path=source_path,
        target_path=target_path,
        rules_path=rules_path,
        rules=rules,
        use_color=not args.no_color,
        verbose=args.verbose,
    )
    print(report)

    if args.write_report:
        # Always write plain text report without ANSI colors.
        plain_report = render_report(
            plan=plan,
            source_path=source_path,
            target_path=target_path,
            rules_path=rules_path,
            rules=rules,
            use_color=False,
            verbose=args.verbose,
        )
        write_report(Path(args.write_report), plain_report)

    return compute_exit_code(plan)


def main() -> int:
    args = parse_args()

    try:
        if args.generate_contract:
            return run_generate_contract_mode(args)
        return run_sync_mode(args)
    except PermissionErrorSync as exc:
        print(str(exc), file=sys.stderr)
        return EXIT_PERMISSION
    except ValidationError as exc:
        print(str(exc), file=sys.stderr)
        return EXIT_ERROR
    except Exception as exc:  # noqa: BLE001 - final safety catch without leaking data.
        print(f"Execution error: {exc.__class__.__name__}", file=sys.stderr)
        return EXIT_ERROR


if __name__ == "__main__":
    sys.exit(main())
