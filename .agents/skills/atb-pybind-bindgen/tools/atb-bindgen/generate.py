#!/usr/bin/env python3
"""ATB pybind11 binding code generator - main entry."""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

from atb_bindgen.bootstrap import bootstrap_all
from atb_bindgen.codegen import CodeGenerator
from atb_bindgen.naming import set_overrides
from atb_bindgen.parser import HeaderParser
from atb_bindgen.test_generator import TestGenerator


def load_config(path: Path) -> dict:
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def resolve_paths(config: dict, args: argparse.Namespace) -> tuple[Path, Path, Path]:
    atb_repo = Path(args.atb_repo or os.environ.get("ATB_REPO_PATH", ""))
    if not atb_repo or not atb_repo.is_dir():
        default = Path(__file__).resolve().parent.parent / "ascend-transformer-boost"
        if default.is_dir():
            atb_repo = default
        else:
            print("[ERROR] ATB_REPO_PATH not set or invalid. Set env or use --atb-repo.", file=sys.stderr)
            sys.exit(1)

    header = Path(args.header) if args.header else atb_repo / config["header"]
    output_dir = Path(args.output_dir) if args.output_dir else atb_repo / config["output_dir"]
    return atb_repo, header, output_dir


def main() -> None:
    parser = argparse.ArgumentParser(description="ATB pybind11 binding generator")
    parser.add_argument("--config", default=str(Path(__file__).parent / "config.json"))
    parser.add_argument("--header", help="Path to infer_op_params.h")
    parser.add_argument("--output-dir", help="Output directory for generated .inc files")
    parser.add_argument("--atb-repo", help="ATB repository root path")
    parser.add_argument(
        "--bootstrap",
        action="store_true",
        help="Extract param bindings from existing hand-written source (one-time migration)",
    )
    parser.add_argument(
        "--regenerate-params",
        action="store_true",
        help="Regenerate bindings_ops.inc from header parser (complex ops use init_overrides preserve)",
    )
    parser.add_argument("--tests", action="store_true", help="Also generate test cases")
    parser.add_argument("--force-tests", action="store_true", help="Overwrite existing bindgen test files")
    parser.add_argument("--dry-run", action="store_true", help="Print actions without writing files")
    args = parser.parse_args()

    config = load_config(Path(args.config))
    atb_repo, header, output_dir = resolve_paths(config, args)

    if not header.exists():
        print(f"[ERROR] Header not found: {header}", file=sys.stderr)
        sys.exit(1)

    set_overrides(config.get("name_overrides", {}))
    header_parser = HeaderParser(config, atb_repo)
    structs = header_parser.parse(header)
    print(f"[INFO] Parsed {len(structs)} structs from {header}")

    gen = CodeGenerator(config)
    param_bindings: str | None = None

    if args.bootstrap:
        print("[INFO] Bootstrap mode: extracting param bindings from existing bindings.cpp")
        if not args.dry_run:
            bootstrap_all(atb_repo, output_dir)
            param_bindings = (output_dir / "bindings_ops.inc").read_text(encoding="utf-8")
    elif args.regenerate_params:
        print("[INFO] Regenerating bindings_ops.inc from parser")
        param_bindings = gen.generate_param_bindings(structs)
    elif (output_dir / "bindings_ops.inc").exists():
        print("[INFO] Reusing existing bindings_ops.inc (use --bootstrap or --regenerate-params to replace)")
        param_bindings = (output_dir / "bindings_ops.inc").read_text(encoding="utf-8")
    else:
        print("[INFO] No bindings_ops.inc found, running bootstrap")
        if not args.dry_run:
            bootstrap_all(atb_repo, output_dir)
            param_bindings = (output_dir / "bindings_ops.inc").read_text(encoding="utf-8")

    if args.dry_run:
        print("[DRY-RUN] Would write generated files to", output_dir)
        return

    written = gen.write_all(output_dir, structs, param_bindings=param_bindings)
    for name, path in written.items():
        print(f"[OK] {path}")

    if args.tests:
        test_gen = TestGenerator(config, atb_repo, force=args.force_tests)
        test_written = test_gen.generate_all(structs)
        for name, path in test_written.items():
            print(f"[OK] test {path}")

    print("[DONE] Generation complete. Run validate_consistency.py to verify four-file consistency.")


if __name__ == "__main__":
    main()
