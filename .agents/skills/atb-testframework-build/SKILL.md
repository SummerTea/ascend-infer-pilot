---
name: atb-testframework-build
description: >
  编译 ATB (Ascend Transformer Boost) 测试框架。当用户需要编译 ATB 测试框架、
  torch_atb、运行 CSV 测试、或构建 atb_test_framework 时调用。
  支持全量编译和增量编译两种模式。需在 Docker 容器内配合 CANN 环境执行。
keywords:
    - atb
    - ascend-transformer-boost
    - testframework
    - build
    - compile
    - csv-test
    - torch_atb
    - 昇腾
metadata:
  version: "1.3.2"
  updated: "2026-05-12"
  skill-type: build
hooks:
  PreToolUse:
    - matcher: "Write|Edit|Bash"
      hooks:
        - type: command
          command: "([ -z \"$CANN_PATH\" ] || [ ! -f \"$CANN_PATH/set_env.sh\" ]) && { echo '[PATH CHECK] CANN_PATH 未设置或无效，请先向用户获取 CANN 路径' >&2; exit 1; }; ([ -z \"$ATB_REPO_PATH\" ] || [ ! -d \"$ATB_REPO_PATH\" ]) && { echo '[PATH CHECK] ATB_REPO_PATH 未设置或无效，请先向用户获取 ATB 路径' >&2; exit 1; }"
  PostToolUse:
    - matcher: "Write|Edit"
      hooks:
        - type: command
          command: "echo '[COMPILE LIMIT] 编译验证最多 3 次。若第 3 次失败，必须停止并记录错误、向用户提问。'"
---

# ATB 测试框架编译

## Quick Reference

**用途**：完成 ATB 测试框架全量/增量编译，并确保产物可用于 CSV 测试。

**渐进式披露阅读顺序**：
1. 先完成「执行前 Checklist」确认编译模式与路径
2. 再看「调用时机」判断是否需要立即编译
3. 最后按增量或全量路径执行详细步骤

## 执行前 Checklist

- [ ] 已确认 `CANN_PATH`、`ATB_REPO_PATH`、`DOCKER_NAME`
- [ ] 已确认 `testframework` 与 `torch_atb` / `apitest` 均在容器内执行时使用同一 `DOCKER_NAME` 与路径挂载
- [ ] 已确认本次是增量编译还是全量编译
- [ ] 已确认 cpp 改动后必须先编译再测试
- [ ] 已确认最多尝试 3 次，超过即中断并反馈

## 功能概述

此技能提供 ATB (Ascend Transformer Boost) 测试框架的编译指导，包括全量编译（含第三方依赖克隆与源替换）和增量编译两种模式。

## 调用时机

在以下情况下调用此技能：
- 用户需要编译 ATB 测试框架
- 用户需要运行 CSV 测试但测试框架未编译
- 用户需要从零开始构建 ATB 项目
- 用户遇到第三方依赖克隆失败的问题

## 强制规则

**每次修改 cpp 源码后，必须重新进行增量编译**，才能运行 CSV 测试。cpp 改动不会自动生效，必须通过 `libatb_test_framework.so` 重新链接才能加载新代码。

流程：**修改 cpp → 增量编译 → 运行测试**。跳过编译直接运行测试是无效的。

## 前置条件

- Docker 容器已启动
- CANN 环境已安装
- ATB 源码仓库已克隆

## 关键路径变量

在执行编译前，需确认以下路径变量（从用户处获取）：

| 变量 | 说明 | 示例 |
|---|---|---|
| `<CANN_PATH>` | CANN 安装根目录，包含 `set_env.sh` | `/path/to/cann` |
| `<ATB_REPO_PATH>` | ATB 源码仓库根目录 | `/path/to/ascend-transformer-boost` |
| `<DOCKER_NAME>` | Docker 容器名称 | `<YOUR_DOCKER_NAME>` |

## 编译模式选择

### 增量编译

当 `3rdparty/` 目录已存在且第三方依赖完整时，直接执行增量编译：

```bash
docker exec <DOCKER_NAME> bash -c "
source <CANN_PATH>/set_env.sh && \
cd <ATB_REPO_PATH> && \
bash scripts/build.sh testframework
"
```

**适用场景**：第三方依赖已就绪，仅需重新编译 ATB 源码。

### 全量编译

当 `3rdparty/` 目录为空或不存在时，需要全量编译，包括第三方依赖的克隆。由于 Docker 容器内可能无法访问 GitHub，需要先进行源替换。

