# Computation Pipeline 分析指南（Step 4）

> **6 种 C++ dtype 检测模式** — 自动识别 NPU 内部 dtype 流转

---

## 检测流程总览

```
                   ┌──────────────┐
                   │ Op 源码输入   │
                   └──────┬───────┘
                          │
          ┌───────────────┼───────────────┐
          ▼               ▼               ▼
    ┌──────────┐   ┌──────────┐   ┌──────────┐
    │模式#4优先│   │模式#1枚举│   │模式#3    │
    │dtype设置 │   │注释提取  │   │innerPrec│
    └────┬─────┘   └────┬─────┘   └────┬─────┘
         │              │              │
         └──────────────┼──────────────┘
                        ▼
              ┌─────────────────┐
              │ 有发现？         │
              └────┬────────┬───┘
                   │        │
              YES  │        │ NO
                   ▼        ▼
         ┌──────────┐  ┌──────────┐
         │组装多阶段│  │模式#5/#6 │
         │Pipeline  │  │辅助检测  │
         └────┬─────┘  └────┬─────┘
              │             │
              ▼             ▼
         ┌──────────┐  ┌──────────┐
         │生成流转图│  │single_   │
         │+精度表   │  │stage 声明│
         └──────────┘  └──────────┘
```

---

## 模式 #1: 枚举注释 `//!< i:fp16, bmm:fp32, o:fp16`

### 搜索位置
`include/atb/infer_op_params.h` 中的 `enum KernelType` / `enum CalcType`

### 真实样本

```cpp
// include/atb/infer_op_params.h:1723-1725
enum KernelType : int {
    KERNELTYPE_DEFAULT = 0,    //!< i:float16, bmm:float16, o:float16
    KERNELTYPE_HIGH_PRECISION, //!< i:float16, bmm:float, o:float16
    KERNELTYPE_EXP_M8V2,       //!< i:float16, bmm: float16, exp: m8v2, softmax: default
};
```

### 提取规则

```python
# 搜索枚举注释中的 dtype 信息
pattern = r'enum\s+(\w+).*?\{([^}]+)\}'
comment_pattern = r'//!<\s*(.+)'

# 解析注释字段: i=input_dtype, bmm=compute_dtype, o=output_dtype
fields = {'i': 'input', 'bmm': 'compute', 'o': 'output', 'exp': 'exp_impl', 'softmax': 'softmax'}
```

### 输出格式

```markdown
### 4.2 精度控制标志
| 标志 | 位置 | 取值 | 效果 |
|------|------|------|------|
| KernelType | infer_op_params.h:1723 | DEFAULT | i:fp16, bmm:fp16, o:fp16 |
| KernelType | infer_op_params.h:1724 | HIGH_PRECISION | i:fp16, bmm:fp32, o:fp16 |
```

---

## 模式 #2: 模板 PrecType 参数

### 搜索位置
`src/kernels/mixkernels/*/` 中的 `*_common.h`、`*_tiling.h`

### 真实样本

```cpp
// unpad_flash_attention_nz_tiling_dependency.h:35
OpParam::UnpadFlashAttentionNz::PrecType precType;

// unpad_flash_attention_nz_kernel.cpp:66
if (param.precType == OpParam::UnpadFlashAttentionNz::PrecType::BMM1_FP32_EXP_FP32) {
    // BMM1 在 fp32 计算
}
```

### 提取规则

```python
# 搜索 PrecType / prec_type 使用
prectype_def = r'enum\s+(?:class\s+)?(\w*Prec\w*).*?\{([^}]+)\}'
prectype_use = r'precType\s*==\s*\w+::(\w+)'

# 解析枚举值名中的 dtype 信息
# BMM1_FP32_EXP_FP32 → BMM1(fp32), EXP(fp32)
# BMM2_ONLINE_SOFTMAX_FP16 → BMM2(fp16), SOFTMAX(fp16)
```

### 输出格式

```markdown
### 4.2 精度控制标志 (Kernel 模板)
| 模板参数 | 位置 | 类型 | 说明 |
|---------|------|------|------|
| `precType` | `*_tiling_dependency.h:35` | `PrecType` enum | 控制 BMM/Softmax 精度 |
```

---

## 模式 #3: innerPrecise 标志

### 搜索位置
`src/ops/ops_infer/{op}/*_aclnn_runner.cpp` 和 `.h`

### 真实样本

```cpp
// paged_attention_aclnn_runner.cpp:129
int64_t innerPrecise = 1;  // 1 = fp32 accumulator

// self_attention_aclnn_runner.h:49
int64_t innerPrecise = 1;
```

### 提取规则

```python
# 搜索 innerPrecise 声明 + 使用
decl_pattern = r'int64_t\s+innerPrecise\s*=\s*(\d+)'
use_pattern = r'innerPrecise'

# innerPrecise = 0 → fp16 accumulator
# innerPrecise = 1 → fp32 accumulator
```

### 映射

| innerPrecise | 含义 |
|-------------|------|
| 0 | fp16 accumulator (低精度, 高性能) |
| 1 | fp32 accumulator (高精度, 较低性能) |

---

## 模式 #4: InferShape dtype 显式设置

### 搜索位置
`src/ops/ops_infer/{op}/*_operation.cpp` 中的 `InferShapeImpl`

### 真实样本

