# Parameter Constraints 提取规则（Step 3）

## 输入

- `include/atb/infer_op_params.h` 或 `train_op_params.h`
- `{op}_operation.cpp`（InferShape, GetInputNum, GetOutputNum）
- `atb_ops_info.ini`（可选）

## 提取步骤

### 3.1 定位 Param 结构体

```cpp
// 在 param header 中搜索
struct XxxParam {
    // 枚举定义
    // 成员变量
    // 嵌套 struct
};
```

**提取内容**:
- 枚举类型名 + 枚举值列表 + 注释
- 成员变量名、类型、默认值
- 嵌套 struct 名 + 成员

### 3.2 提取参数约束（从 CreateOperation / *ParamCheck）

在 `{op}_operation.cpp` 中搜索:
- `*ParamCheck` 函数 — 参数合法性校验
- `CreateOperation` 函数 — 平台特定约束
- 搜索模式:
  - `ATB_LOG(ERROR) << "..."` — 错误信息即约束条件
  - `if (...) return ERROR_*` — 条件即边界

### 3.3 提取 Shape 约束（从 InferShape / InferShapeCheck）

在 InferShape 相关函数中提取:
- `dimNum` 约束 (最小/最大维度数)
- `dims[N]` 约束 (特定维度值限制)
- 对齐约束 (如 `lastDim % ALIGNMENT == 0`)
- 动态量化最大长度等常量

### 3.4 提取 Dtype 约束（从 InferShape）

关键模式:
```cpp
// dtype 设置
outTensorDescs.at(N).dtype = ACL_INT8;    // 输出 dtype ≠ 输入
outTensorDescs.at(0) = inTensorDescs.at(0); // 输出 dtype == 输入
```

### 3.5 提取 I/O 数量规则（从 GetInputNum/GetOutputNum）

分析 switch/if-else 逻辑，建立 (layerType, quantType, dynamicQuantType) → (inCount, outCount) 映射。

## 输出格式

```markdown
### 3.1 参数结构体
**位置**: `{header}` (L{start}-{end})
```cpp
struct XxxParam { ... }  // 关键枚举+成员
```

### 3.2 参数约束表
| 参数名 | 类型 | 默认值 | 合法范围 | 约束条件 | 来源 |

### 3.3 Shape 约束
| 约束项 | 条件 | 错误信息 |

### 3.4 Dtype 约束
| Tensor | 支持 Dtype | 条件 |
```

## 检测模式速查

| 检测目标 | 搜索位置 | 正则/模式 |
|---------|---------|----------|
| struct 定义 | param header | `struct \w+Param\s*\{` |
| enum 定义 | param header | `enum \w+\s*:\s*\w+\s*\{` |
| 参数校验 | operation.cpp | `\w+Check\s*\(` |
| 平台约束 | operation.cpp | `Is910B\|Is910A\|PlatformType` |
| dimNum 约束 | operation.cpp | `\.dimNum\s*[<>=!]+\s*\d+` |
| 对齐约束 | operation.cpp | `%\s*\d+\s*==\s*0\|ALIGNMENT` |
| dtype 设置 | operation.cpp | `\.dtype\s*=` |
| 错误信息 | operation.cpp | `ATB_LOG\(ERROR\).*` |
| 输入数 | operation.cpp | `GetInputNum\(\)` |
| 输出数 | operation.cpp | `GetOutputNum\(\)` |