<details>
<summary>GitHub→gitcode 源替换（点击展开）</summary>

#### 第1步：替换 GitHub 源为 gitcode 镜像

ATB 的 `scripts/build.sh` 中包含多个 GitHub 依赖，在国内网络环境下需要替换为 gitcode.com 镜像。

**需要替换的源映射表**：

| 原始 GitHub URL | gitcode 替换 URL | build.sh 中的函数 |
|---|---|---|
| `https://github.com/nlohmann/json.git` | `https://gitcode.com/nlohmann/json.git` | `fn_build_nlohmann_json` |
| `https://github.com/google/googletest.git` | `https://gitcode.com/google/googletest.git` | `fn_build_googletest` |
| `https://github.com/coolxv/cpp-stub.git` | `https://gitcode.com/coolxv/cpp-stub.git` | `fn_build_stub` |
| `https://github.com/pybind/pybind11.git` | `https://gitcode.com/pybind/pybind11.git` | `fn_build_pybind11` |
| `https://github.com/doxygen/doxygen/releases/download/Release_1_9_6/doxygen-1.9.6.src.tar.gz` | 使用 `git clone --branch Release_1_9_6 --depth 1 https://gitcode.com/doxygen/doxygen.git` 替代 wget | `fn_build_doxygen` |

**替换命令**：

```bash
cd <ATB_REPO_PATH>
sed -i 's|https://github.com/nlohmann/json.git|https://gitcode.com/nlohmann/json.git|g' scripts/build.sh
sed -i 's|https://github.com/google/googletest.git|https://gitcode.com/google/googletest.git|g' scripts/build.sh
sed -i 's|https://github.com/coolxv/cpp-stub.git|https://gitcode.com/coolxv/cpp-stub.git|g' scripts/build.sh
sed -i 's|https://github.com/pybind/pybind11.git|https://gitcode.com/pybind/pybind11.git|g' scripts/build.sh
```

**doxygen 替换说明**：doxygen 的 wget 下载需要改为 git clone 方式，修改 `fn_build_doxygen` 函数：

```bash
# 将 wget + tar 方式替换为 git clone
# 原始代码:
#   [[ ! -f "doxygen-1.9.6.src.tar.gz" ]] && wget --no-check-certificate https://github.com/doxygen/doxygen/releases/download/Release_1_9_6/doxygen-1.9.6.src.tar.gz
#   tar -xzvf doxygen-1.9.6.src.tar.gz
#   mv doxygen-1.9.6 doxygen
# 替换为:
#   [[ ! -d "doxygen" ]] && git clone --branch Release_1_9_6 --depth 1 https://gitcode.com/doxygen/doxygen.git
```
</details>

#### 第2步：清理旧构建产物（可选）

```bash
cd <ATB_REPO_PATH>
rm -rf build output 3rdparty
```

#### 第3步：执行全量编译

```bash
docker exec <DOCKER_NAME> bash -c "
source <CANN_PATH>/set_env.sh && \
cd <ATB_REPO_PATH> && \
bash scripts/build.sh testframework
"
```

## 编译产物验证

编译成功后，检查关键产物：

```bash
# 检查测试框架库
ls -lh <ATB_REPO_PATH>/output/atb/cxx_abi_0/lib/libatb_test_framework.so

# 检查 ATB 主库
ls -lh <ATB_REPO_PATH>/output/atb/cxx_abi_0/lib/libatb.so
```

**预期产物**：
- `libatb_test_framework.so` — 测试框架核心库
- `libatb.so` — ATB 主库
- `atb_testframework_<arch>_<timestamp>.tar.gz` — 打包文件

## 编译后环境设置

编译完成后，设置环境变量以运行 CSV 测试：

```bash
source <ATB_REPO_PATH>/output/atb/set_env.sh
```

或手动设置：

```bash
export ATB_HOME_PATH=<ATB_REPO_PATH>/output/atb/cxx_abi_0
export LD_LIBRARY_PATH=<ATB_REPO_PATH>/output/atb/cxx_abi_0/lib:$LD_LIBRARY_PATH
```

## 运行 CSV 测试

```bash
cd <ATB_REPO_PATH>/tests/framework/python/CsvOpsTestTool
python3 atb_csv_ops_test.py -i <csv_file_path> -n <start>:<end>
```

<details>
<summary>第三方依赖说明（点击展开）</summary>

`testframework` 构建所需的第三方依赖：

