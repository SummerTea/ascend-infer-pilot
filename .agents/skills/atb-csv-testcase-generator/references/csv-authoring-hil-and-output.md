# CSV 编写步骤、Gate 2 与用户确认

本文为 `atb-csv-testcase-generator` 延伸阅读：路径前置后的 Step 1–8、Reviewer、HIL 检查表与执行结果占位。

## 编写步骤

### Step 1: 获取接口规格
从用户或官方文档获取算子的：
- 输入输出定义
- 参数约束
- 数据类型支持

### Step 2: 阅读源码获取校验逻辑
```bash
# 查看参数校验
cat <ATB_REPO_PATH>/src/ops/ops_infer/<op_name>/<op_name>_operation.cpp

# 查找 ERROR_INVALID_* 分支
grep -n "ERROR_INVALID" <ATB_REPO_PATH>/src/ops/ops_infer/<op_name>/<op_name>_operation.cpp
```

### Step 3: 设计正例
覆盖：
- 典型数据类型的基例
- 主流模型的常见 shape
- 边界条件

### Step 4: 设计反例
覆盖所有校验分支：
- 数据类型校验
- 维度数量校验
- 维度值校验
- 参数校验
- 输出 tensor 校验

### Step 5: 设计性能测试
覆盖：
- 大/中/小 shape
- 不同数据类型
- 边界值

### Step 6: 创建 CSV 文件（双文件输出）

**⚠️ 必须产出两个独立 CSV 文件，不可合并为一个**：

```bash
# 创建功能用 CSV（正例 + 反例）
touch <ATB_REPO_PATH>/tests/apitest/opstest/csv/<op_name>_func.csv

# 创建性能用 CSV（性能用例）
touch <ATB_REPO_PATH>/tests/apitest/opstest/csv/<op_name>_perf.csv

# 可选：创建合并全量文件
touch <ATB_REPO_PATH>/tests/apitest/opstest/csv/<op_name>_test.csv
```

#### 拆分规则

| 文件 | 内容 | TestType 列 | 用途 |
|------|------|------------|------|
| `{op}_func.csv` | 所有 TestType 非 Performance 的用例（正例+反例） | 空或 Function | Phase 5a 前台快速验证 |
| `{op}_perf.csv` | 所有 TestType=Performance 的用例 | Performance | Phase 5a 后台 subagent 运行 |
| `{op}_test.csv` | 全部用例（func + perf 合并） | 混合 | 全量参考 / Phase 5b 全量回归 |

#### 拆分理由
- 正例/反例用 `-t 1`（默认），秒级完成
- 性能用例默认 400 次迭代，耗时长且可能 OOM
- 分文件允许 Phase 5a 先快速验证功能，再后台跑性能
- `_func.csv` 和 `_perf.csv` 各有独立完整 header（21 列）

### Step 7: 自动引入 Reviewer Agent 评审 ⭐

**⚠️ 强制步骤 — Gate 2 之前必须执行**

CSV 文件创建后，**必须**调用 `superpowers:requesting-code-review` agent 进行评审，不可跳过。

**评审内容**:

| 评审维度 | 检查内容 |
|---------|---------|
| 完整度 | 正例/反例/性能是否覆盖所有必要场景 |
| 正确性 | OpParam JSON 是否与设计文档参数映射一致 |
| Shape 一致性 | InShape/OutShape 是否与 ACLNN 接口约束一致 |
| 设备分离 | 910B/950 差异场景是否正确分离 SocVersion |
| 格式规范 | 21 列、`|` 分隔符、数据类型名称 |

**评审输入**:
- CSV 文件路径
- 设计文档路径（来自 Phase 1 的 `*_replacement_design.md`）
- ACLNN 接口参数约束（来自详设第 2 章）

**评审通过标准**:
- 无遗漏的正例场景（dtype/shape/边界）
- 反例覆盖所有 `ERROR_INVALID_*` 分支
- 所有 Shape 经 ACLNN 参数约束预检通过
- 无格式错误

**评审问题修复后**，方可进入 Gate 2 用户确认。

