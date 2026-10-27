# 常见编译与解析错误

## OpParamToJson 未实现（import 时 undefined symbol）

**现象**：`import torch_atb` 报 `undefined symbol: OpParamToJson<...SomeParam>`。

**原因**：部分算子（如 `WhereParam`）C++ 侧未实现 `OpParamToJson` 特化，但 `bindings_ops.inc` 的 `__repr__` 调用了它。

**修复**：将该算子的 `__repr__` 改为简单字符串（如 `return "WhereParam()"`），勿使用 `OpParamToJson`。

## 空字段 Param 的 py::init 语法

**现象**：编译报 `expected primary-expression before ')'` 于 `.def(py::init<>(),)`。

**原因**：仅含 `rsv` 等跳过字段的 struct，codegen 生成尾随逗号。

**修复**：使用 `.def(py::init<>())`（skills 自带 `bindings_ops.inc.j2` 已修复空字段分支）。

## CANN / clang 不可用

设置 `CANN_PATH` 并 `source set_env.sh`；或依赖 regex fallback + init_overrides.preserve。

NPU 环境（物理机或 Docker 容器）内常见路径：`/usr/local/Ascend/ascend-toolkit/set_env.sh`（勿假设 `$CANN_PATH/9.1/set_env.sh` 存在）。

## 四文件一致性失败

确认算子在 operation_ops / graph_builder_ops 中，重新运行 generate.py。

## operation_wrapper.cpp 未迁移（import 时 undefined symbol）

**现象**：

```
ImportError: ... _C.so: undefined symbol: _ZN8TorchAtb16OperationWrapperC1ERKN3atb5infer12RingMLAParamE
```

或 `nm -D _C.so` 显示 `RingMLAParam` 等构造函数为 `U`（未定义）。

**原因**：仓库仍用手写 `OperationWrapper::OperationWrapper(const XxxParam &)` 列表，未 `#include "operation_wrapper_ops.inc"`；链接时缺少 `operation_wrapper_ops.inc` 中的实现。

**修复**：将 `operation_wrapper.cpp` 改为在 `ReleaseOperation()` 之后仅 `#include "operation_wrapper_ops.inc"`，删除手写构造函数块；重新编译安装 whl。

## ModuleNotFoundError: No module named 'torch_atb_test'

**原因**：未在 `tests/apitest` 下运行 unittest，或直接 `python path/to/xxx_bindgen_test.py`。

**修复**：

```bash
cd ${ATB_REPO_PATH}/tests/apitest
python3 -m unittest torch_atb_test.op_test.<op>.<op>_bindgen_test -v
```

## HCCL 头文件版本冲突（编译报错）

**现象**：

```
hccl.h: 'HcclCommConfig' has no member named 'aclGraphZeroCopyEnable'
```

**原因**：CANN toolkit 的 HCCL 头与 `torch_npu` 自带 HCCL 版本不一致；CANN include 优先级更高时会触发。

**修复**：`src/torch_atb/CMakeLists.txt` 中 `$ENV{PYTORCH_NPU_INSTALL_PATH}/include/third_party/hccl/inc` 必须排在 `$ENV{ASCEND_HOME_PATH}/include` **之前**。未迁移的仓库需手动补上该 include（与已 bindgen 仓库对齐）。

## LTO 链接失败（Docker 内）

**现象**：

```
lto-wrapper: fatal error: make returned 2 exit status
/usr/bin/ld: error: lto-wrapper failed
```

**修复**：编译时加 `-DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF`，链接用 `-j1`。

## torch / torch_npu 版本不匹配

**现象**：

```
ImportError: ... _C.so: undefined symbol: _ZN6at_npu6native9OpCommand4NameERKSs
```

**原因**：whl 针对 torch 2.10 编译，但环境中 torch 被降级到 2.9。

**修复**：保持 `torch==2.10.0` 与 `torch-npu==2.10.0` 一致后重新编译安装 whl。

## import torch_atb 时 libasdops.so 加载失败

**现象**：

```
RuntimeError: Failed to load libasdops.so: undefined symbol: ...TbeTilingRunner...
```

**修复**：测试/导入前必须：

```bash
source ${ATB_REPO_PATH}/output/atb/set_env.sh --cxx_abi=1
```

## 新增算子后 import 失败

1. 按 verification-playbook 编译 torch_atb 并安装 whl
2. 运行 `TestGeneratedParams` 验证

## bindgen golden 精度失败

### Split

NPU 返回 **list**（每个 chunk 一个 tensor），golden 应为 `torch.stack(parts)`，**不是** `[torch.stack(parts)]`。参考 `split_test.py`。

### Gather

ATB Gather 与 `torch.gather` 语义不完全一致；golden 需用手写 flatten 逻辑。参考 `gather_test.py`，recipe 在 `golden_recipes.py`。

### IndexAdd

- **输出语义**：NPU 输出为 `index_add` 相对输入 `var` 的 **增量（delta）**，不是完整结果张量。对齐 `tests/apitest/opstest/python/operations/index_add/test_index_add.py` 中 `golden_calc`（`result - input`），勿与 CSV `data_generation.IndexAddOperation.golden`（返回完整 var）混淆。
- **比对函数**：浮点用 `check_float`，不要用 `check_move`。
- **suite 内失败**：gather 等算子的 `run_perf_test`（100 次 forward）会污染 `MemoryManager` workspace，导致后续同进程 IndexAdd 精度失败。recipe 应对 inplace 输入使用 `var_npu.clone()` 做 perf；forward 测试类可用 **子进程** 调用 `run_test()` 隔离。
- **稳定性**：recipe 中建议 `torch.manual_seed(42)` + `torch.npu.synchronize()` 后再比对。

### unittest discover 漏测

`layer_norm/`、`transpose/` 等目录需有 `__init__.py`，否则 discover 只跑 8/10 项。生成器已自动 touch `__init__.py`。

## 复杂默认值解析失败

在 init_overrides 中设 init_style: preserve，手写 param 绑定，其余三文件仍自动生成。