| 依赖 | 源 | 用途 |
|---|---|---|
| nlohmannJson | gitcode.com/nlohmann/json (v3.11.3) | JSON 解析库 |
| Mind-KernelInfra (mki) | gitcode.com/cann/ascend-boost-comm | 内核基础设施 |
| catlass | gitcode.com/cann/catlass | 矩阵运算库 |
| compiler | CANN 路径符号链接 | 编译器工具链 |

**注意**：`testframework` 不需要 googletest、cpp-stub、pybind11、doxygen（这些是 unittest/fuzztest/doc 构建模式所需）。但如果使用其他构建模式（如 `alltest`、`unittest`），也需要替换对应的 GitHub 源。
</details>

## CXX ABI 版本

编译时 `USE_CXX11_ABI` 由 `fn_init_env` 函数自动检测：
- 检查系统安装的 torch 是否使用 CXX11 ABI
- 输出目录为 `output/atb/cxx_abi_0/` 或 `output/atb/cxx_abi_1/`

<details>
<summary>故障排查（点击展开）</summary>

| 问题 | 原因 | 解决方案 |
|---|---|---|
| `git clone` 失败 (curl 16) | GitHub 网络不通 | 替换为 gitcode 镜像源 |
| `ASCEND_HOME_PATH is null` | 未 source CANN 环境 | 先执行 `source <CANN_PATH>/set_env.sh` |
| `libatb_test_framework.so` 不存在 | 编译未完成或失败 | 检查编译日志，确保 `BUILD_TEST_FRAMEWORK=ON` |
| 第三方依赖克隆 403 | gitcode 仓库路径错误 | 确认 gitcode 上的仓库路径和标签 |
</details>

### 修改文件后重新编译

当修改了 `*_aclnn_runner.cpp`、`*_operation.cpp` 等源码后，需要重新编译：

```bash
# 在 Docker 容器内执行（已在容器中）
source $ASCEND_TOOLKIT_HOME/set_env.sh
cd $ATB_REPO_PATH
bash scripts/build.sh testframework 2>&1 | tail -50
```

> **注意**：确保环境变量已设置：
> - `ASCEND_TOOLKIT_HOME`（CANN 安装路径，如 `/usr/local/Ascend/ascend-toolkit/latest`）
> - `ATB_REPO_PATH`（ATB 仓库路径，如 `{your working path}ascend-transformer-boost`）

**编译失败处理流程**：

| 失败次数 | 操作 | 说明 |
|---------|------|------|
| 第1次失败 | 分析日志，定位问题，修复后重新编译 | 正向分析错误原因 |
| 第2次失败 | `rm -rf build/ output/` 清理后重新编译 | 清理 cmake 缓存 |
| 第3次失败 | `bash scripts/build.sh testframework --clean-first` | 从头编译，完整清理 |

**编译约束规则**：
- **最多验证 3 次**：3次均失败时，记录完整错误信息，询问用户
- **Step by Step**：每次只修复一个问题，重新编译验证
- **无法解决时**：记录问题并询问用户

## torch_atb 编译与安装

与上文 **testframework** 一致：`torch_atb` 的编译、wheel 安装与 `apitest` 均在 **Docker 容器内**执行（`docker exec <DOCKER_NAME> ...`），以便使用容器内的 CANN 与 Python。若 CANN 仅装在容器内，在宿主机直接 `source <CANN_PATH>/set_env.sh` 会失败，与「执行前 Checklist」中的 `DOCKER_NAME` 要求一致。

修改 `src/torch_atb/` 下的 cpp 源码后，需要重新编译 torch_atb 并安装 whl 包。

**bindgen 迁移仓库**：若 `CMakeLists.txt` 未将 `torch_npu` 自带 HCCL include 置于 CANN 之前，编译会报 `HcclCommConfig` 字段错误。见 `atb-pybind-bindgen/references/troubleshooting.md`（HCCL 头文件冲突）。

### 编译命令

```bash
docker exec <DOCKER_NAME> bash -c '
source <CANN_PATH>/set_env.sh && cd <ATB_REPO_PATH> && bash scripts/build.sh --torch_atb
'
```

产物目录：`<ATB_REPO_PATH>/output/whl/`（wheel 文件名随 ATB 版本与 Python 标签变化，**勿硬编码**）。

### 安装（定位最新 wheel 与 pip 共用同一段逻辑）

在容器内选取**最新**的 `torch_atb-*.whl` 并安装；无匹配文件时退出，避免向 pip 传入空路径：

