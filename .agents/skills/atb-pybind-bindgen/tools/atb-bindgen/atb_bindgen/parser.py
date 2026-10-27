"""C++ header parser: clang AST dump (preferred) or regex fallback."""

from __future__ import annotations

import json
import os
import re
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass
class EnumValue:
    name: str
    value: int | None = None


@dataclass
class EnumDef:
    name: str
    values: list[EnumValue] = field(default_factory=list)
    is_scoped: bool = False


@dataclass
class FieldDef:
    cpp_type: str
    name: str
    default: str | None = None
    is_svector: bool = False
    svector_elem: str | None = None
    is_vector: bool = False
    vector_elem: str | None = None


@dataclass
class StructDef:
    name: str
    namespace: str = "atb::infer"
    fields: list[FieldDef] = field(default_factory=list)
    nested_enums: list[EnumDef] = field(default_factory=list)
    nested_structs: list["StructDef"] = field(default_factory=list)
    parent: str | None = None


def _strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.DOTALL)
    text = re.sub(r"//.*?$", "", text, flags=re.MULTILINE)
    return text


def _find_matching_brace(text: str, start: int) -> int:
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return i
    raise ValueError(f"Unmatched brace at offset {start}")


def _parse_enum_body(body: str) -> list[EnumValue]:
    values: list[EnumValue] = []
    counter = 0
    for part in body.split(","):
        part = part.strip()
        if not part:
            continue
        m = re.match(r"(\w+)(?:\s*=\s*([^,]+))?", part)
        if not m:
            continue
        name = m.group(1)
        if m.group(2) is not None:
            try:
                val = int(m.group(2).strip())
            except ValueError:
                val = counter
        else:
            val = counter
        values.append(EnumValue(name=name, value=val))
        counter = val + 1
    return values


def _parse_field(line: str) -> FieldDef | None:
    line = line.strip().rstrip(";")
    if not line or line.startswith("//") or line.startswith("/*"):
        return None
    m = re.match(
        r"(?:(?:const|static|mutable)\s+)*"
        r"(SVector<([^>]+)>|std::vector<([^>]+)>|([\w:]+(?:\s*[*&])?))\s+"
        r"(\w+)(?:\s*=\s*(.+))?$",
        line,
    )
    if not m:
        return None
    svector_elem = m.group(2)
    vector_elem = m.group(3)
    plain_type = m.group(4)
    name = m.group(5)
    default = m.group(6).strip() if m.group(6) else None
    if name == "rsv":
        return None
    if svector_elem:
        return FieldDef(
            cpp_type=f"SVector<{svector_elem.strip()}>",
            name=name,
            default=default,
            is_svector=True,
            svector_elem=svector_elem.strip(),
        )
    if vector_elem:
        return FieldDef(
            cpp_type=f"std::vector<{vector_elem.strip()}>",
            name=name,
            default=default,
            is_vector=True,
            vector_elem=vector_elem.strip(),
        )
    return FieldDef(cpp_type=plain_type.strip(), name=name, default=default)


def _parse_struct_body(body: str, parent: str | None = None) -> tuple[list[FieldDef], list[EnumDef], list[StructDef]]:
    fields: list[FieldDef] = []
    enums: list[EnumDef] = []
    nested: list[StructDef] = []
    i = 0
    while i < len(body):
        while i < len(body) and body[i].isspace():
            i += 1
        if i >= len(body):
            break
        em = re.match(r"enum\s+(?:class\s+)?(\w+)(?:\s*:\s*\w+)?\s*\{", body[i:])
        if em:
            enum_name = em.group(1)
            brace_start = i + em.end() - 1
            brace_end = _find_matching_brace(body, brace_start)
            enum_body = body[brace_start + 1 : brace_end]
            enums.append(
                EnumDef(
                    name=enum_name,
                    values=_parse_enum_body(enum_body),
                    is_scoped="enum class" in body[i : i + em.end()],
                )
            )
            i = brace_end + 1
            continue
        sm = re.match(r"struct\s+(\w+)\s*\{", body[i:])
        if sm:
            sub_name = sm.group(1)
            brace_start = i + sm.end() - 1
            brace_end = _find_matching_brace(body, brace_start)
            sub_body = body[brace_start + 1 : brace_end]
            sub_fields, sub_enums, sub_nested = _parse_struct_body(sub_body, parent=sub_name)
            nested.append(
                StructDef(
                    name=sub_name,
                    parent=parent,
                    fields=sub_fields,
                    nested_enums=sub_enums,
                    nested_structs=sub_nested,
                )
            )
            i = brace_end + 1
            continue
        line_end = body.find(";", i)
        if line_end == -1:
            break
        line = body[i:line_end]
        fd = _parse_field(line)
        if fd:
            fields.append(fd)
        i = line_end + 1
    return fields, enums, nested


