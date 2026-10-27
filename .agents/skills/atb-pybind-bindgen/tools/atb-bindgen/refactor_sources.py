#!/usr/bin/env python3
"""One-time migration: refactor torch_atb sources to use generated .inc files."""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path


def resolve_torch_atb_dir(atb_repo: Path) -> Path:
    repo = atb_repo / "src" / "torch_atb"
    if not repo.is_dir():
        print(f"[ERROR] torch_atb not found under {atb_repo}", file=sys.stderr)
        sys.exit(1)
    return repo


def refactor_bindings(repo: Path) -> None:
    path = repo / "bindings.cpp"
    text = path.read_text(encoding="utf-8")

    op_start = text.index('    py::class_<TorchAtb::OperationWrapper>(m, "Operation")')
    op_init_start = text.index("        .def(py::init<const LayerNormParam &>())", op_start)
    op_init_end = text.index('        .def_property_readonly("name"', op_init_start)

    builder_add_start = text.index(
        '        .def("add_node", py::overload_cast<const std::vector<std::string> &, const atb::infer::LinearParam &>',
    )
    builder_add_end = text.index(
        '        .def("add_node", py::overload_cast<const std::vector<std::string> &, TorchAtb::OperationWrapper &>',
        builder_add_start,
    )

    param_start = text.index("    py::class_<LayerNormParam>")
    param_end = len(text) - 1
    while param_end > param_start and text[param_end] != "}":
        param_end -= 1

    new_text = (
        text[:op_init_start]
        + '#include "bindings_operation_inits.inc"\n'
        + text[op_init_end:builder_add_start]
        + '#include "bindings_builder_add_nodes.inc"\n'
        + text[builder_add_end:param_start]
        + '#include "bindings_ops.inc"\n'
        + text[param_end:]
    )
    path.write_text(new_text, encoding="utf-8")
    print(f"Refactored {path}")


def refactor_wrapper_h(repo: Path) -> None:
    path = repo / "operation_wrapper.h"
    text = path.read_text(encoding="utf-8")
    start = text.index("    explicit OperationWrapper(const atb::infer::LayerNormParam &param);")
    end = text.index("    atb::Operation *ReleaseOperation();")
    new_text = text[:start] + '#include "operation_wrapper_generated.inc"\n' + text[end:]
    path.write_text(new_text, encoding="utf-8")
    print(f"Refactored {path}")


def refactor_wrapper_cpp(repo: Path) -> None:
    path = repo / "operation_wrapper.cpp"
    text = path.read_text(encoding="utf-8")
    start = text.index("OperationWrapper::OperationWrapper(const LayerNormParam &param)")
    end = text.index("std::string OperationWrapper::GetName() const")
    new_text = text[:start] + '#include "operation_wrapper_ops.inc"\n\n' + text[end:]
    path.write_text(new_text, encoding="utf-8")
    print(f"Refactored {path}")


def refactor_graph_h(repo: Path) -> None:
    path = repo / "enger_graph_builder.h"
    text = path.read_text(encoding="utf-8")
    start = text.index(
        "    GraphNode &AddNode(const std::vector<std::string> &inputs, const atb::infer::LinearParam &param);"
    )
    end = text.index(
        "    GraphNode &AddNode(const std::vector<std::string> &inputs, OperationWrapper &opWrapper);"
    )
    new_text = text[:start] + '#include "enger_graph_builder_generated.inc"\n' + text[end:]
    path.write_text(new_text, encoding="utf-8")
    print(f"Refactored {path}")


def refactor_graph_cpp(repo: Path) -> None:
    path = repo / "enger_graph_builder.cpp"
    text = path.read_text(encoding="utf-8")
    start = text.index(
        "GraphNode &GraphBuilder::AddNode(const std::vector<std::string> &inputs, const atb::infer::LinearParam &param)"
    )
    end = text.index(
        "GraphNode &GraphBuilder::AddNode(const std::vector<std::string> &inputs, OperationWrapper &opWrapper)"
    )
    new_text = text[:start] + '#include "enger_graph_builder_ops.inc"\n\n' + text[end:]
    path.write_text(new_text, encoding="utf-8")
    print(f"Refactored {path}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Refactor torch_atb to bindgen .inc layout")
    parser.add_argument("--atb-repo", help="ATB repository root (or set ATB_REPO_PATH)")
    args = parser.parse_args()
    atb_repo = Path(args.atb_repo or os.environ.get("ATB_REPO_PATH", ""))
    if not atb_repo.is_dir():
        print("[ERROR] Set ATB_REPO_PATH or pass --atb-repo", file=sys.stderr)
        sys.exit(1)
    repo = resolve_torch_atb_dir(atb_repo)
    refactor_bindings(repo)
    refactor_wrapper_h(repo)
    refactor_wrapper_cpp(repo)
    refactor_graph_h(repo)
    refactor_graph_cpp(repo)


if __name__ == "__main__":
    main()