```bash
docker exec <DOCKER_NAME> bash -c '
source <CANN_PATH>/set_env.sh && cd <ATB_REPO_PATH> &&
WHL=$(ls -1t output/whl/torch_atb-*.whl 2>/dev/null | head -1) &&
if [ -z "$WHL" ]; then echo "[ERROR] 未找到 torch_atb whl，请确认 bash scripts/build.sh --torch_atb 已成功" >&2; exit 1; fi &&
pip install --force-reinstall --no-deps "$WHL"
'
```

**必须使用 `--force-reinstall`** 覆盖已装 wheel；**建议同时加 `--no-deps`**，避免 pip 顺带重装 `torch`/`numpy` 等大型依赖导致环境漂移。不能只用 `cp _C.so` 替换。

### 运行 torch_atb 测试

```bash
docker exec <DOCKER_NAME> bash -c '
source <CANN_PATH>/set_env.sh &&
source <ATB_REPO_PATH>/output/atb/set_env.sh &&
cd <ATB_REPO_PATH>/tests/apitest &&
python3 -m unittest discover -s . -p "*_test.py" -v
'
```

**注意**：必须从 `tests/apitest` 目录下运行，保证 `torch_atb_test` 作为包可被正确导入。与编译输出一致：由 `output/atb/set_env.sh` 选择 `cxx_abi_0` / `cxx_abi_1`，勿在文档中写死 `--cxx_abi=1`（CXX11_ABI=0 环境会指向错误目录）。

### 运行单个算子测试

```bash
docker exec <DOCKER_NAME> bash -c '
source <CANN_PATH>/set_env.sh &&
source <ATB_REPO_PATH>/output/atb/set_env.sh &&
cd <ATB_REPO_PATH>/tests/apitest &&
python3 -m unittest <package>.<module> -v
'
```

例如将 `<package>.<module>` 换为 `torch_atb_test.op_test.index_add.index_add_bindgen_test.TestIndexAddBindgen`。

**勿**在仓库根目录直接 `python tests/apitest/.../xxx_bindgen_test.py`；必须在 `tests/apitest` 下用 `python3 -m unittest`（见 `atb-pybind-bindgen/references/verification-playbook.md`）。

---

**编译错误记录模板**：

```
### 编译失败记录 (#N)

**错误信息**：
```
<编译器输出>
```

**问题分析**：
<分析原因>

**修改计划**：
1. <修改步骤1>
2. <修改步骤2>

**状态**：待用户确认
```

## 执行结果

> ⚠️ **执行后填写**：技能执行完成后，参照下方格式填写实际执行结果。

### 检查点检查表

| 步骤 | 检查点描述 | 状态 |
|------|-----------|------|
| - | CANN 环境 sourced (`ASCEND_TOOLKIT_HOME` 已设置) | ✅ PASS / ❌ FAIL / ⏭️ SKIP |
| - | Docker 容器运行中 | ✅ PASS / ❌ FAIL / ⏭️ SKIP |
| - | ATB 源码目录存在 | ✅ PASS / ❌ FAIL / ⏭️ SKIP |
| 1 | GitHub→gitcode 源替换已应用 | ✅ PASS / ❌ FAIL / ⏭️ SKIP |
| 2 | `libatb.so` 编译产物存在 | ✅ PASS / ❌ FAIL / ⏭️ SKIP |
| 2 | `libatb_test_framework.so` 编译产物存在 | ✅ PASS / ❌ FAIL / ⏭️ SKIP |
| 2 | CXX ABI 目录命名正确 | ✅ PASS / ❌ FAIL / ⏭️ SKIP |
| 3 | `ATB_HOME_PATH` 指向输出目录 | ✅ PASS / ❌ FAIL / ⏭️ SKIP |
| 3 | `LD_LIBRARY_PATH` 包含 ATB lib | ✅ PASS / ❌ FAIL / ⏭️ SKIP |
| 4 | CSV 测试可正常启动 | ✅ PASS / ❌ FAIL / ⏭️ SKIP |

**VERDICT: ✅ SUCCESS / ⚠️ PARTIAL / ❌ FAILED / ⏭️ SKIPPED**

### 问题列表（若有）

| 等级 | 检查点 | 问题描述 | 建议 |
|------|--------|---------|------|
| 🔴 CRITICAL | - | - | - |
| 🟡 WARNING | - | - | - |

### 执行摘要

- **执行时间**：
- **执行环境**：
- **ATB_REPO_PATH**：
- **持续时间**：
- **通过率**：
