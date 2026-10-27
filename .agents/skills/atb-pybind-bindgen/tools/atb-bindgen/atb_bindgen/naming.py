"""C++ camelCase to Python snake_case conversion."""

import re

# Manual overrides for irregular names (config.json name_overrides merged at runtime).
_DEFAULT_OVERRIDES: dict[str, str] = {}


def set_overrides(overrides: dict[str, str]) -> None:
    global _DEFAULT_OVERRIDES
    _DEFAULT_OVERRIDES = dict(overrides)


def camel_to_snake(name: str) -> str:
    if name in _DEFAULT_OVERRIDES:
        return _DEFAULT_OVERRIDES[name]
    s1 = re.sub(r"(.)([A-Z][a-z]+)", r"\1_\2", name)
    return re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", s1).lower()


def param_to_op_snake(param_name: str) -> str:
    """LayerNormParam -> layer_norm."""
    base = param_name
    if base.endswith("Param"):
        base = base[: -len("Param")]
    return camel_to_snake(base)
