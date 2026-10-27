#!/usr/bin/env python3
"""Four-file consistency validator for ATB pybind bindings."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path


def load_config(path: Path) -> dict:
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8") if path.exists() else ""


def find_ops_in_file(text: str, patterns: list[str]) -> set[str]:
    found: set[str] = set()
    for pattern in patterns:
        found.update(re.findall(pattern, text))
    return found


def validate(repo: Path, config: dict) -> list[str]:
    errors: list[str] = []
    torch_atb = repo / "src/torch_atb"
    operation_ops = set(config.get("operation_ops", []))
    graph_ops = set(config.get("graph_builder_ops", [])) - set(config.get("skip_ops_in_graphbuilder", []))

    bindings = read_text(torch_atb / "bindings.cpp")
    bindings_inc = read_text(torch_atb / "bindings_ops.inc")
    bindings_op_inits = read_text(torch_atb / "bindings_operation_inits.inc")
    bindings_add_nodes = read_text(torch_atb / "bindings_builder_add_nodes.inc")
    bindings_all = bindings + bindings_inc + bindings_op_inits + bindings_add_nodes

    wrapper_h = read_text(torch_atb / "operation_wrapper.h") + read_text(
        torch_atb / "operation_wrapper_generated.inc"
    )
    wrapper_cpp = read_text(torch_atb / "operation_wrapper.cpp") + read_text(
        torch_atb / "operation_wrapper_ops.inc"
    )

    graph_h = read_text(torch_atb / "enger_graph_builder.h") + read_text(
        torch_atb / "enger_graph_builder_generated.inc"
    )
    graph_cpp = read_text(torch_atb / "enger_graph_builder.cpp") + read_text(
        torch_atb / "enger_graph_builder_ops.inc"
    )

    for op in operation_ops:
        if op == "GraphParam":
            patterns = [
                r"py::init<const atb::GraphParam &>",
                r"OperationWrapper\(const atb::GraphParam &",
                r"CreateOpUniquePtr\(param\)",
            ]
        else:
            patterns = [
                rf"py::init<const {op} &>",
                rf"OperationWrapper\(const atb::infer::{op} &",
                rf"OperationWrapper\(const {op} &",
            ]
        if op != "GraphParam":
            if op not in find_ops_in_file(bindings_all, [rf"class_<{op}>"]):
                if op not in {"GraphParam"}:
                    pass  # GraphParam has no param class
        in_bindings_init = bool(find_ops_in_file(bindings_all, [rf"py::init<const (?:atb::)?{op} &>"]))
        in_wrapper_h = bool(find_ops_in_file(wrapper_h, [rf"OperationWrapper\(const (?:atb::infer::|atb::)?{op} &"]))
        in_wrapper_cpp = bool(find_ops_in_file(wrapper_cpp, [rf"OperationWrapper::OperationWrapper\(const {op} &"]))
        if op == "GraphParam":
            in_wrapper_cpp = bool(find_ops_in_file(wrapper_cpp, [r"OperationWrapper::OperationWrapper\(const atb::GraphParam &"]))
        if not in_bindings_init:
            errors.append(f"MISSING Operation init for {op} in bindings")
        if not in_wrapper_h:
            errors.append(f"MISSING OperationWrapper declaration for {op} in operation_wrapper.h")
        if not in_wrapper_cpp:
            errors.append(f"MISSING OperationWrapper implementation for {op} in operation_wrapper.cpp")

    for op in graph_ops:
        in_bindings = bool(
            find_ops_in_file(
                bindings_all,
                [rf"add_node.*const atb::infer::{op} &"],
            )
        )
        in_graph_h = bool(
            find_ops_in_file(graph_h, [rf"AddNode\(const std::vector<std::string> &inputs, const atb::infer::{op} &"])
        )
        in_graph_cpp = bool(
            find_ops_in_file(
                graph_cpp,
                [rf"GraphBuilder::AddNode\(const std::vector<std::string> &inputs, const atb::infer::{op} &"],
            )
        )
        if not in_bindings:
            errors.append(f"MISSING Builder.add_node for {op} in bindings")
        if not in_graph_h:
            errors.append(f"MISSING AddNode declaration for {op} in enger_graph_builder.h")
        if not in_graph_cpp:
            errors.append(f"MISSING AddNode implementation for {op} in enger_graph_builder.cpp")

    return errors


def main() -> None:
    parser = argparse.ArgumentParser(description="Validate four-file binding consistency")
    parser.add_argument("--config", default=str(Path(__file__).parent / "config.json"))
    parser.add_argument("--repo", help="ATB repository root")
    args = parser.parse_args()

    config = load_config(Path(args.config))
    repo = Path(args.repo or os.environ.get("ATB_REPO_PATH", ""))
    if not repo or not repo.is_dir():
        repo = Path(__file__).resolve().parent.parent / "ascend-transformer-boost"
    if not repo.is_dir():
        print("[ERROR] ATB repo not found", file=sys.stderr)
        sys.exit(1)

    errors = validate(repo, config)
    if errors:
        print(f"[FAIL] {len(errors)} consistency error(s):")
        for e in errors:
            print(f"  - {e}")
        sys.exit(1)
    print("[PASS] Four-file consistency check passed")
    sys.exit(0)


if __name__ == "__main__":
    main()
