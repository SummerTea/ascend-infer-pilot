---
name: atb-pybind-test-generator
description: >
  生成 ATB pybind 测试用例（op_param_test + bindgen golden forward 测试）。
  触发词：pybind 测试生成、op_param_test、bindgen_test、golden recipe。
keywords:
    - atb
    - pybind
    - test
    - op_param_test
    - bindgen_test
    - golden
metadata:
  author: ascend-transformer-boost-team
  version: "1.2.1"
  created: "2026-06-26"
  updated: "2026-06-30"
  skill-type: test
---

# ATB Pybind 测试生成器

## 用途

生成 param 冒烟与 forward 精度测试。工具随 **atb-pybind-bindgen** skill 自带（`tools/atb-bindgen/`）；无 NPU 时可只生成文件，精度 Gate 见 `atb-pybind-bindgen/references/verification-playbook.md`。

## 命令

```bash
export ATB_BINDGEN_PATH="<SKILLS_DIR>/atb-pybind-bindgen/tools/atb-bindgen"
cd ${ATB_BINDGEN_PATH}
python3 generate.py --atb-repo ${ATB_REPO_PATH} --tests --force-tests
```

## 输出

| 输出 | 说明 |
|------|------|
| `op_param_test.py` → `TestGeneratedParams` | 各 whitelist 算子构造 + repr 冒烟（当前约 35 项） |
| `op_test/<op>/<op>_bindgen_test.py` | CPU golden + NPU forward + `check_float`/`check_move` |
| `op_test/<op>/__init__.py` | 自动生成（discover 必需） |

Golden recipe 内建于 `atb_bindgen/golden_recipes.py`；分类见 `config.json` → `golden_mappings`。

## golden_mappings 分类

| category | 行为 |
|----------|------|
| `torch_builtin` | 使用 `golden_recipes.py` 内建 recipe |
| `torch_compose` | 同上（如 Linear 用 `F.linear` 拼接） |
| `comm_skip` | 不生成 forward（AllGather 等） |
| `skip_npu` | 不生成 forward（SelfAttention 等） |
| `custom_manual` | 输出手工 stub，需人工补 golden |

## 编写 recipe 经验

1. **对齐已有手写测试**：优先参考 `tests/apitest/torch_atb_test/op_test/<op>/<op>_test.py` 或 `tests/apitest/opstest/python/operations/<op>/`，不要直接用 `torch.*` 若 ATB 语义不同。
2. **Split**：NPU 返回 list，`check_move(npu_outputs, torch.stack(parts))`（非 list 包一层）。
3. **Gather**：用手写 flatten 索引逻辑，勿用 `torch.gather`。
4. **IndexAdd**：golden 为 `out - var`（delta）；`check_float`；`run_perf_test` 用 `var_npu.clone()`；suite 内可用子进程跑 `run_test()`（见 troubleshooting）。
5. **精度函数**：整型/move 类用 `check_move`；浮点用 `check_float`（默认 err=2^-8）。
6. **discover 覆盖**：每个 `op_test/<op>/` 目录必须有 `__init__.py`，否则 `unittest discover -p "*_bindgen_test.py"` 会漏测。
7. **运行方式**：在 `tests/apitest` 下 `python3 -m unittest ...`，勿直接 `python .../xxx_bindgen_test.py`。

## 当前覆盖（11 算子）

Split, Concat, Softmax, LayerNorm, Gather, Transpose, Elewise, Activation, RmsNorm, Linear, IndexAdd

## 验证

```bash
# 在 RzH 内，source ATB set_env 后；工作目录必须是 tests/apitest
cd ${ATB_REPO_PATH}/tests/apitest
export ASCEND_RT_VISIBLE_DEVICES=2
python3 -m unittest discover -s torch_atb_test/op_test -p "*_bindgen_test.py" -v
```

或一键（环境变量 + `run_verify.sh`，见 `atb-pybind-bindgen/references/verification-playbook.md`）：

```bash
export ATB_REPO_PATH=... ATB_BINDGEN_PATH=... DOCKER_NAME=...  # 可选容器
bash "${ATB_BINDGEN_PATH}/scripts/run_verify.sh"
```

## 衔接

完整流程（生成 + 编译 + Gate）：`atb-pybind-bindgen`
