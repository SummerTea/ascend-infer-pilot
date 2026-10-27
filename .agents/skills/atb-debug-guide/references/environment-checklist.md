# ATB 环境检查与调试检查表

本文为 `atb-debug-guide` 延伸阅读：环境步骤、命令检查表与问题记录模板。

## ATB 环境检查流程

### Step 1: 检查 NPU 设备

```bash
npu-smi info
```

### Step 2: Source 环境

```bash
source <CANN_PATH>/set_env.sh
# 与编译产物一致：优先使用自动检测（与 fn_init_env 输出 cxx_abi_0 / cxx_abi_1 对齐）
source <ATB_REPO_PATH>/output/atb/set_env.sh
# 仅当你明确知道本次编译落在 cxx_abi_1 且需与手动路径一致时再追加，例如：
# source <ATB_REPO_PATH>/output/atb/set_env.sh --cxx_abi=1
```

### Step 3: 验证测试框架

```bash
echo "ATB_HOME_PATH=$ATB_HOME_PATH"
ls -la $ATB_HOME_PATH/lib/libatb_test_framework.so
```

### Step 4: 运行 CSV 测试

```bash
cd <ATB_REPO_PATH>/tests/framework/python/CsvOpsTestTool
python3 atb_csv_ops_test.py -i <CSV_FILE_PATH>
```

---

## 调试检查表

| 检查项 | 命令 | 预期结果 |
|--------|------|----------|
| NPU 设备 | `npu-smi info` | 显示可用设备 |
| ATB_HOME_PATH | `echo $ATB_HOME_PATH` | 指向 cxx_abi_0/1 目录 |
| 测试框架库 | `ls $ATB_HOME_PATH/lib/libatb_test_framework.so` | 文件存在 |
| 依赖库版本 | `ldd $ATB_HOME_PATH/lib/libatb_test_framework.so` | 所有依赖可解析 |
| ACLNN 符号 | `nm -D $ASCEND_TOOLKIT_HOME/lib64/libopapi_nn.so \| grep aclnn` | 符号存在 |
| NZ / `ConvertToAtbTensor` 修复验证 | 见 [error-scenarios.md](error-scenarios.md) 中 **「NZ格式丢失（ConvertToAtbTensor）」** 小节的 **验证方法**：在已 source CANN+ATB 环境下运行 **ND / 2D-NZ / 4D-NZ** 的 **CSV 或 `torch_atb` Linear** 用例（勿用「`contiguous()` 后仍必为 29」的一行 Python 作为唯一判据：其与 PyTorch 语义及 C++ 侧跳过 `contiguous()` 的修复点不对齐，易产生假阳/假阴） |
| 异步析构 | `ASCEND_LAUNCH_BLOCKING=0` 下运行后 `echo $?` | 非 139 (非 segfault) |

---

## 新问题记录模板

```markdown
## 问题名称

**错误信息：**
```
[粘贴错误信息]
```

**日志分析：**
- ATB 日志: [关键行]
- 下层日志: [关键行]

**根本原因：**
[分析原因]

**解决方案：**
[解决方案]

**验证方法：**
[验证命令]
```
