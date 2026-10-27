# 常见错误分类与诊断

本文为 `atb-debug-guide` 延伸阅读：ABI、内存、维度、ACLNN、NZ、异步析构、GDB、析构处理与日志分析。

## 常见错误分类

### ABI 版本不匹配错误

#### 错误信息
```
OSError: /path/to/atb/output/atb/cxx_abi_0/lib/libatb_test_framework.so: cannot open shared object file
```

或

```
undefined symbol: _ZN3atb13OpParamToJson...
```

#### 原因
ATB 输出目录有两个 ABI 版本：
- `cxx_abi_0`: 旧版本（g++/libstdc++abi_0）
- `cxx_abi_1`: 新版本（g++/libstdc++abi_1）

测试框架库和依赖库必须使用相同 ABI 版本。

#### 解决方案

**方案A：使用正确的 set_env.sh 参数**
```bash
source <CANN_PATH>/set_env.sh
source <ATB_REPO_PATH>/output/atb/set_env.sh --cxx_abi=1
echo $ATB_HOME_PATH
```

**方案B：创建软链接（不推荐）**
```bash
ln -s <ATB_REPO_PATH>/output/atb/cxx_abi_1 <ATB_REPO_PATH>/output/atb/cxx_abi_0
```

#### 验证方法
```bash
ls -la $ATB_HOME_PATH/lib/libatb_test_framework.so
ldd $ATB_HOME_PATH/lib/libatb_test_framework.so | grep libatb
```

---

### 内存错误

#### 错误信息
```
ActualError: S:ERROR_OUT_OF_HOST_MEMORY
```

#### 可能原因
1. **输入输出 tensor 数量不匹配**：Runner 中定义的 IN_TENSOR_NUM/OUT_TENSOR_NUM 与接口规格不一致
2. **Shape 计算错误**：输出 shape 计算有误导致内存分配失败
3. **数据太大**：测试用例的 shape 超出设备内存限制

#### 解决方案
1. 检查 Runner 中 IN_TENSOR_NUM 和 OUT_TENSOR_NUM 是否与接口规格匹配
2. 检查 InferShapeImpl 中的 shape 推导逻辑
3. 减小测试用例的 shape 大小

#### 接口规格检查点
```cpp
// 检查接口规格中的输入输出定义
// 例如 SwigluQuant:
// - 输入：1个 [ntokens, 2*hidden_size]
// - 输出：2个 [ntokens, hidden_size] + [ntokens]
// Runner 必须匹配这些规格
```

---

### Tensor 维度错误

#### 错误信息
```
ActualError: I:ERROR_INVALID_TENSOR_DIM_NUM
ActualError: I:ERROR_INVALID_TENSOR_DIM
```

#### 检查点
1. 输入 tensor 维度数量是否符合预期（通常为 2D）
2. 特定维度值是否在有效范围内
3. 维度是否能被指定值整除（如 hidden size 必须能被 2 整除）

---

### 数据类型错误

#### 错误信息
```
ActualError: I:ERROR_INVALID_TENSOR_INI_MATCH
KeyError: 'float32'
```

#### 原因
1. 输入数据类型不支持（如 float32 不在 data_generation.py 的 dtype_dict 中）
2. 输出数据类型与期望不符

#### 解决方案
在 CSV 中使用 data_generation.py 支持的数据类型：
- `float` (对应 float32)
- `float16` / `half`
- `bf16` / `bfloat16`
- `int8` / `char`
- `int32` / `int`
- `int64` / `long`

---

### ACLNN 函数签名不匹配

#### 错误信息
```
undefined symbol: aclnn{xxx}QuantGetWorkspaceSize
ActualError: S:ERROR_CANN_ERROR (161001, 161002)
```

#### 原因
1. 函数名拼写错误
2. 函数参数数量/类型与 ACLNN API 不匹配
3. 动态库加载失败

#### 解决方案
```bash
# 检查函数符号
nm -D <ATB_PATH>/output/atb/cxx_abi_1/lib/libatb.so | grep -i {xxx}

nm -D $ASCEND_TOOLKIT_HOME/lib64/libopapi_nn.so | grep -i {xxx}
```

#### ACLNN 错误码
| 错误码 | 名称 | 含义 |
|--------|------|------|
| 161001 | ACLNN_ERR_PARAM_NULLPTR | 参数为空指针（如 x/yOut 为空） |
| 161002 | ACLNN_ERR_PARAM_INVALID | 参数类型/维度/取值无效 |

---

### ACLNN MoE 场景不匹配

#### 问题描述
**问题**: ATB 算子为非 MoE 场景设计，但 ACLNN 接口仅支持 MoE 场景。

#### 典型案例
**{xxx}Quant**:
- ATB 设计: 非 MoE Per-Token 动态量化
- ACLNN: 仅支持 MoE 分组动态量化，需要 `groupIndex` 和 `smoothScales`

#### 错误信息
```
[ERROR] errno[161001] Check yOut != nullptr failed
```

