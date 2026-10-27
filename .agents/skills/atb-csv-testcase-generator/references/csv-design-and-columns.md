# CSV 正例、反例与格式详解

本文为 `atb-csv-testcase-generator` 延伸阅读：展开区的设计原则、模板与多设备规则。

<details>
<summary>正例设计原则（点击展开）</summary>

### 数据类型覆盖
- float16 (最常用)
- bf16 (高精度场景)

### Shape 典型性
包含主流模型的常见 shape：
- **Llama**: 512, 7168 (hidden_size=3584)
- **GPT**: 256, 12288 (hidden_size=6144)
- **Mini batch**: 1-16 tokens
- **Large batch**: 1024-2048 tokens

### 边界条件
- UB 上限边界（如 hidden_size=31424）
- 非对齐 hidden_size（如 130, 65）
- 最小 shape（如 1, 64）

### ExpectedError 选择指南

| 测试目标 | ExpectedError | 需要 Golden | 典型场景 |
|---------|--------------|------------|---------|
| 仅验证参数校验 | `C:ERROR_INVALID_PARAM` | 否 | 反例 |
| 仅验证维度推断 | `I:NO_ERROR` | 否 | 简单正例 |
| 完整执行+精度验证 | `NO_ERROR` | **是** | 完整正例 |

**正例使用 `NO_ERROR` 时，需要在 `data_generation.py` 中实现 `golden()` 参考计算。** 详见 [ATB Golden Developer](../../atb-golden-developer/SKILL.md)（本文件在 `references/` 下，跨 skill 需两级 `..` 回到 `skills/`）。

### 正例模板
```csv
CaseNum|CaseName|OpName|OpParam|InNum|InDType|InFormat|InShape|OutNum|OutDType|OutFormat|OutShape|DataGenType|DataGenRange|InTensorFile|OutTensorFile|TestType|TestLevel|FromModel|SocVersion|ExpectedError
# 完整正例 (需 golden)
1      |XxxBase |XxxOperation|{"param":0}|1|float16|nd|128,4096|2|int8;float|nd;nd|128,2048;128|customize|-100,100;|||||||Ascend910B;Ascend950|NO_ERROR
# 仅验证 InferShape (不需 golden)
2      |XxxShape |XxxOperation|{"param":0}|1|float16|nd|1,8,512|1|float16|nd|1,8,512|random|-100,100;|||||||Ascend910B|I:NO_ERROR
```
</details>

<details>
<summary>反例设计原则（点击展开）</summary>

### 数据类型错误
```csv
# 只支持 float16/bf16，不支持 int64
SwigluQuantErrorDtypeInt64|SwigluQuantOperation|{"quantType":0}|1|int64|nd|128,4096|...|I:ERROR_INVALID_TENSOR_INI_MATCH
```

### 维度错误
```csv
# dimNum 必须为 2
SwigluQuantErrorDimNum|SwigluQuantOperation|{"quantType":0}|1|float16|nd|128,4096,1|...|I:ERROR_INVALID_TENSOR_DIM_NUM
```

### 维度值错误
```csv
# hidden_size 必须能被 2 整除
SwigluQuantErrorHiddenSizeOdd|SwigluQuantOperation|{"quantType":0}|1|float16|nd|128,4097|...|I:ERROR_INVALID_TENSOR_DIM
```

### 参数错误
```csv
# quantType 只能为 0
SwigluQuantErrorParam|SwigluQuantOperation|{"quantType":1}|1|float16|nd|128,4096|...|C:ERROR_INVALID_PARAM
```

### Shape 边界超限
```csv
# UB 上限检查
SwigluQuantErrorHiddenSizeTooLarge|SwigluQuantOperation|{"quantType":0}|1|float16|nd|5,15714|...|I:ERROR_INVALID_TENSOR_DIM
```

### 反例覆盖检查表

| 校验类型 | ExpectedError | 覆盖场景 |
|----------|--------------|----------|
| 数据类型 | `I:ERROR_INVALID_TENSOR_INI_MATCH` | int64, int32, float32, bool |
| 数据格式 | `I:ERROR_INVALID_TENSOR_INI_MATCH` | fractal_z, ncdhw 等 |
| 维度数量 | `I:ERROR_INVALID_TENSOR_DIM_NUM` | 1D, 3D, 4D |
| 维度值 | `I:ERROR_INVALID_TENSOR_DIM` | 0, 奇数, 超限 |
| 参数校验 | `C:ERROR_INVALID_PARAM` | 非法参数值 |
| 输出 Shape | `S:ERROR_INVALID_TENSOR_DIM` | shape 不匹配 |
| UB 边界 | `I:ERROR_INVALID_TENSOR_DIM` | hidden_size 过大 |
</details>

<details>
<summary>性能测试设计原则（点击展开）</summary>

### 大小 Shape 覆盖
```csv
# 大 shape
SwigluQuantPerformanceLarge|SwigluQuantOperation|{"quantType":0}|1|float16|nd|2048,16384|...|Performance|Ascend910B;Ascend950|NO_ERROR

# 中 shape
SwigluQuantPerformanceMedium|SwigluQuantOperation|{"quantType":0}|1|float16|nd|512,8192|...|Performance|Ascend910B;Ascend950|NO_ERROR

# 小 shape
SwigluQuantPerformanceSmall|SwigluQuantOperation|{"quantType":0}|1|float16|nd|64,256|...|Performance|Ascend910B;Ascend950|NO_ERROR
```

