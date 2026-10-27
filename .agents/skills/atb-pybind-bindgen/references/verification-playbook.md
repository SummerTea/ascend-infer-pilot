# Bindgen 端到端验证 Playbook

在 **NPU 可用环境**（物理机或 Docker 容器）内跑通：一致性校验 → 编译 `torch_atb` → 安装 whl → unittest Gate。

验证不绑定特定容器名；通过环境变量配置路径与设备。

## 方式 A：脚本一键（推荐）

`atb-bindgen/scripts/` 下两个脚本：

| 脚本 | 用途 |
|------|------|
| `verify_bindgen.sh` | 验证主流程（在**已具备 CANN/NPU 的 shell** 内执行） |
| `run_verify.sh` | 可选 Docker 包装：设置 `DOCKER_NAME` 时在容器内执行 `verify_bindgen.sh` |

```bash
export ATB_REPO_PATH=/path/to/ascend-transformer-boost
export ATB_BINDGEN_PATH="<SKILLS_DIR>/atb-pybind-bindgen/tools/atb-bindgen"    # 含 generate.py 的目录
export CANN_PATH=/usr/local/Ascend/ascend-toolkit
export DOCKER_NAME=your_npu_container          # 无则在本机执行
export ASCEND_RT_VISIBLE_DEVICES=2

bash "${ATB_BINDGEN_PATH}/scripts/run_verify.sh"
```

日志默认：`/tmp/atb_bindgen_verify.log`（可用 `ATB_BINDGEN_VERIFY_LOG` 覆盖）。

### 常用环境变量

| 变量 | 说明 | 默认 |
|------|------|------|
| `ATB_REPO_PATH` | ATB 源码根目录 | 必填 |
| `ATB_BINDGEN_PATH` | `atb-bindgen` 工具根目录 | 必填 |
| `CANN_PATH` / `ASCEND_HOME_PATH` | CANN 安装根 | `/usr/local/Ascend/ascend-toolkit` |
| `DOCKER_NAME` | 非空则 `docker exec` 进容器跑验证 | 空（本机） |
| `ASCEND_RT_VISIBLE_DEVICES` | NPU 设备号 | `2` |
| `TORCH_VERSION` | torch / torch_npu 对齐版本 | `2.10.0` |
| `CMAKE_BUILD_PARALLEL` | cmake build 并行度 | `1` |
| `ATB_CXX_ABI_FLAG` | `source output/atb/set_env.sh` 参数 | `--cxx_abi=1` |
| `SKIP_TORCH_ALIGN` | `1` 跳过 pip 装 torch | `0` |
| `SKIP_NPU_FORWARD_TESTS` | `1` 跳过 Step 8 forward | `0` |

**多仓库**：`ATB_BINDGEN_PATH` 与 `ATB_REPO_PATH` 可指向不同目录；只改 `ATB_REPO_PATH` 即可验证另一份 `ascend-transformer-boost`。

**兼容**：旧名 `verify_in_rzh.sh` 已弃用，内部转调 `run_verify.sh`；需容器时请显式设置 `DOCKER_NAME`。

## 方式 B：分步手动（skills 通用、无脚本依赖）

与 `verify_bindgen.sh` 步骤一致，便于在 CI 或自定义环境中拆开执行：

1. `source ${CANN_PATH}/set_env.sh`
2. （可选）对齐 `torch` / `torch_npu` 版本
3. `python3 ${ATB_BINDGEN_PATH}/validate_consistency.py --repo ${ATB_REPO_PATH}`
4. 编译安装 `torch_atb`（见下文「编译关键参数」）
5. 打包并 `pip install --force-reinstall` whl
6. `source ${ATB_REPO_PATH}/output/atb/set_env.sh` 后 `import torch_atb` 冒烟
7. 在 `${ATB_REPO_PATH}/tests/apitest` 下跑 `TestGeneratedParams`
8. 同目录下 `discover -p "*_bindgen_test.py"`（需 NPU）

通过标准：Step 3 为 `[PASS]`；Step 7、8 的 unittest 输出以 `OK` 结尾（用例数量随 whitelist / golden_mappings 变化，**不写死**）。

## 前置条件

| 条件 | 说明 |
|------|------|
| `output/atb/set_env.sh` | Step 4 前必须存在；无则先 `bash scripts/build.sh testframework`，或从同版本已编译仓库复制 `output/` + `3rdparty/` |
| bindgen 结构 | `bindings.cpp` / `operation_wrapper.cpp` 应 `#include` 对应 `.inc` |
| `tests/apitest` | unittest 的 **工作目录** |

## 编译 torch_atb 关键参数

```bash
source ${CANN_PATH}/set_env.sh
source ${ATB_REPO_PATH}/output/atb/set_env.sh --cxx_abi=1
export LD_LIBRARY_PATH="/usr/local/Ascend/driver/lib64/common:/usr/local/Ascend/driver/lib64/driver:${LD_LIBRARY_PATH}"

export PYTHON_INCLUDE_PATH="$(python3 -c 'from sysconfig import get_paths; print(get_paths()["include"])')"
export PYTORCH_INSTALL_PATH="$(python3 -c 'import torch, os; print(os.path.dirname(os.path.abspath(torch.__file__)))')"
export PYTORCH_NPU_INSTALL_PATH="$(python3 -c 'import torch_npu, os; print(os.path.dirname(os.path.abspath(torch_npu.__file__)))')"
export LD_LIBRARY_PATH="${PYTORCH_INSTALL_PATH}/../torch.libs:${LD_LIBRARY_PATH}"

cmake -S src/torch_atb -B build/src/torch_atb \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF
cmake --build build/src/torch_atb --parallel 1
cmake --install build/src/torch_atb
```

要点：

1. **HCCL 头文件**：`CMakeLists.txt` 中 `torch_npu` 自带 HCCL include 须排在 CANN 之前。
2. **关闭 LTO**：`-DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF`。
3. **torch 版本对齐**：`torch` 与 `torch_npu` 同主版本。
4. **ATB 库**：`import torch_atb` 前 `source output/atb/set_env.sh`。

## 手动精度测试（Step 7 / 8 细化）

**必须在 `tests/apitest` 下执行**：

```bash
source ${CANN_PATH}/set_env.sh
source ${ATB_REPO_PATH}/output/atb/set_env.sh --cxx_abi=1
export ASCEND_RT_VISIBLE_DEVICES=2
cd ${ATB_REPO_PATH}/tests/apitest

python3 -m unittest torch_atb_test.op_test.op_param_test.TestGeneratedParams -v
python3 -m unittest discover -s torch_atb_test/op_test -p "*_bindgen_test.py" -v
```

勿在仓库根目录直接 `python .../xxx_bindgen_test.py`（会 `ModuleNotFoundError: torch_atb_test`）。

## 当前 bindgen golden 覆盖（11 算子）

Split, Concat, Softmax, LayerNorm, Gather, Transpose, Elewise, Activation, RmsNorm, Linear, IndexAdd

未生成 forward：`comm_skip` / `skip_npu`（如 AllGather、SelfAttention）。
