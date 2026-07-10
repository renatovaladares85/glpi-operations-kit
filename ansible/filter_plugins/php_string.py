"""Ansible filters for safely rendering PHP string literals."""

from urllib.parse import quote


def php_single_quoted_string(value):
    """Return a PHP single-quoted literal preserving the original text."""
    text = str(value)
    escaped = text.replace("\\", "\\\\").replace("'", "\\'")
    return f"'{escaped}'"


def php_rawurlencoded_single_quoted_string(value):
    """Return a GLPI-compatible rawurlencoded password as a PHP literal."""
    return php_single_quoted_string(quote(str(value), safe="-_.~"))


class FilterModule:
    """Expose PHP string filters to Ansible/Jinja."""

    def filters(self):
        return {
            "php_single_quoted_string": php_single_quoted_string,
            "php_rawurlencoded_single_quoted_string": php_rawurlencoded_single_quoted_string,
        }
