# {{OP_NAME}} — ATB Agent 知识条目

> **模板版本**: v1.0 | **状态**: {{STATUS}} | **最后更新**: {{LAST_UPDATED}}
>
> 本文件由 `atb-op-knowledge-extract` Skill 自动生成（或增量更新），供 Agent 快速理解算子完整知识，避免反复阅读源码。

---

## YAML Frontmatter（元数据）

```yaml
# ============================================================
# 知识条目元数据 — 供 Agent 路由和自动化工具解析
# ============================================================
op:
  name: "{{OP_NAME}}"                    # ATB 算子名（与 atb_ops_info.ini 一致）
  category: "{{CATEGORY}}"              # norm / attention / activation / communication / other
  tier: "{{TIER}}"                      # S / M / L / XL（见 inventory.csv）
  type: "{{OP_TYPE}}"                   # single（单算子） / fusion（融合算子） / composite（复合算子）

source:
  repo_path: "src/ops/ops_{{INFER_OR_TRAIN}}/{{OP_NAME}}/"
  kernel_path: "src/kernels/kernels/{{KERNEL_SUBPATH}}/"  # 若存在
  param_header: "include/atb/infer_op_params.h"            # 或 train_op_params.h
  ini_file: "atb_ops_info.ini"                             # 算子注册信息

knowledge:
  status: "{{STATUS}}"                  # complete / partial / stale
  last_extracted: "{{DATE}}"
  last_source_commit: "{{GIT_SHA}}"
  extractor_version: "1.0.0"

test:
  atk_test_path: "atk_test/atk_cida_atb/atb/{{INFER_OR_TRAIN}}/{{OP_NAME}}Operation/"
  has_atk_tests: {{HAS_ATK_TESTS}}      # true / false
```

---

## 1. Source File Map（源文件地图）

> **目的**: Agent 一眼看到所有相关文件及其角色，无需 `find` + `grep`。

### 1.1 文件清单

| # | 文件（相对路径） | 角色 | 关键内容 |
|---|-----------------|------|---------|
| 1 | `{{FILE_1}}` | Operation 定义 | 参数校验、InferShape、CreateRunner |
| 2 | `{{FILE_2}}` | OpsRunner | 原生 Ops 执行路径 |
| 3 | `{{FILE_3}}` | ACLNN Runner | ACLNN 执行路径 |
| 4 | `{{FILE_4}}` | Kernel 入口 | Kernel 启动、Tiling 计算 |
| ... | ... | ... | ... |

> **文件角色枚举**: Operation定义 | OpsRunner | ACLNNRunner | Kernel入口 | Tiling计算 | 公共工具 | 参数结构体 | 测试配置

### 1.2 外部依赖（关键头文件）

| 头文件 | 提供的类型/函数 |
|--------|----------------|
| `include/atb/infer_op_params.h` | `{{OP_NAME}}Param` 结构体 |
| `{{KERNEL_COMMON_HEADER}}` | Kernel 模板参数、Tiling 结构体 |
| ... | ... |

---

## 2. Reading Order（推荐阅读顺序）

> **目的**: 最小化 Agent 阅读量 — 按层级递进，每个阶段读完即可回答对应问题。

```
阶段 1: 参数层（回答"这个 Op 接受什么参数？"）
  ├── [1] {{PARAM_HEADER}}                    → 读 {{OP_NAME}}Param 结构体
  └── [2] atb_ops_info.ini                     → 查 {{OP_NAME}} 注册段

阶段 2: 调度层（回答"如何选择 Runner？支持哪些平台？"）
  ├── [3] {{OP_NAME}}_operation.cpp            → 读 CreateRunner() / CreateOperation()
  └── [4] {{OP_NAME}}_operation.h              → 读类声明

阶段 3: 执行层（回答"数据如何在 NPU 上计算？"）
  ├── [5] {{OP_NAME}}_aclnn_runner.cpp         → 读 ACLNN 路径（主要路径）
  ├── [6] {{OP_NAME}}_ops_runner.cpp           → 读 Ops 路径（fallback/legacy）
  └── [7] {{KERNEL_FILE}}                      → 读 Kernel 计算逻辑

阶段 4: 约束层（回答"有什么边界条件？"）
  ├── [8] {{OP_NAME}}_operation.cpp            → 读 InferShape + 维度校验函数
  └── [9] 测试用例 YAML                         → 读参数范围限制
```

---

## 3. Parameter Constraints（参数约束）

> **目的**: Agent 生成 Golden / ATK 用例时，直接查此表获取合法参数范围。

### 3.1 参数结构体

**位置**: `{{PARAM_HEADER_PATH}}`（第 {{LINE_START}}-{{LINE_END}} 行）

```cpp
// 从源码提取的关键参数结构体（简化版）
struct {{OP_NAME}}Param {
    // ===== 数据类型 =====
    // dtype 约束:

    // ===== 形状约束 =====
    // shape 约束:

    // ===== 算法参数 =====
    // 超参约束:
};
```