```cpp
// layer_norm_operation.cpp:236 — 量化输出设为 INT8
outTensorDescs.at(0).dtype = ACL_INT8;

// layer_norm_operation.cpp:242 — 动态量化输出 mean 设为 FLOAT
outTensorDescs.at(1).dtype = ACL_FLOAT;

// elewise_operation.cpp:220 — Dynamic Quant 输出 INT8
outTensorDescs.at(0).dtype = ACL_INT8;

// gather_pre_rms_norm_operation.cpp:74 — 输出设为 FLOAT (≠ input)
outTensorDescs.at(0).dtype = ACL_FLOAT;

// 普通 pass-through
outTensorDescs.at(0).dtype = inTensorDescs.at(0).dtype;
```

### 提取规则

```python
# 搜索 dtype 设置语句
dtype_assign = r'outTensorDescs\.at\((\d+)\)\.dtype\s*=\s*([^;]+);'

# 判断是否为 dtype 断点:
# - 右侧是 ACL_INT8, ACL_FLOAT, ACL_FLOAT16 等常量 → 可能断点
# - 右侧是 inTensorDescs.at(N).dtype → pass-through
# - 右侧是 param_.xxx → 由参数控制的 dtype

# 判断是否为断点的标准:
# outDtype ≠ inDtype → DTYPE_BREAK
```

### 输出格式

```markdown
| 条件 | Input Dtype | Output Dtype | 触发文件 |
|------|------------|-------------|---------|
| NORM + QUANT_INT8 | fp16/bf16 | int8 | layer_norm_operation.cpp:236 |
```

---

## 模式 #5: aclCreateTensor dtype ≠ input dtype

### 搜索位置
`src/ops/ops_infer/{op}/*_aclnn_runner.cpp` 中的 `BuildAclnnVariantPack`

### 真实样本

```cpp
// swiglu_quant_aclnn_runner.cpp:129
// smoothScales 用 ACL_FLOAT 创建，而输入是 fp16/bf16
smoothScalesAclnnTensor_->tensor =
    aclCreateTensor(smoothScalesShape.data(), ..., ACL_FLOAT, ...);
```

### 提取规则

```python
# 1. 先确定输入 dtype（从 BuildAclnnVariantPack 的 inTensor 创建）
in_dtype = re.findall(r'aclCreateTensor\([^)]*,\s*(ACL_\w+)\s*,', content)

# 2. 搜索所有 aclCreateTensor 调用
all_dtypes = re.findall(r'aclCreateTensor\([^)]*,\s*(ACL_\w+)\s*,', content)

# 3. 找出辅助 tensor（非输入输出，如 smoothScales/scale/offset）
# 关键特征: 变量名含 smooth/scale/offset/antiquant
aux_pattern = r'(smooth\w*|scale\w*|offset\w*|antiq\w*).*aclCreateTensor.*?(ACL_\w+)'

# 4. 如果辅助 tensor 的 dtype ≠ 输入 dtype → 断点
```

---

## 模式 #6: ini 文件 dtype 断点

### 搜索位置
`ops_configs/atb_ops_info.ini`

### 检测策略

```python
# 在 ini 中搜索算子的 input/output dtype 配置段
# 比较 input.dtype 和 output.dtype 字段
# 如果不同 → DTYPE_BREAK
```

> 注: 实际 ATB 仓中 ini 文件主要用于运行配置，dtype 约束主要在代码中。此模式作为补充。

---

## Pipeline 组装逻辑

### 判断流水线类型

```python
def classify_pipeline(patterns_found):
    """根据检测到的模式判断 Pipeline 类型"""
    
    has_dtype_break = patterns_found.get('p4') or patterns_found.get('p5') or patterns_found.get('p6')
    has_precision_control = patterns_found.get('p1') or patterns_found.get('p2') or patterns_found.get('p3')
    has_multi_stage = patterns_found.get('p1')  # 枚举注释通常意味着多阶段
    
    if has_multi_stage:
        return 'multi_stage'        # §4.1 完整流转图
    elif has_dtype_break:
        return 'single_with_break'  # §4.4 单阶段 + dtype 断点表
    elif has_precision_control:
        return 'single_with_prec'   # §4.2 精度控制标志
    else:
        return 'single_stage'       # §4.4 简化声明
```

### 生成 Pipeline 流转图

```python
# 当 classify = 'multi_stage' 时
# 从模式 #1 注释解析 Stage 序列:
#
# stage_map = {
#     'bmm':    'Q×K^T (BMM1)',
#     'softmax': 'Softmax (row-wise)',
#     'bmm2':   'Attn×V (BMM2)',
#     'exp':    'Exponential',
#     'scale':  'Scale (×1/√d)',
# }
#
# 输出:
# Stage 1: Q×K^T (BMM1)  → fp16 in → {prec} acc → fp16 out
# Stage 2: Scale          → fp16 pass-through
# Stage 3: Softmax        → fp16 in → fp32 exp → fp16 out
# Stage 4: Attn×V (BMM2)  → fp16 in → {prec} acc → fp16 out
```

### 识别 Stage 顺序的启发式规则

| 注释关键词 | Stage 名称 | 典型位置 |
|-----------|-----------|---------|
| `bmm` (第一个) | BMM1 (Q×K^T) | Stage 1 |
| `exp` / `softmax` | Softmax | Stage 2-3 |
| `bmm` (第二个/`o:`) | BMM2 (Attn×V) | Stage 4 |
| `scale` | Scale | Stage 1-2 之间 |

---

## 质量检查清单

- [ ] 每个检测到的模式标注了来源文件和行号
- [ ] Pipeline 类型判断正确（multi_stage / single_with_break / single_stage）
- [ ] dtype 断点表覆盖了所有量化/转换场景
- [ ] 精度控制标志表完整（如有 Precision/KernelType/innerPrecise）
- [ ] Pipeline 流转图每个 Stage 标注了 dtype 检测来源
- [ ] 单阶段算子有明确的 `pipeline_type` 声明