### Step 8: 运行测试验证
```bash
source <CANN_PATH>/set_env.sh
source <ATB_REPO_PATH>/output/atb/set_env.sh --cxx_abi=1
cd <ATB_REPO_PATH>/tests/framework/python/CsvOpsTestTool
python3 atb_csv_ops_test.py -i <CSV_FILE_PATH>
```

<details>
<summary>苏格拉底式提问模板（点击展开）</summary>

在开始编写前，确认以下问题：

1. **算子接口**：
   - 输入/输出张量的数量和形状？
   - 支持的数据类型？
   - 参数的合法取值范围？

2. **已有参考**：
   - 是否有同类型算子的 CSV 可参考？
   - 是否已有该算子的测试用例？

3. **特殊约束**：
   - 是否有 UB 限制？
   - 是否有内存限制？
   - 是否有特定 shape 要求？
</details>

## 输出模板

```
## CSV 测试用例设计

### 算子信息
- **算子名称**: XxxOperation
- **接口规格**: [简述]

### 正例列表 (N 个)
| CaseName | InShape | OutShape | 说明 |
|----------|---------|----------|------|
| XxxBase | 128,4096 | 128,2048 | 基例 |
| ... | ... | ... | ... |

### 反例列表 (M 个)
| CaseName | ErrorType | 覆盖分支 |
|----------|-----------|----------|
| XxxErrorDtype | ERROR_INVALID_TENSOR_INI_MATCH | dtype 校验 |
| ... | ... | ... |

### 性能测试列表 (P 个)
| CaseName | InShape | 说明 |
|----------|---------|------|
| XxxPerfLarge | 2048,16384 | 大 shape |
| ... | ... | ... |

### 统计
- 正例: N 个
- 反例: M 个
- 性能测试: P 个
- 总计: N+M+P 个

### 保存路径
- **功能 CSV**: `{ATB_REPO_PATH}/tests/apitest/opstest/csv/{op_name}_func.csv`（正例+反例）
- **性能 CSV**: `{ATB_REPO_PATH}/tests/apitest/opstest/csv/{op_name}_perf.csv`（性能用例）
- **合并 CSV**（可选）: `{ATB_REPO_PATH}/tests/apitest/opstest/csv/{op_name}_test.csv`
- **备份/预览**: `{WORKING_DIR}/`
```

## Human in the Loop: 用户确认检查点 ⭐

**⚠️ 强制检查点 - 不可跳过**

CSV 用例设计完成后，必须等待用户确认后方可进入实际迁移阶段。

### 确认前准备
1. **保存 CSV**: 将生成的 CSV 用例保存至 ATB 仓库目录
   - **功能 CSV**: `{ATB_REPO_PATH}/tests/apitest/opstest/csv/{op_name}_func.csv`（正例+反例）
   - **性能 CSV**: `{ATB_REPO_PATH}/tests/apitest/opstest/csv/{op_name}_perf.csv`（性能用例）
   - **合并 CSV**（可选）: `{ATB_REPO_PATH}/tests/apitest/opstest/csv/{op_name}_test.csv`

2. **准备确认清单**: 供用户逐项确认

### 用户确认检查表

```markdown
## CSV 用例确认 - {OpName}

### 待确认文件
- **功能 CSV**: `{ATB_REPO_PATH}/tests/apitest/opstest/csv/{op_name}_func.csv`（正例 X 个 + 反例 Y 个）
- **性能 CSV**: `{ATB_REPO_PATH}/tests/apitest/opstest/csv/{op_name}_perf.csv`（性能 Z 个）

### 确认检查表
| 检查项 | 说明 | 用户确认 |
|--------|------|----------|
| 正例覆盖典型场景 | 包含 float16/bf16 基础用例，主流模型常见 shape | [ ] |
| 反例覆盖所有校验分支 | 覆盖所有 ERROR_INVALID_* 类型 | [ ] |
| 性能测试覆盖大小 shape | 包含大/中/小 shape 测试 | [ ] |
| CSV 已拆分为双文件 | `_func.csv` 和 `_perf.csv` 各自独立 | [ ] |
| CSV 格式符合规范 | 列数=21，分隔符=|，无多余空格 | [ ] |
| 数据类型名称正确 | 使用 data_generation.py 支持的名称 | [ ] |
| ExpectedError 类型正确 | 与参数校验逻辑匹配 | [ ] |
| 可进入实际迁移阶段 | CSV 用例已通过审查 | [ ] |

### 确认方式
- **通过**: 回复 "确认通过" 或逐项打勾确认
- **修改**: 指出具体问题，返回修改后重新确认

### 后续步骤
确认通过后，将进入 Phase 3: 实际迁移阶段
- 下一步调用: `atb-aclnn-operator-migration`

**⚠️ 未收到用户确认前，禁止进入实际迁移阶段**
```

