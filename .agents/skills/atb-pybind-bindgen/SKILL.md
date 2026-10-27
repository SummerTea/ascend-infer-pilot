---
name: atb-pybind-bindgen
description: >
  ATB torch_atb pybind11 绑定自动生成工作流。当用户需要自动绑定、pybind 代码生成、
  infer_op_params.h 新增算子同步、torch_atb 绑定维护、bindgen 端到端验证时调用。
  触发词：自动绑定、pybind、torch_atb、infer_op_params、bindgen、bindgen 验证、verify_bindgen。
keywords:
    - atb
    - pybind
    - torch_atb
    - bindgen
    - infer_op_params
    - 自动绑定
    - verify_bindgen
    - bindgen验证
metadata:
  author: ascend-transformer-boost-team
  version: "1.3.3"
  created: "2026-06-26"
  updated: "2026-07-01"
  skill-type: workflow
hooks:
  PreToolUse:
    - matcher: "Write|Edit|Bash"
      hooks:
        - type: command
          command: "([ -z \"$ATB_REPO_PATH\" ] || [ ! -d \"$ATB_REPO_PATH\" ]) && { echo '[PATH CHECK] ATB_REPO_PATH 未设置或无效' >&2; exit 1; }; ([ -z \"$CANN_PATH\" ] && [ -z \"$ASCEND_HOME_PATH\" ]) && echo '[WARN] CANN_PATH 未设置，clang AST 解析将降级为 regex' >&2; true"
---

# ATB Pybind 绑定自动生成

## Quick Reference

**用途**：从 `infer_op_params.h` 一键重新生成 torch_atb 四文件绑定，校验一致性，并在 NPU 环境完成精度 Gate。

**工具路径**：`<ATB_BINDGEN_PATH>/`（`atb-bindgen` 目录，含 `generate.py`、`scripts/`）

**工具获取**：本 Skill **自带** `tools/atb-bindgen/`（安装 skill 后即可使用，无需另找仓库）。默认：

```bash
export ATB_BINDGEN_PATH="<SKILLS_DIR>/atb-pybind-bindgen/tools/atb-bindgen"
```

`<SKILLS_DIR>` 为 Agent 安装 skills 的根目录（与 `atb-csv-tester` 的 `scripts/` 同级约定）。若你维护了独立副本，可显式覆盖 `ATB_BINDGEN_PATH`。

**端到端验证**（环境变量驱动，见 `references/verification-playbook.md`）：

```bash
export ATB_REPO_PATH=/path/to/ascend-transformer-boost
export ATB_BINDGEN_PATH="<SKILLS_DIR>/atb-pybind-bindgen/tools/atb-bindgen"
export CANN_PATH=/usr/local/Ascend/ascend-toolkit
export DOCKER_NAME=your_npu_container   # 可选；不设则在本机执行

bash "${ATB_BINDGEN_PATH}/scripts/run_verify.sh"
```

## 执行前 Checklist

- [ ] `ATB_REPO_PATH` 指向 ascend-transformer-boost 根目录
- [ ] `ATB_BINDGEN_PATH` 指向 **atb-bindgen** 工具目录（默认 `<SKILLS_DIR>/atb-pybind-bindgen/tools/atb-bindgen`；非 ATB 仓库根）
- [ ] `CANN_PATH` 已设置（clang AST 解析，可选）
- [ ] NPU 验证在具备 CANN + NPU 的环境执行（`DOCKER_NAME` 指定容器，或本机）
- [ ] `torch==2.10.0` 与 `torch-npu==2.10.0` 版本对齐（NPU 验证）
- [ ] 新增算子已加入 `config.json` 的 `whitelist` / `operation_ops` / `graph_builder_ops` / `golden_mappings`（若需 forward 测试）
- [ ] 目标仓库已迁移 bindgen 结构（见下文「首次迁移」）；存在 `output/atb/set_env.sh`（否则先编译 testframework 或从已编译仓库同步 `output/` + `3rdparty/`）
- [ ] `operation_wrapper.cpp` 使用 `#include "operation_wrapper_ops.inc"`（勿保留手写构造函数列表）

## 关键路径变量

| 变量 | 说明 | 示例 |
|------|------|------|
| `ATB_REPO_PATH` | ATB 源码根目录 | `/path/to/ascend-transformer-boost` |
| `ATB_BINDGEN_PATH` | atb-bindgen 工具根目录 | `<SKILLS_DIR>/atb-pybind-bindgen/tools/atb-bindgen` |
| `CANN_PATH` | CANN 安装路径 | `/usr/local/Ascend/ascend-toolkit` |
| `DOCKER_NAME` | 可选 Docker 容器名 | 空则本机执行 |

## 完整工作流

### 第一步：运行代码生成器

```bash
cd ${ATB_BINDGEN_PATH}
pip install -r requirements.txt

# 首次迁移或保留手写 param 绑定时
python3 generate.py --bootstrap --atb-repo ${ATB_REPO_PATH}

# 日常增量：重新生成 operation/wrapper/graph_builder 片段（复用已有 bindings_ops.inc）
python3 generate.py --atb-repo ${ATB_REPO_PATH}

# 生成测试（含 CPU golden + NPU forward + check_*）
python3 generate.py --atb-repo ${ATB_REPO_PATH} --tests --force-tests

# 仅当需要从头生成 bindings_ops.inc 时用（会跳过 init_overrides.preserve 算子，勿盲目全量 regenerate）
# python3 generate.py --atb-repo ${ATB_REPO_PATH} --regenerate-params
```

**新增算子 param 绑定**：日常 `generate.py` 不会改写已有 `bindings_ops.inc`。新算子需单独生成 param 块并追加到 `bindings_ops.inc`，或在一轮 bootstrap 后仅对新算子跑 codegen 追加（勿对全表 `--regenerate-params` 除非已理解 preserve 跳过逻辑）。

