---
name: atb-csv-testcase-generator
description: >
  ATB CSV 测试用例生成技能。当用户需要为 ATB 算子创建 CSV 格式的泛化测试用例时调用此技能。
  覆盖：正例设计、反例设计、性能测试用例、CSV 格式规范。
keywords:
    - atb
    - csv
    - test
    - testcase
    - 昇腾
    - 泛化测试
    - 正例
    - 反例
    - 性能测试
metadata:
  version: "1.5.0"
  updated: "2026-05-11"
  skill-type: testcase
  gates:
    - id: gate-csv
      description: "CSV 测试用例确认"
      trigger: "CSV 用例设计完成后，必须等待用户确认再进入实际迁移阶段"
hooks:
  PreToolUse:
    - matcher: "Write|Edit|Bash"
      hooks:
        - type: command
          command: "([ -z \"$ATB_REPO_PATH\" ] || [ ! -d \"$ATB_REPO_PATH\" ]) && { echo '[PATH CHECK] ATB_REPO_PATH 未设置或无效，请先向用户获取 ATB 路径' >&2; exit 1; }"
  PostToolUse:
    - matcher: "Write"
      hooks:
        - type: command
          command: "echo '[HIL GATE 2] CSV 用例已生成/修改。若 CSV 用例设计完成，请向用户展示确认检查表并等待\"确认通过\"。未收到用户确认前，严禁进入实际迁移阶段。'"
  Stop:
    - hooks:
        - type: command
          command: "echo '[CHECK] 确认 CSV 用例已获用户确认（Gate 2）后，方可结束此技能。'"
---

# ATB CSV Testcase Generator

## Quick Reference

**用途**：为 ATB 算子生成 CSV 泛化测试用例（正例/反例/性能），并支持 Gate 2 用户确认。

**渐进式披露阅读顺序**：

1. 先完成「执行前 Checklist」确认输入与目标覆盖范围
2. 阅读 [`references/csv-design-and-columns.md`](references/csv-design-and-columns.md) 中的正/反/性能设计、列说明与多设备原则
3. 再按 [`references/csv-authoring-hil-and-output.md`](references/csv-authoring-hil-and-output.md) 执行 Step 1–8 与 Gate 2

## 执行前 Checklist

- [ ] 已确认目标算子与迁移阶段（设计后、迁移前）
- [ ] 已确认 `ATB_REPO_PATH` 与参考 CSV 路径可访问
- [ ] 已确认正例/反例/性能三类覆盖目标
- [ ] 已确认生成后需要用户进行 Gate 2 确认

## 功能概述

此技能用于为 ATB 算子生成 CSV 格式的泛化测试用例，支持正例、反例和性能测试用例设计。

## 调用时机

在以下情况下调用此技能：

- 用户需要为 ATB 算子创建 CSV 测试用例
- 用户需要生成正例、反例或性能测试用例

> **关于下文示例**：`references/csv-design-and-columns.md` 中出现的 `SwigluQuant*` CaseName **仅用于演示 CSV 列格式与错误码前缀**，请替换为目标算子命名。

## 任务分块

| 类型 | 说明 | 数量建议 |
|------|------|----------|
| 正例 | 验证正常功能，覆盖典型场景 | 5-15 个 |
| 反例 | 覆盖所有参数校验分支 | 10-20 个 |
| 性能测试 | 大小 shape 性能验证 | 5-10 个 |

## 任务前提知识

1. **参考已有 CSV 文件**：`tests/apitest/opstest/csv/` 目录下有丰富的参考用例
2. **性能测试标记**：`TestType` 列填写 `Performance` 即为性能测试
3. **预期错误标记**：`ExpectedError` 列填写错误类型，如 `NO_ERROR`、`I:ERROR_INVALID_TENSOR_DIM` 等

---

## 延伸阅读（必读）

| 文档 | 内容 |
|------|------|
| [`references/csv-design-and-columns.md`](references/csv-design-and-columns.md) | 正例/反例/性能设计原则、模板、列说明、ExpectedError、多设备拆分 |
| [`references/csv-authoring-hil-and-output.md`](references/csv-authoring-hil-and-output.md) | Step 1–8、双文件输出、Reviewer、Gate 2、输出模板、呈现话术 |

---

## 路径约束（必须执行）

执行此技能前，**必须从用户处获取以下路径**：

- `<ATB_REPO_PATH>`: ATB 仓库路径（如 `{your working path}ascend-transformer-boost`）

---

## 执行结果

> **执行后填写**：技能执行完成后，参照下方格式填写实际执行结果。

### 检查点检查表

| 步骤 | 检查点描述 | 状态 |
|------|-----------|------|
| - | 正例设计完成 | ✅ PASS / ❌ FAIL / ⏭️ SKIP |
| - | 反例设计完成 | ✅ PASS / ❌ FAIL / ⏭️ SKIP |
| - | 性能测试设计完成 | ✅ PASS / ❌ FAIL / ⏭️ SKIP |
| - | CSV 文件已创建（双文件） | ✅ PASS / ❌ FAIL / ⏭️ SKIP |
| - | **CSV 已拆分为 _func.csv 和 _perf.csv** | ✅ PASS / ❌ FAIL / ⏭️ SKIP |
| - | **用户已确认 CSV 用例** | ⬜ 待确认 |

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

## 相关文档

- [ATB Skills 索引](../../SKILL.md)
- [ATB Golden Developer](../atb-golden-developer/SKILL.md) — 如何为 `NO_ERROR` 正例编写 golden 参考实现
- [ATB CSV Tester](../atb-csv-tester/SKILL.md) — CSV 测试运行
- [ATB Debug Guide](../atb-debug-guide/SKILL.md) — 测试失败排查