### 向用户呈现方式

```markdown
我已生成 {OpName} 算子的 CSV 测试用例，已拆分为两个独立文件，请确认以下内容：

📄 **功能 CSV**: `{ATB_REPO_PATH}/tests/apitest/opstest/csv/{op_name}_func.csv`
   - 正例: N 个
   - 反例: M 个
📄 **性能 CSV**: `{ATB_REPO_PATH}/tests/apitest/opstest/csv/{op_name}_perf.csv`
   - 性能测试: P 个

Phase 5a 测试时将分两步：
1. 前台跑 _func.csv（秒级完成）
2. 后台 subagent 逐个跑 _perf.csv（避免 OOM）

请检查：
1. 正例是否覆盖了所有典型场景和数据类型？
2. 反例是否覆盖了所有参数校验分支？
3. 性能测试的 shape 选择是否合理？
4. CSV 拆分是否正确（正例/反例在 _func，性能在 _perf）？

回复 "确认通过" 进入实际迁移阶段，或指出需要修改的地方。
```

<details>
<summary>保存路径规范（点击展开）</summary>

| 文件类型 | 路径 | 说明 |
|----------|------|------|
| 功能 CSV | `{ATB_REPO_PATH}/tests/apitest/opstest/csv/{op_name}_func.csv` | 正例+反例，Phase 5a 前台跑 |
| 性能 CSV | `{ATB_REPO_PATH}/tests/apitest/opstest/csv/{op_name}_perf.csv` | 性能用例，Phase 5a 后台 subagent 跑 |
| 合并 CSV（可选） | `{ATB_REPO_PATH}/tests/apitest/opstest/csv/{op_name}_test.csv` | 全量参考

**变量说明**:
- `ATB_REPO_PATH`: ATB 仓库路径
- `WORKING_DIR`: working_files 目录
- `op_name`: 算子名称小写（如 `{xxx}quant`）
</details>

## 执行结果

> ⚠️ **执行后填写**：技能执行完成后，参照下方格式填写实际执行结果。

### 检查点检查表

| 步骤 | 检查点描述 | 状态 |
|------|-----------|------|
| - | 正例设计完成 | ✅ PASS / ❌ FAIL / ⏭️ SKIP |
| - | 反例设计完成 | ✅ PASS / ❌ FAIL / ⏭️ SKIP |
| - | 性能测试设计完成 | ✅ PASS / ❌ FAIL / ⏭️ SKIP |
| - | CSV 文件已创建（双文件） | ✅ PASS / ❌ FAIL / ⏭️ SKIP |
| - | **CSV 已拆分为 _func.csv 和 _perf.csv** | ✅ PASS / ❌ FAIL / ⏭️ SKIP |
| - | **用户已确认 CSV 用例** ⭐ | ⬜ 待确认 |

**VERDICT: ✅ SUCCESS / ⚠️ PARTIAL / ❌ FAILED / ⏭️ SKIPPED**

### 问题列表（若有）

| 等级 | 检查点 | 问题描述 | 建议 |
|------|--------|---------|------|
| 🔴 CRITICAL | - | - | - |
| 🟡 WARNING | - | - | - |

### 执行摘要

- **执行时间**：
- **算子名称**：
- **正例数量**：
- **反例数量**：
- **性能测试数量**：
- **通过率**：

---