### 第二步：四文件一致性校验

```bash
python3 validate_consistency.py \
  --config config.json \
  --repo ${ATB_REPO_PATH}
```

校验规则详见 `references/config-schema.md`。

### 第三步：编译安装与验证 Gate

**推荐**：`run_verify.sh`（或 playbook 方式 B 分步手动）。

```bash
export ATB_REPO_PATH=... ATB_BINDGEN_PATH=... CANN_PATH=...
# 可选 DOCKER_NAME=...
bash "${ATB_BINDGEN_PATH}/scripts/run_verify.sh"
```

**仅编译 torch_atb**（不跑测试）时见 playbook「编译关键参数」或 **atb-testframework-build**。

### 第四步：冒烟与精度验证

```bash
source ${ATB_REPO_PATH}/output/atb/set_env.sh --cxx_abi=1
cd ${ATB_REPO_PATH}/tests/apitest

# Param 冒烟（无需 NPU forward，但仍需 ATB 库路径）
python3 -m unittest torch_atb_test.op_test.op_param_test.TestGeneratedParams -v

# Forward 精度 Gate（需 NPU）
export ASCEND_RT_VISIBLE_DEVICES=2
python3 -m unittest discover -s torch_atb_test/op_test -p "*_bindgen_test.py" -v
```

**Gate 标准**：36 param + 12 bindgen golden 全部 OK（随 whitelist / golden_mappings 增减而变化）。

**禁止**：在仓库根目录或 `op_test/` 子目录直接 `python .../xxx_bindgen_test.py`，会 `ModuleNotFoundError: torch_atb_test`。必须在 `tests/apitest` 下用 `python3 -m unittest`（见 verification-playbook）。

## 首次迁移（仓库尚无 bindgen .inc）

若 `src/torch_atb/` 无 `bindings_ops.inc`，且 `bindings.cpp` 仍为整文件手写 param：

1. 用已迁移仓库的 `bindings.cpp`、`operation_wrapper.cpp/.h`、`enger_graph_builder.cpp/.h` 及全部 `*.inc` 作模板，或 `--bootstrap` 后手工合并。
2. 确认 `operation_wrapper.cpp` 在 `ReleaseOperation()` 之后为 `#include "operation_wrapper_ops.inc"`，**不得**保留逐算子手写构造函数。
3. 确认 `CMakeLists.txt` 含 torch_npu HCCL include 优先项（见 troubleshooting）。
4. `python3 generate.py --atb-repo ${ATB_REPO_PATH} --tests --force-tests`
5. 若无 `output/atb`：先 `bash scripts/build.sh testframework`，或从同版本已编译仓库复制 `3rdparty/` + `output/` 再仅重编 `torch_atb`。

## 增量变更场景

| 场景 | 处理方式 |
|------|---------|
| header 新增字段 | 重新 `generate.py`；复杂算子设 `init_overrides.preserve` |
| header 新增算子 | 加入 whitelist + operation_ops/graph_builder_ops，重新生成 |
| 白名单外 struct | 不自动绑定，generate.py 输出 WARN |
| RingMLA 类回归 | 确保 operation_ops 与 graph_builder_ops 四处同步 |
| 新增 golden 算子 | 在 `golden_recipes.py` 扩展 recipe，`config.json` 设 `torch_builtin`/`torch_compose`；对齐 opstest 语义（如 IndexAdd 输出 delta） |
| inplace / workspace 敏感算子 | recipe 中 `run_perf_test` 用 `var_npu.clone()`；suite 内可考虑子进程隔离 forward 测试 |

## Skill 附带资源

| 路径 | 内容 |
|------|------|
| `tools/atb-bindgen/` | 绑定代码生成器（`generate.py`、`validate_consistency.py`、`config.json`、`scripts/`） |

## 生成文件说明

| 文件 | 内容 |
|------|------|
| `bindings_ops.inc` | Param 类绑定 |
| `bindings_operation_inits.inc` | Operation 构造函数注册 |
| `bindings_builder_add_nodes.inc` | Builder.add_node 重载 |
| `operation_wrapper_generated.inc` | wrapper 声明 |
| `operation_wrapper_ops.inc` | wrapper 实现 |
| `enger_graph_builder_generated.inc` | AddNode 声明 |
| `enger_graph_builder_ops.inc` | AddNode 实现 |
| `op_test/<op>/<op>_bindgen_test.py` | CPU golden + NPU forward 精度测试 |

手动区块保留在 `bindings.cpp`（枚举、基础设施类）。详见 `references/binding-patterns.md`。

## 故障排查

| 问题 | 参考 |
|------|------|
| HCCL 头文件冲突 | troubleshooting.md |
| LTO 链接失败 | troubleshooting.md |
| torch/torch_npu 版本不匹配 | troubleshooting.md |
| libasdops 加载失败 | troubleshooting.md + 需 source ATB set_env |
| Split/Gather/IndexAdd golden 失败 | troubleshooting.md |
| ModuleNotFoundError torch_atb_test | troubleshooting.md（测试 cwd 错误） |
| undefined symbol RingMLAParam 等 | troubleshooting.md（wrapper 未迁移到 .inc） |
| 端到端验证步骤 | verification-playbook.md |

## 技能衔接

- **编译**：`atb-testframework-build`（或 playbook 分步编译）
- **端到端 Gate**：`references/verification-playbook.md`（`run_verify.sh` / 手动 8 步）
- **Forward golden 扩展**：`atb-golden-developer` + `golden_recipes.py`
- **仅测试生成**：`atb-pybind-test-generator`
