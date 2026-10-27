# Known Issues & 边界条件提取规则（Step 7）

## 目标

从源码错误处理+日志中提取已知问题、边界条件、常见错误排查信息。

---

## 7.1 已知问题提取

### 从 ERROR 日志提取

```python
# 搜索所有 ATB_LOG(ERROR) 语句
errors = re.findall(r'ATB_LOG\(ERROR\)\s*<<\s*(.+?)(?:;|"(?:\s*<<|;))', content, re.DOTALL)

# 每条 ERROR 日志的结构:
# "描述性错误信息" << variable
# 提取: 条件 + 错误描述 + 错误码
```

### 错误码与条件映射

| 错误码 | 含义 | 提取位置 |
|--------|------|---------|
| `ERROR_INVALID_PARAM` | 参数值非法 | `*Check()` 函数 |
| `ERROR_INVALID_TENSOR_DIM` | Tensor 维度不匹配 | `InferShapeCheckImpl` |
| `ERROR_INVALID_TENSOR_SIZE` | Tensor 大小/对齐非法 | `*DimCheck()` |
| `ERROR_OUT_OF_HOST_MEMORY` | Host 内存不足 | `new` 操作 |
| `ERROR_CANN_ERROR` | CANN/ACLNN 调用失败 | `LaunchAclnnKernel` |
| `ERROR_INTERNAL_ERROR` | 内部错误 | 异常路径 |

### 平台限制提取

```python
# "only supports" / "does not support" 模式
platform_limits = re.findall(
    r'ATB_LOG\(ERROR\).*?(only supports?|does not support|not support).*?',
    content
)
# 示例: "SwigluQuant only supports 910B/950 devices"
```

### 输出格式

```markdown
### 7.1 已知问题
| # | 问题描述 | 影响范围 | 平台 | 规避方式 | 状态 |
|---|---------|---------|------|---------|------|
| 1 | 950 仅支持 NORM+UNQUANT | PRENORM/POSTNORM | 950 | 使用 910B | open |
```

---

## 7.2 边界条件提取

### 从参数校验函数提取

```python
# 搜索 if (...) { return ERROR_*; } 模式
bounds = re.findall(
    r'(?:if|else if)\s*\(([^)]+)\)\s*\{[^}]*?(?:ERROR_|ATB_LOG\(ERROR\))',
    content
)

# 解析条件表达式:
# - param.xxx < VALUE        → 下限
# - param.xxx > VALUE        → 上限
# - param.xxx != VALUE       → 必须等于
# - PlatformType == xxx      → 平台限制
# - std::fabs(xxx) < THRESHOLD → 数值精度限制
```

### 常见边界模式

| 条件模式 | 边界类型 | 提取为 |
|---------|---------|--------|
| `epsilon < THRESHOLD` | 数值下限 | epsilon ≥ 2e-38 |
| `headNum <= 0` | 正值要求 | headNum > 0 |
| `lastDim % ALIGN != 0` | 对齐要求 | lastDim 按 ALIGN 对齐 |
| `dimNum < MIN_DIM` | 维度下限 | dimNum ≥ MIN_DIM |
| `quantType != X && quantType != Y` | 枚举限定 | quantType ∈ {X, Y} |
| `PlatformType == X` → 特殊逻辑 | 平台边界 | X 平台特定行为 |
| `param_.xxx == UNDEFINED` | 必选参数 | xxx 必须显式设置 |

### 输出格式

```markdown
### 7.2 边界条件
| 条件 | 行为 | 错误码 |
|------|------|--------|
| layerType == UNDEFINED | 拒绝 | ERROR_INVALID_PARAM |
| last dim 未对齐 | 拒绝 | ERROR_INVALID_TENSOR_SIZE |
```

---

## 7.3 常见错误排查

### 编译时错误→运行时映射

```python
# 从错误日志文本提取排查建议
# 日志文本就是排查信息
# "layerType is not supported, only support NORM/PRENORM/POSTNORM"
# → 根因: layerType 设错
# → 解决方案: 设为 NORM/PRENORM/POSTNORM 之一
```

### 自动生成排查条目

```python
def extract_troubleshooting(error_log_text):
    """从错误日志文本自动生成排查条目"""
    # "xxx is not supported, only support A/B/C"
    # → 根因: xxx 参数值非法
    # → 解决: 设为 A/B/C 之一
    
    # "yyy only supports Z devices"
    # → 根因: 平台不匹配  
    # → 解决: 使用 Z 平台
    
    # "zzz failed with return value: N"
    # → 根因: CANN/ACLNN 调用失败
    # → 解决: 检查 CANN 版本/环境
```

### 输出格式

```markdown
### 7.3 常见错误排查
| 错误信息 | 根因 | 解决方案 |
|---------|------|---------|
| "layerType is not supported" | layerType 设错 | 设为合法枚举值 |
| "last dim should align 32" | 最后维未对齐 | 对齐到 16 元素 |
| "only supports 910B/950" | 平台不匹配 | 切换到支持的平台 |
```

---

## 7.4 已知限制注释提取

```python
# 搜索注释中的限制标记
# FIXME / TODO / HACK / WORKAROUND / LIMITATION / BUG
comment_issues = re.findall(
    r'//\s*(FIXME|TODO|HACK|WORKAROUND|LIMITATION|BUG|KNOWN.?ISSUE)[\s:]*(.+)',
    content, re.IGNORECASE
)
```

---

## 质量评估

提取完成后评估：
- [ ] 每条 ERROR 日志都有对应的错误排查条目
- [ ] 平台限制全部记录
- [ ] 数值边界（epsilon/对齐/最大长度）全部提取
- [ ] 状态标记: 有规避方案→`wa`, 无规避方案→`open`, 已修复→`fixed`
