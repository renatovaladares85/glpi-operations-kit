"""Ansible filters for safely rendering PHP string literals."""


def php_single_quoted_string(value):
    """Return a PHP single-quoted literal preserving the original text."""
    text = str(value)
    escaped = text.replace("\\", "\\\\").replace("'", "\\'")
    return f"'{escaped}'"


class FilterModule:
    """Expose PHP string filters to Ansible/Jinja."""

    def filters(self):
        return {"php_single_quoted_string": php_single_quoted_string}