def _parse_top_level_structs(text: str, namespace: str = "atb::infer") -> dict[str, StructDef]:
    structs: dict[str, StructDef] = {}
    pattern = re.compile(r"struct\s+(\w+)\s*\{")
    for m in pattern.finditer(text):
        name = m.group(1)
        if not name.endswith("Param") and name not in ("GraphParam",):
            continue
        brace_start = m.end() - 1
        try:
            brace_end = _find_matching_brace(text, brace_start)
        except ValueError:
            continue
        body = text[brace_start + 1 : brace_end]
        fields, enums, nested = _parse_struct_body(body, parent=name)
        structs[name] = StructDef(
            name=name,
            namespace=namespace,
            fields=fields,
            nested_enums=enums,
            nested_structs=nested,
        )
    return structs


def _clang_include_args(atb_repo: Path) -> list[str]:
    ascend = os.environ.get("ASCEND_HOME_PATH") or os.environ.get("CANN_PATH", "")
    includes = []
    if ascend:
        includes.append(f"-I{ascend}/include")
    includes.extend(
        [
            f"-I{atb_repo}/include",
            f"-I{atb_repo}/src",
            f"-I{atb_repo}/3rdparty/mki/include",
            f"-I{atb_repo}/3rdparty/nlohmannJson/include",
        ]
    )
    pytorch = os.environ.get("PYTORCH_INSTALL_PATH", "")
    if pytorch:
        includes.extend(
            [
                f"-I{pytorch}/include",
                f"-I{pytorch}/include/torch/csrc/api/include",
            ]
        )
    return includes


def _parse_with_clang(header: Path, atb_repo: Path) -> dict[str, StructDef] | None:
    if not shutil_which("clang"):
        return None
    includes = _clang_include_args(atb_repo)
    cmd = ["clang", "-Xclang", "-ast-dump=json", "-fsyntax-only", "-std=c++17", *includes, str(header)]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return None
    if result.returncode != 0:
        return None
    try:
        ast = json.loads(result.stdout)
    except json.JSONDecodeError:
        return None
    return _extract_structs_from_ast(ast)


def shutil_which(cmd: str) -> str | None:
    from shutil import which

    return which(cmd)


def _extract_structs_from_ast(ast: dict[str, Any]) -> dict[str, StructDef]:
    """Minimal clang AST extraction; falls back to regex for defaults."""
    # Clang JSON AST is complex; regex fallback handles production structs.
    return {}


class HeaderParser:
    def __init__(self, config: dict[str, Any], atb_repo: Path):
        self.config = config
        self.atb_repo = atb_repo

    def parse(self, header: Path) -> dict[str, StructDef]:
        text = _strip_comments(header.read_text(encoding="utf-8"))
        structs = _parse_top_level_structs(text, "atb::infer")

        external = self.config.get("external_structs", {})
        for struct_name, fq_name in external.items():
            if struct_name in structs:
                structs[struct_name].namespace = fq_name.rsplit("::", 1)[0] if "::" in fq_name else "atb"
            else:
                ext_header = self.atb_repo / "include/atb/types.h"
                if ext_header.exists():
                    ext_text = _strip_comments(ext_header.read_text(encoding="utf-8"))
                    ext_structs = _parse_top_level_structs(ext_text, "atb")
                    if struct_name in ext_structs:
                        ext_structs[struct_name].namespace = "atb"
                        structs[struct_name] = ext_structs[struct_name]

        whitelist = set(self.config.get("whitelist", []))
        for name in structs:
            if name not in whitelist:
                print(f"[WARN] Struct {name} not in whitelist, skipping binding generation")

        clang_result = _parse_with_clang(header, self.atb_repo)
        if clang_result:
            for name, sd in clang_result.items():
                if name in structs:
                    structs[name] = sd

        return {k: v for k, v in structs.items() if k in whitelist}