### 3.2 参数约束表

| 参数名 | 类型 | 默认值 | 合法范围 | 约束条件 | 来源 |
|--------|------|--------|---------|---------|------|
| `{{PARAM_1}}` | `{{TYPE}}` | `{{DEFAULT}}` | `{{RANGE}}` | `{{CONSTRAINT}}` | param struct |
| ... | ... | ... | ... | ... | ... |

### 3.3 Shape 约束

| 约束项 | 条件 | 错误信息 |
|--------|------|---------|
| 输入维度数 | `{{MIN_DIM}}` ≤ dimNum ≤ `{{MAX_DIM}}` | "dimNum must be between..." |
| 最后维对齐 | lastDim % `{{ALIGN}}` == 0 | "last dim must align to..." |
| ... | ... | ... |

### 3.4 Dtype 约束

| Tensor | 支持 Dtype | 条件 |
|--------|-----------|------|
| input | `{{DTYPES}}` | {{CONDITION}} |
| output | `{{DTYPES}}` | {{CONDITION}} |
| ... | ... | ... |

---

## 4. Computation Pipeline（计算管线）

> **目的**: 多阶段算子的 Golden 生成需精确匹配 NPU 内部 dtype 流转。
> 本章是知识条目最关键的创新——Agent 无需阅读 Kernel 源码即可知道中间 dtype。

### 4.1 阶段流转图

```
输入 ({{INPUT_DTYPE}})
  │
  ├── Stage 1: {{STAGE_1_NAME}} → {{STAGE_1_DTYPE_IN}} in → {{STAGE_1_ACC}} acc → {{STAGE_1_DTYPE_OUT}} out
  │       ▲ 检测来源: {{DETECTION_PATTERN_1}}
  │
  ├── Stage 2: {{STAGE_2_NAME}} → {{STAGE_2_FLOW}}
  │       ▲ 检测来源: {{DETECTION_PATTERN_2}}
  │
  ...
  │
  └── 输出 ({{OUTPUT_DTYPE}})
```

### 4.2 精度控制标志

| 标志 | 位置 | 取值 | 效果 |
|------|------|------|------|
| `{{PREC_FLAG_1}}` | `{{FILE}}:{{LINE}}` | 0 / 1 | `0`={{EFFECT_0}}, `1`={{EFFECT_1}} |
| `innerPrecise` | `*_aclnn_runner.cpp` | 0 / 1 | `0`=fp16 acc, `1`=fp32 acc |
| ... | ... | ... | ... |

### 4.3 Dtype 断点（Input ≠ Output）

| 条件 | Input Dtype | Output Dtype | 触发文件 |
|------|------------|-------------|---------|
| {{CONDITION_1}} | {{IN_DTYPE}} | {{OUT_DTYPE}} | `{{FILE}}:{{LINE}}` |
| ... | ... | ... | ... |

### 4.4 单阶段算子（若无多阶段 Pipeline）

```yaml
pipeline_type: single_stage  # 不需要 Pipeline 分析
note: "本算子为逐元素/简单运算，无中间 dtype 转换"
```

---

## 5. Execution Paths（执行路径）

> **目的**: 明确哪些条件下走哪个 Runner，Agent 调用 API 时选择正确路径。

### 5.1 Runner 选择决策树

```
{{OP_NAME}}Operation::CreateRunner()
  │
  ├── [条件 1] {{CONDITION_1}}
  │     └── → {{RUNNER_CLASS_1}}（{{PLATFORM_1}}）
  │           调用: {{ACLNN_API_1}}
  │
  ├── [条件 2] {{CONDITION_2}}
  │     └── → {{RUNNER_CLASS_2}}（{{PLATFORM_2}}）
  │           调用: {{OPS_API_2}}
  │
  └── [fallback] 默认
        └── → {{DEFAULT_RUNNER}}
```

### 5.2 平台支持矩阵

| 平台 | Runner | 特性支持 | 限制 |
|------|--------|---------|------|
| Atlas 910B | {{RUNNER}} | {{FEATURES}} | {{LIMITS}} |
| Atlas 950 | {{RUNNER}} | {{FEATURES}} | {{LIMITS}} |
| Atlas A2 | {{RUNNER}} | {{FEATURES}} | {{LIMITS}} |

### 5.3 关键 API 调用链

```
用户 API: atb::CreateOperation(param, &op)
  └─ op->Setup(inTensors, outTensors)
       └─ op->Execute(context, inTensors, outTensors)
            ├─ [ACLNN路径] aclnn{{OP_NAME}}GetWorkspaceSize() → aclnn{{OP_NAME}}()
            └─ [OPS路径] AsdOps::OpParam::{{OP_PARAM}} → {{OPS_KERNEL_CALL}}
```

