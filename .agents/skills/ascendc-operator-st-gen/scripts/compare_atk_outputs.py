#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""对比 ATK --save_data 落盘的 benchmark / cpu / pyaclnn 输出。"""

import argparse
import glob
import os
import sys

import torch


def _find_output_pt(root, backend, case_name, index=0):
    pattern = os.path.join(
        root, backend, case_name, str(index), "output_*.pt")
    hits = sorted(glob.glob(pattern))
    if not hits:
        pattern = os.path.join(root, backend, case_name, str(index), "output_0.pt")
        if os.path.isfile(pattern):
            return pattern
    return hits[0] if hits else None


def _load(path):
    t = torch.load(path, map_location="cpu")
    if isinstance(t, (list, tuple)):
        return t[0]
    return t


def main():
    parser = argparse.ArgumentParser(description="Compare ATK saved outputs")
    parser.add_argument("output_dir", help="atk_output/<task>_*/output")
    parser.add_argument("--case", default="", help="case subdir name, auto if empty")
    parser.add_argument("--pytest-dir", default="", help="path to tests/pytest for check_result")
    args = parser.parse_args()

    out_root = os.path.abspath(args.output_dir)
    case_name = args.case
    if not case_name:
        for name in ("cpu_benchmark", "cpu_0", "pyaclnn_0"):
            d = os.path.join(out_root, name)
            if os.path.isdir(d):
                case_name = next(iter(os.listdir(d)))
                break
    if not case_name:
        print("ERROR: cannot detect case name under", out_root)
        return 1

    paths = {}
    for backend in ("cpu_benchmark", "cpu_0", "pyaclnn_0"):
        p = _find_output_pt(out_root, backend, case_name)
        if p:
            paths[backend] = p

    if not paths:
        print("ERROR: no output_*.pt under", out_root)
        return 1

    tensors = {k: _load(v) for k, v in paths.items()}
    print("case:", case_name)
    for k, v in paths.items():
        t = tensors[k]
        print(f"  {k}: {v} shape={tuple(t.shape)} dtype={t.dtype}")

    check_result = None
    if args.pytest_dir:
        sys.path.insert(0, os.path.abspath(args.pytest_dir))
        try:
            from result_compare_method import check_result as cr
            check_result = cr
        except ImportError:
            print("WARN: cannot import result_compare_method from", args.pytest_dir)

    if "cpu_benchmark" in tensors and "cpu_0" in tensors:
        a, b = tensors["cpu_benchmark"], tensors["cpu_0"]
        print("benchmark vs cpu_0: equal=", torch.equal(a, b),
              "max_diff=", (a.float() - b.float()).abs().max().item())
        if check_result:
            print("  check_result:", check_result(a, b))

    if "cpu_benchmark" in tensors and "pyaclnn_0" in tensors:
        a, b = tensors["cpu_benchmark"], tensors["pyaclnn_0"]
        print("benchmark vs pyaclnn_0: equal=", torch.equal(a, b),
              "max_diff=", (a.float() - b.float()).abs().max().item())
        if check_result:
            print("  check_result:", check_result(a, b))

    return 0


if __name__ == "__main__":
    sys.exit(main())