实际上由于 `smoothScalesOptional` 和 `groupIndexOptional` 不支持空指针（当前版本）。

#### 解决方案

**方案A：回退到 OPS 实现（推荐）**
```cpp
// 禁用 ACLNN 路径
std::shared_ptr<Runner> XxxOperation::CreateRunner(Context &context) const
{
    // TODO: 待 ACLNN 支持非 MoE 场景后启用
    return std::make_shared<XxxOpsRunner>(param_);
}
```

**方案B：构造 MoE 参数模拟非 MoE（复杂，不推荐）**
- 构造单分组 `groupIndex`
- 构造全 1 `smoothScales`

#### 如何识别
查阅 ACLNN 文档：
> "当前 xxx 仅支持 MoE 场景"

---

### NZ格式丢失（ConvertToAtbTensor）

#### 错误信息
```
[info] inTensorDescs[1]:dtype: float16, format: nd, shape:[48, 32, 16, 16]
[error] inTensor1 dim num should be 2 or 3, inTensor1 dimNum = 4.
```

或 Python 侧：
```
RuntimeError: call operation_->InferShape fail
[ERROR] ERR99999 UNKNOWN applicaiton exception
```

#### 日志定位方法
在 Python 中打印 tensor 状态：
```python
import torch_npu
t = ...  # 怀疑格式不对的 tensor
print(f'shape={list(t.shape)}, format={int(torch_npu.get_npu_format(t))}, contiguous={t.is_contiguous()}')
# NZ format = 29, ND format = 2
# NZ tensor 通常 contiguous=False
```

模拟 ConvertToAtbTensor 行为确认根因：
```python
# contiguous() 会改变格式！
t_after = t.contiguous()
print(f'after contiguous: format={int(torch_npu.get_npu_format(t_after))}')
# 如果 NZ→ND，说明 contiguous() 破坏了格式
```

#### 原因
`src/torch_atb/resource/utils.cpp` 的 `ConvertToAtbTensor` 函数中：

1. `contiguous()` 在 `get_npu_format()` 之前调用
2. NZ（Fractal NZ）分形布局本质非连续，`is_contiguous()` 返回 False
3. `contiguous()` 将 NZ 物理布局转为 ND → 格式丢失
4. 后续 `get_npu_format()` 返回 ND，但 shape 仍是 NZ 的 4D 逻辑 shape
5. ATB 算子看到 format=ND, shape=[b, n/16, k, 16] → 校验失败

#### 解决方案
在 `contiguous()` 之前保存格式，对 NZ 跳过 `contiguous()`：

```cpp
// utils.cpp ConvertToAtbTensor()
aclFormat originalFormat = ACL_FORMAT_ND;
if (!torchTensor.is_cpu()) {
    originalFormat = static_cast<aclFormat>(at_npu::native::get_npu_format(torchTensor));
}

// NZ 格式跳过 contiguous()，避免格式丢失
if (originalFormat != ACL_FORMAT_FRACTAL_NZ && !torchTensor.is_contiguous()) {
    torchTensor = torchTensor.contiguous();
}

// 使用保存的原始格式
if (!torchTensor.is_cpu()) {
    atbTensor.desc.format = originalFormat;
    atbTensor.deviceData = torchTensor.data_ptr();
}
```

#### 验证方法

**推荐**：在已 `source` CANN 与 `<ATB_REPO_PATH>/output/atb/set_env.sh`（**勿硬编码 `--cxx_abi`**，与当前 `cxx_abi_0/` 或 `cxx_abi_1/` 产物一致）后，从 ATB 仓库运行 **torch_atb Linear NZ** 单测（与 `atb-testframework-build` 技能中「运行单个算子测试」一致），例如：

```bash
source <CANN_PATH>/set_env.sh
source <ATB_REPO_PATH>/output/atb/set_env.sh
cd <ATB_REPO_PATH>/tests/apitest
ASCEND_LAUNCH_BLOCKING=1 python3 -m unittest torch_atb_test.op_test.linear.linear_nz_test -v
```

对 **ND / 2D-NZ / 4D-NZ** 等变体，以你仓内实际用例名为准（可用 `rg "linear.*nz" tests/apitest/torch_atb_test` 检索）；**三种场景均 PASS** 即表明 NZ→ATB 张量路径在该环境下可用。上文 Python 片段仅用于**理解** `contiguous()` 与 format 变化，**不作为**唯一自动化验收命令。

---

### 异步模式析构Segfault

#### 错误信息
```
Segmentation fault (core dumped)  # exit code 139
```

GDB 栈常见于 TBE worker 线程：
```
#0  __dynamic_cast () from libstdc++.so.6
#1  atb::Runner::GetExecuteStream(atb::Context*) () from libatb.so
...
#5  atb::OperationBase::Execute(...) () from libatb.so
#6-9  libtorch_npu.so (TBE TaskQueue worker thread)
#12  libc.so.6 (clone/start_thread)
```

#### 根因：`cmd.Run()` 是 fire-and-forget

