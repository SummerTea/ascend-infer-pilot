# Source File Map 生成规则（Step 2）

## 输入

- Op 名称 + 分类 (infer/train/common)
- Routing 文件 (`routing/{op_name}.md`)
- ATB 仓中 Op 目录的实际文件列表

## 文件角色识别规则

### 按文件名模式分类

| 模式 | 角色 | 判定规则 |
|------|------|---------|
| `{op}_operation.h` | Operation 定义 (header) | 文件名含 `operation` + `.h` |
| `{op}_operation.cpp` | Operation 定义 (impl) | 文件名含 `operation` + `.cpp` |
| `{op}_aclnn_runner.h` | ACLNN Runner (header) | 文件名含 `aclnn_runner` 或 `aclnn` + `.h` |
| `{op}_aclnn_runner.cpp` | ACLNN Runner (impl) | 文件名含 `aclnn_runner` 或 `aclnn` + `.cpp` |
| `{op}_ops_runner.h` | Ops Runner (header) | 文件名含 `ops_runner` + `.h` |
| `{op}_ops_runner.cpp` | Ops Runner (impl) | 文件名含 `ops_runner` + `.cpp` |
| `{op}_quant_aclnn_runner.*` | Quant ACLNN Runner | 文件名含 `quant_aclnn` |
| `add_{op}_aclnn_runner.*` | Add 融合 ACLNN Runner | 文件名含 `add_` + `aclnn` |
| `*_runner_utils.*` | 公共工具 | 文件名含 `runner_utils` |
| `*_910a.*` / `*_910b.*` / `*_BNSD.*` | 平台变体 | 文件名含平台后缀 |
| `param.*` | 参数映射 | 文件名 `param.h` / `param.cpp` |

### 按文件内容特征补充

对无法通过文件名判定的文件，搜索内容关键词：

| 内容特征 | 角色推断 |
|---------|---------|
| `class XxxOperation : public OperationBase` | Operation 定义 |
| `REG_RUNNER_TYPE` | Runner 注册（在对应 runner 文件中） |
| `aclnnStatus` / `aclnnXxx` | ACLNN 相关 |
| `AsdOps` / `OpParam` | 原生 Ops 相关 |
| `KernelLaunch` / `kernel_launch` | Kernel 调用 |
| `template <` + `class.*Kernel` | Kernel 模板定义 |
| `TilingData` / `tiling_data` | Tiling 计算 |

## 外部依赖识别

扫描 `#include` 语句，识别关键外部头文件：

| 头文件路径模式 | 类型 | 作用 |
|--------------|------|------|
| `include/atb/infer_op_params.h` | 推理参数 | Param 结构体定义 |
| `include/atb/train_op_params.h` | 训练参数 | Param 结构体定义 |
| `atb/operation/operation_base.h` | 基类 | OperationBase |
| `mki/utils/platform/platform_info.h` | 平台检测 | 平台类型判断 |
| `aclnn/opdev/*.h` | ACLNN API | ACLNN 接口 |
| `atbops/params/*.h` | ACLNN 参数 | ACLNN 参数结构 |
| `atb/utils/*.h` | 工具函数 | 公共工具 |

## 输出格式

```markdown
### 1.1 文件清单
| # | 文件 | 角色 | 关键内容 |
|---|------|------|---------|

### 1.2 外部依赖
| 头文件 | 提供的类型/函数 |
|--------|----------------|
```

## Kernel 路径推断

若 Op 目录在 `src/ops/ops_infer/{op}/`，Kernel 可能在：
1. `src/kernels/kernels/{category}/{opname}/` — 标准 Kernel
2. `src/kernels/mixkernels/{相关名称}/` — 融合 Kernel

推断策略:
1. 在 Op 源码中搜索 `#include.*kernel` 找出 kernel 头文件路径
2. 反向搜索 `src/kernels/` 找包含 `{op_name}` 的目录
3. 无结果则标注 "未找到独立 Kernel 目录"