---

## 6. Kernel Dependencies（Kernel 依赖）

> **目的**: 知道 Kernel 文件位置、Tiling 约束、Workspace 计算方式。

### 6.1 Kernel 清单

| Kernel 名称 | 文件 | 用途 | 平台 |
|------------|------|------|------|
| `{{KERNEL_NAME_1}}` | `{{KERNEL_FILE}}` | {{PURPOSE}} | {{PLATFORM}} |
| ... | ... | ... | ... |

### 6.2 Tiling 约束

| 约束项 | 值 | 来源 |
|--------|---|------|
| Tiling 维度 | {{TILING_DIMS}} | `{{TILING_STRUCT}}` |
| Block 大小限制 | {{BLOCK_LIMIT}} | `{{CONSTANT}}` |
| ... | ... | ... |

### 6.3 Workspace 大小

| 场景 | Workspace 公式 | 变量说明 |
|------|---------------|---------|
| 标准 | `{{WS_FORMULA}}` | {{VARS}} |
| 量化 | `{{WS_FORMULA_QUANT}}` | {{VARS}} |

---

## 7. Known Issues（已知问题与边界条件）

> **目的**: Agent 调试时直接查已知陷阱，无需重新发现。

### 7.1 已知问题

| # | 问题描述 | 影响范围 | 平台 | 规避方式 | 状态 |
|---|---------|---------|------|---------|------|
| 1 | {{ISSUE_1}} | {{SCOPE}} | {{PLATFORM}} | {{WORKAROUND}} | open/fixed/wa |
| ... | ... | ... | ... | ... | ... |

### 7.2 边界条件

| 条件 | 行为 | 错误码 |
|------|------|--------|
| {{EDGE_CASE_1}} | {{BEHAVIOR}} | {{ERROR_CODE}} |
| ... | ... | ... |

### 7.3 常见错误排查

| 错误信息 | 根因 | 解决方案 |
|---------|------|---------|
| `{{ERROR_MSG_1}}` | {{ROOT_CAUSE}} | {{SOLUTION}} |
| ... | ... | ... |

---

## 8. Test Coverage（测试覆盖）

> **目的**: Agent 知道如何运行测试、测试覆盖了哪些参数组合。

### 8.1 ATK 测试用例

| 测试文件 | 用例数 | 覆盖参数 | 覆盖平台 |
|---------|--------|---------|---------|
| `{{TEST_YAML}}` | {{COUNT}} | {{COVERED_PARAMS}} | {{PLATFORMS}} |
| ... | ... | ... | ... |

### 8.2 测试执行命令

```bash
# 生成用例
cd atk_test/atk_cida_atb/atb/{{INFER_OR_TRAIN}}/{{OP_NAME}}Operation/
atk case -f {{DESIGN_YAML}}

# 执行测试
atk task -n node.yaml -c result/{{YAML_NAME}}/json/all_{{YAML_NAME}}.json \
    -p ./ --task accuracy -ap ../../common
```

### 8.3 覆盖盲区

| 未覆盖的参数组合 | 原因 | 优先级 |
|----------------|------|--------|
| {{MISSING_COMBO_1}} | {{REASON}} | high/medium/low |
| ... | ... | ... |

---

## 9. Related Ops（相关算子）

> **目的**: 帮助 Agent 理解算子间关系，构建上下游上下文。

### 9.1 功能相似

| 算子 | 关系 | 区别 |
|------|------|------|
| `{{RELATED_OP_1}}` | {{RELATION}} | {{DIFF}} |
| ... | ... | ... |

### 9.2 组合使用（上下游）

```
{{UPSTREAM_OP}} → {{THIS_OP}} → {{DOWNSTREAM_OP}}
```

### 9.3 变体关系

| 变体 | 与主 Op 的区别 |
|------|---------------|
| `{{OP_NAME}}_with_stride` | 增加 stride 参数支持 |
| `{{OP_NAME}}_backward` | 反向传播版本 |
| ... | ... |

---

## Appendix A: 自动提取元数据

> 以下字段由 `atb-op-knowledge-extract` Skill 自动填充，供质量门禁使用。

| 字段 | 值 |
|------|-----|
| 提取耗时 | {{EXTRACT_TIME_SEC}}s |
| 读取文件数 | {{FILES_READ}} |
| 置信度评分 | {{CONFIDENCE_SCORE}}/100 |
| 需人工审核 | {{NEEDS_MANUAL_REVIEW}} |
| 审核原因 | {{REVIEW_REASON}} |

---

## Appendix B: 变更日志

| 日期 | 变更类型 | 变更章节 | 触发 Commit | 说明 |
|------|---------|---------|------------|------|
| {{DATE_1}} | auto/manual | {{CHAPTERS}} | `{{SHA}}` | {{DESC}} |
| ... | ... | ... | ... | ... |