### 不同数据类型
```csv
# bf16 性能
SwigluQuantPerformanceBf16|SwigluQuantOperation|{"quantType":0}|1|bf16|nd|1024,8192|...|Performance|Ascend910B;Ascend950|NO_ERROR
```

### 边界值测试
```csv
# hidden_size 边界
SwigluQuantPerformanceHidden4096|SwigluQuantOperation|{"quantType":0}|1|float16|nd|256,8192|...|Performance|Ascend910B;Ascend950|NO_ERROR
```
</details>

<details>
<summary>CSV 格式规范（点击展开）</summary>

### 列说明
| 列号 | 名称 | 说明 |
|------|------|------|
| 1 | CaseNum | 用例编号 |
| 2 | CaseName | 用例名称 |
| 3 | OpName | 算子名称（如 `SwigluQuantOperation`） |
| 4 | OpParam | JSON 格式参数字符串 |
| 5 | InNum | 输入张量数量 |
| 6 | InDType | 输入数据类型（分号分隔） |
| 7 | InFormat | 输入数据格式（分号分隔） |
| 8 | InShape | 输入形状（分号分隔） |
| 9 | OutNum | 输出张量数量 |
| 10 | OutDType | 输出数据类型 |
| 11 | OutFormat | 输出数据格式 |
| 12 | OutShape | 输出形状 |
| 13 | DataGenType | 数据生成类型（通常为 `customize`） |
| 14 | DataGenRange | 数据生成范围 |
| 15 | InTensorFile | 输入张量文件（空） |
| 16 | OutTensorFile | 输出张量文件（空） |
| 17 | TestType | 测试类型（空或 `Performance`） |
| 18 | TestLevel | 测试级别（空） |
| 19 | FromModel | 来源模型（空） |
| 20 | SocVersion | 目标 SoC（如 `Ascend910B`、`Ascend950`。多个设备用 `;` 分隔：`Ascend910B;Ascend950`） |
| 21 | ExpectedError | 期望错误（`NO_ERROR` 或错误类型） |

### 数据类型映射

在 CSV 中使用 data_generation.py 支持的数据类型名称：

| 实际类型 | CSV 中使用 |
|----------|-----------|
| float32 | `float` |
| float16 | `float16` 或 `half` |
| bfloat16 | `bf16` 或 `bfloat16` |
| int8 | `int8` 或 `char` |
| int32 | `int32` 或 `int` |
| int64 | `int64` 或 `long` |

### 常用 ExpectedError 类型

| 错误类型 | 说明 | 触发场景 |
|----------|------|----------|
| `NO_ERROR` | 无错误，正例预期（完整流程：Create→Execute→Golden Compare） | 正常执行，需要 golden 参考实现 |
| `I:NO_ERROR` | InferShape 无错误（仅验证到 InferShape 阶段） | 不需要 golden，仅验证维度推断 |
| `C:NO_ERROR` | Create 无错误（仅验证到 Create 阶段） | 仅验证参数校验通过 |
| `I:ERROR_INVALID_TENSOR_INI_MATCH` | 张量初始化不匹配 | dtype/format 错误 |
| `I:ERROR_INVALID_TENSOR_DIM_NUM` | 维度数量错误 | dimNum 不符合预期 |
| `I:ERROR_INVALID_TENSOR_DIM` | 维度值错误 | 维度值超限/无效 |
| `C:ERROR_INVALID_PARAM` | 参数错误 | 非法参数值 |
| `S:ERROR_INVALID_TENSOR_DIM` | 输出 Shape 错误 | 输出 tensor shape 不匹配 |
</details>

### 多设备测试设计原则

**设计 CSV 测试用例时，必须同时覆盖 Ascend910B 和 Ascend950 设备。**

#### 合并 vs 分离规则

| 情况 | SocVersion | 说明 |
|------|-----------|------|
| 910B 和 950 **完全一致**（场景/约束/dtype/format 均相同） | `Ascend910B;Ascend950` | 合并为一条用例 |
| 910B 和 950 **存在任何差异** | 分两条，各写各自 SocVersion | **必须分离** |

#### 必须分离的场景（不限于以下）

| 差异类型 | 示例 | 处理方式 |
|---------|------|---------|
| **dtype 支持不同** | 910B 支持 bf16，950 不支持 | 分两条：910B bf16 / 950 用其他 dtype |
| **format 支持不同** | 910B 支持 ND，950 仅支持 ND_TRANSPOSE | 分两条，各自指定合法 format |
| **参数约束不同** | 910B quantType=0,1；950 quantType=0 | 分两条，各自合法/非法参数 |
| **维度限制不同** | 910B hidden_size≤31424；950 hidden_size≤32768 | 正向/边界分别设计 |
| **ExpectedError 不同** | 同一非法输入，910B 报 ERROR_A，950 报 ERROR_B | 分两条，各自 ExpectedError |
| **性能基准不同** | 910B 和 950 性能预期不同 | 分两条，各自 Performance |

#### 设计流程

1. **先分析接口文档**：对比 910B 和 950 的 ACLNN 接口规格，标记所有差异点
2. **先写共同用例**：无差异的场景用 `Ascend910B;Ascend950`
3. **再写差异用例**：每个差异点，为 910B 和 950 各写一条独立用例
4. **差异用例命名**：`{OpName}{场景}910B` / `{OpName}{场景}950` 便于区分

> **注意**：实际运行测试时仅执行 Ascend910B 用例（当前测试环境限制）。Ascend950 用例由用户在 950 设备上手动验证。

---
