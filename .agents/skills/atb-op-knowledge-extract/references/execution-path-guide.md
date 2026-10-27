# Execution Paths 提取规则（Step 5）

## 目标

从 `CreateRunner()` 提取 Runner 选择决策树 + 平台支持矩阵 + API 调用链。

---

## 5.1 CreateRunner 分析

### 关键模式

```cpp
// 典型 CreateRunner 模式
std::shared_ptr<Runner> XxxOperation::CreateRunner(Context &context) const
{
    // 模式 A: 平台条件判断
    if (PlatformType == ASCEND_950 && ...) {
        return std::make_shared<XxxAclnnRunner>(param_);
    }
    // 模式 B: 参数条件判断
    if (param_.calcType == ENCODER) {
        if (Platform == 910A) return ...;
        return ...;
    }
    // 模式 C: Fallback
    return std::make_shared<XxxOpsRunner>(param_);
}
```

### 提取步骤

```python
# 1. 定位 CreateRunner 函数
create_runner = re.search(r'(?:std::shared_ptr<Runner>|Status)\s+(\w+)::CreateRunner.*?^\}', 
                          content, re.DOTALL | re.MULTILINE)

# 2. 提取条件分支
# 搜索 if/else if/else 结构
branches = re.findall(r'(?:if|else if)\s*\(([^)]+)\).*?(?:return|$)')
```

### 决策树节点类型

| 条件模式 | 含义 | 示例 |
|---------|------|------|
| `PlatformType == ASCEND_950` | 950 平台 | ACLNN 路径 |
| `GetSingleton<Config>().Is910B()` | 910B 平台 | Ops 路径 |
| `param_.layerType == LAYER_NORM_NORM` | 参数模式选择 | Norm/PreNorm/PostNorm |
| `param_.calcType == ENCODER` | 计算类型 | Encoder/Decoder/PA |
| `param_.kvCacheCfg == K_BYPASS_V_BYPASS` | Cache 配置 | Bypass/Cache |
| `&&` 组合 | 多维条件 | 950+NORM+UNQUANT |

### 输出格式

```markdown
### 5.1 Runner 选择决策树
```
XxxOperation::CreateRunner()
  ├── [条件] Platform == 950 AND layerType == NORM
  │     └── → XxxAclnnRunner
  └── [fallback]
        └── → XxxOpsRunner
```
```

---

## 5.2 平台支持矩阵

### 平台检测模式

```python
# 在 CreateOperation + CreateRunner 中搜索平台关键字
platforms = set()
for pattern in ['910A', '910B', '310B', '950', 'BNSD', '800I A2', 'Atlas']:
    if pattern in content:
        platforms.add(pattern)

# 判断每个平台的 Runner + 限制
# 搜索 if (platform) { 拒绝/限制 }
restrictions = re.findall(r'ATB_LOG\(ERROR\).*?(only supports|does not support).*?', content)
```

### 输出格式

```markdown
### 5.2 平台支持矩阵
| 平台 | Runner | 特性支持 | 限制 |
|------|--------|---------|------|
| Atlas 910B | OpsRunner | 全特性 | - |
| Atlas 950 | ACLNN Runner | NORM+UNQUANT | 不支持量化 |
```

---

## 5.3 ACLNN 调用链

### 提取 API 调用

```python
# 在 aclnn_runner.cpp 中搜索 ACLNN API 调用
aclnn_apis = re.findall(r'aclnn(\w+)\(', content)  # e.g. aclnnLayerNorm
workspace_apis = re.findall(r'aclnn(\w+)GetWorkspaceSize\(', content)

# 构建调用链
# BuildAclnnVariantPack → SetAclNNWorkspaceExecutor → LaunchAclnnKernel
```

### 输出格式

```markdown
### 5.3 关键 API 调用链
```
atb::CreateOperation(param, &op)
  └─ Setup → InferShape → GetWorkspaceSize
       └─ Execute
            ├─ [ACLNN] aclnn{Xxx}GetWorkspaceSize() → aclnn{Xxx}()
            └─ [OPS]   AsdOps::OpParam::{name} → Tiling → Kernel
```
```

---

## 5.4 Runner 类型识别

```python
# 从 #include + new/make_shared 推断所有 Runner 类
runners = set()
for include in re.findall(r'#include\s+"(\w+_runner\.h)"', content):
    runners.add(include.replace('_runner.h', ''))
for make in re.findall(r'make_shared<(\w+)>', content):
    runners.add(make)

# 分类
for r in runners:
    if 'Aclnn' in r or 'aclnn' in r:
        type = 'ACLNN'
    elif 'Ops' in r or 'ops' in r:
        type = 'Ops'
    elif 'Graph' in r or 'graph' in r:
        type = 'Graph'
    elif 'Lcoc' in r or 'lcoc' in r:
        type = 'LCOC'
    else:
        type = 'Custom'
```
