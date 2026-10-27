# Kernel Dependencies 提取规则（Step 6）

## 目标

提取 Kernel 清单、Tiling 约束、Workspace 计算公式。

---

## 6.1 Kernel 清单提取

### 方法 A: 从 Op 目录 include 推断

```python
# 在 Op 源码中搜索 kernel 相关 include
kernel_includes = re.findall(r'#include.*?(kernel|tiling).*?', content, re.IGNORECASE)

# 反向查找 Kernel 目录
# 在 src/kernels/ 中搜索包含 op_name 的文件
# find src/kernels/ -name "*.cpp" -o -name "*.h" | xargs grep -l "op_name"
```

### 方法 B: 从 Runner 调用推断

```python
# 在 *ops_runner.cpp 中搜索 Kernel Launch
kernel_launch = re.findall(r'(?:LaunchKernel|KernelLaunch|kernel_launch)\s*[<(]', content)
# 在 *aclnn_runner.cpp 中搜索 ACLNN API
aclnn_kernels = re.findall(r'aclnn(\w+)\(', content)
```

### Kernel 类型分类

| 调用模式 | Kernel 类型 | 示例 |
|---------|-----------|------|
| `aclnn{Xxx}(...)` | ACLNN Kernel (CANN 内置) | `aclnnLayerNorm` |
| `aclnn{Xxx}GetWorkspaceSize(...)` | ACLNN Workspace API | `aclnnLayerNormGetWorkspaceSize` |
| `AsdOps::OpParam::{name}` | 原生 Ops Kernel | `AsdOps::OpParam::Norm` |
| `LaunchKernel<XxxKernel>` | 自定义 Kernel | `LaunchKernel<LayerNormKernel>` |

### 输出格式

```markdown
### 6.1 Kernel 清单
| Kernel 名称 | 文件 | 用途 | 平台 |
|------------|------|------|------|
| aclnnLayerNorm | CANN 内置 | 标准 LayerNorm | 950 |
| LayerNormKernel | src/kernels/kernels/norm/layernorm/ | 原生 LayerNorm | 910B/910A |
```

---

## 6.2 Tiling 约束提取

### 搜索位置

- `*_operation.cpp` — ALIGNMENT 常量
- `*_tiling.h` / `*_tiling.cpp` — 独立 Tiling 文件
- `*_ops_runner.cpp` — Tiling 计算逻辑

### 关键模式

```python
# 对齐常量
alignment = re.findall(r'(?:ALIGNMENT|ALIGN|align)\s*=\s*(\d+)', content)

# 维度约束
dim_constraints = re.findall(r'(?:MAX|MIN)_(?:\w+)\s*=\s*(\d+)', content)

# UB 限制
ub_limit = re.findall(r'MAX_UB_SIZE\s*=\s*(\d+)', content)

# Tiling 结构体
tiling_struct = re.search(r'struct\s+(\w*Tiling\w*)\s*\{([^}]+)\}', content)
```

### 输出格式

```markdown
### 6.2 Tiling 约束
| 约束项 | 值 | 来源 |
|--------|---|------|
| 最后维对齐 | 16 元素 (32 bytes) | `ALIGNMENT = 32` in operation.cpp:48 |
| 动态量化最大长度 | 12288 | `DYNAMIC_QUANT_MAX_TENSOR_LENGTH = 12288` |
| UB 限制 | 192KB | `MAX_UB_SIZE = 192LL * 1024LL` |
```

---

## 6.3 Workspace 大小提取

### 搜索模式

```python
# 在 ACLNN runner 中
workspace_size = re.findall(r'(?:workspaceSize|WorkspaceSize|workspace_size)\s*[=+]', content)
workspace_buffer = re.findall(r'workspaceBufferSize\s*=', content)

# 计算公式模式
# workspaceBufferSize = swigluQuantWorkspaceSize_ + inplaceReciprocalWorkspaceSize_
# workspaceBufferSize = GetWorkspaceSize(x, y, ...)

# 在 Ops runner 中
# 通常为 Kernel 内部管理，标注 "Kernel 内部计算"
```

### 输出格式

```markdown
### 6.3 Workspace 大小
| 场景 | Workspace 来源 | 计算方式 |
|------|---------------|---------|
| ACLNN | aclnn{Xxx}GetWorkspaceSize() | CANN 动态计算 |
| Ops | Kernel 内部管理 | Tiling 决定 |
| 多 Kernel | swigluWorkspaceSize + reciprocalWorkspaceSize | 拼接 |
```

---

## 6.4 常量提取补充

```python
# 提取 static const 常量定义
constants = re.findall(r'static\s+const\s+(?:uint\w+_t|int\w+_t|float|double)\s+(\w+)\s*=\s*([^;]+);', content)

# 分类
# IN_TENSOR_* / OUT_TENSOR_*  → I/O 数量
# DIM_* / SIZE_*              → 维度约束
# ALIGNMENT / THRESHOLD       → 约束条件
```