`OpCommand::Run()` 将 lambda 异步分发到 TBE worker 线程后立即返回。
lambda 捕获 `this`（OperationWrapper*），worker 线程延迟执行时 OperationWrapper 可能已析构。
**`aclrtSynchronizeStream` 只能同步 NPU stream，无法等待 TBE worker 线程。**

真实时序（GDB 证实）：
```
T0: cmd.Run()                     ← lambda 入队，立即返回
T1: aclrtSynchronizeStream        ← NPU stream 空闲（lambda 还没跑），空操作！
T2: Forward() 返回 → 析构
T3: TBE worker 开始执行 lambda     ← this 已失效 → segfault
```

#### 解决方案（3 处修改）

**1. Execute() — 移除 OpCommand，直接调用**：
```cpp
// operation_wrapper.cpp Execute()
if (Utils::IsTaskQueueEnable()) {
    // 不使用 OpCommand/cmd.Run()（fire-and-forget，无法 sync）
    Status st = operation_->Execute(variantPack_, workspace, workspaceSize_, context);
    if (st != NO_ERROR) {
        throw std::runtime_error("call operation_->Execute fail");
    }
    return;
}
```

**2. Forward() — TaskQueue 路径 sync**：
```cpp
// operation_wrapper.cpp Forward()
Execute();
if (Utils::IsTaskQueueEnable()) {
    // Execute() 异步，Forward() 层级 sync 保证 kernel 完成
    aclrtSynchronizeStream(context->GetExecuteStream());
}
```

**3. ~OperationWrapper() — 安全网**：
```cpp
~OperationWrapper() {
    try {
        aclrtSynchronizeStream(context->GetExecuteStream());
    } catch (...) {
        ATB_LOG(ERROR) << "OperationWrapper destructor sync failed";
    }
}
```

#### 为什么不在 Execute() 中 sync
ATB 设计支持 setup→execute×N→sync 批量下发。Execute() 保持异步，Forward() 统一 sync。

#### 验证方法
```bash
python -c "..."  # 默认异步模式，exit code 应为 0
echo $?  # 非 139
```

---

### GDB Core Dump 分析

#### 基本命令

```bash
# 查看 core 文件基本信息
file core.xxx

# 分析 core（非交互式，推荐）
gdb /usr/local/python3.11.15/bin/python core.xxx -batch \
  -ex "info threads" \
  -ex "thread apply all bt"

# 查看崩溃信号
gdb ... -ex "info signal"
```

#### 分析要点

1. **先看哪个线程崩**: `info threads` 标 `*` 的是崩溃线程
2. **看主线程在哪**: 通常 thread 1，如在 `npuSynchronizeUsedDevices` → Python atexit shutdown
3. **看崩溃线程栈**: 确认崩溃位置和动态库
4. **对比主线程和崩溃线程时间序**: 判断是否延迟执行 use-after-free

#### 常见信号

| 信号 | 含义 |
|------|------|
| SIGSEGV (11) | 段错误，访问无效内存 |
| SIGABRT (6) | 断言失败 |
| SIGKILL (9) | OOM killer |

#### 典型 use-after-free 特征
- 崩溃线程在 `libtorch_npu.so` TBE worker 线程
- 主线程在 `npuSynchronizeUsedDevices`（atexit）
- #0 是垃圾地址，说明 vtable/kernel 已释放

---

### 析构函数错误处理

#### 问题
```cpp
catch (...) {
}  // 空块，吞掉 aclrtSynchronizeStream 错误
```

#### 修复
```cpp
catch (...) {
    ATB_LOG(ERROR) << "OperationWrapper destructor sync failed, device may have been reset";
}
```

---

### 日志分析方法

#### 日志位置

| 日志类型 | 路径 | 内容 |
|----------|------|------|
| ATB 日志 | `<MY_DIR>/log/<log_name>/atb/atb_*.log` | ATB 算子调度、infershape、setup |
| 下层组件日志 | `<MY_DIR>/log/<log_name>/debug/plog/plog-*.log` | GE、RUNTIME、OP、ASCENDCL |

#### ATB 日志关键字
```bash
# 查找 ACLNN 加载
grep -i "aclnn\|LoadMethod\|workspace" atb_*.log

# 查找错误
grep -i "error\|fail\|ERROR" atb_*.log

# 查找测试用例执行
grep -i "Case\|times" atb_*.log
```

#### 下层组件日志关键字
```bash
# 查找 ACLNN 底层错误
grep -i "161001\|161002\|errno" plog-*.log

# 查找 kernel 执行
grep -i "kernel\|execute" plog-*.log

# 查找内存分配
grep -i "malloc\|aclrtMalloc" plog-*.log
```

#### 典型日志分析流程

1. **ATB 层** (atb_*.log): 检查算子创建、Runner 选择、shape 推导
2. **接口层** (plog-*.log OP/GE): 检查 ACLNN 接口调用、参数校验
3. **运行时层** (plog-*.log RUNTIME): 检查 kernel 执行、内存分配

