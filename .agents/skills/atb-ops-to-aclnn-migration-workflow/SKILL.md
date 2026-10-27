---
name: atb-ops-to-aclnn-migration-workflow
description: >
  ATB OPS→ACLNN 迁移标准化工作流主模板。整合前置学习、设计文档生成、CSV用例设计、
  实际迁移、编译验证、测试验证全流程，提供明确的阶段 Gates 和用户确认机制。
keywords:
    - atb
    - aclnn
    - workflow
    - migration
    - ops
    - template
    - 标准化流程
    - 昇腾
metadata:
  version: "1.7.0"
  updated: "2026-05-11"
  skill-type: workflow
  allowed-tools: Bash(docker|bash|cd|ls|grep|find|echo|cat|git) Read(*) Write(*)
  gates:
    - id: gate-1
      description: "设计文档确认"
      trigger: "Phase 1 完成后，等待用户确认设计文档"
    - id: gate-2
      description: "CSV 用例确认"
      trigger: "Phase 2 完成后，等待用户确认 CSV 用例"
    - id: gate-5b
      description: "全量回归门控"
      trigger: "Phase 5b 完成后，所有相关 CSV 必须全部通过，方可进入 Phase 6"
    - id: gate-6
      description: "最终交付确认"
      trigger: "Phase 6 完成后，等待用户确认交付报告"
hooks:
  PreToolUse:
    - matcher: "Write|Edit|Bash"
      hooks:
        - type: command
          command: "grep -q 'gate-' ${CLAUDE_PROJECT_DIR}/.claude/plans/*.md 2>/dev/null && echo '[planning-with-files] ACTIVE PLAN with Gates detected - check plan before proceeding' || true"
  PostToolUse:
    - matcher: "Write|Edit"
      hooks:
        - type: command
          command: "echo '[HIL GATE REMINDER] 若刚完成设计文档/CSV用例/全量回归/交付报告，请确认是否需等待用户确认（Gate 1/2/5b/6）。严禁跳过 Gate 自动进入下一阶段。'"
  Stop:
    - hooks:
        - type: command
          command: "echo '[CHECK] 确认所有 Phase (0-6) 已完成、Gate 1/2/5b/6 已通过后，方可结束任务。'"
---

# ATB OPS→ACLNN 迁移标准化工作流

## Quick Reference

**用途**：提供 OPS→ACLNN 迁移 7 阶段主流程编排，控制 Gate 1/2/5b/6 的用户确认节奏。

**渐进式披露阅读顺序**：

1. 先完成「执行前 Checklist」明确任务边界
2. 再看「调用时机」判断是否应走标准主流程
3. 按需打开 [`references/workflow-gates-and-matrix.md`](references/workflow-gates-and-matrix.md) 核对禁止跳步与矩阵
4. 执行具体阶段时阅读 [`references/phases-detailed.md`](references/phases-detailed.md)

## 执行前 Checklist

- [ ] 已确认目标算子、目标设备和交付范围
- [ ] 已确认设计文档与 CSV 用例需用户 Gate 确认
- [ ] 已确认编译验证遵循最多 3 次规则
- [ ] 已确认 Gate 5b 未通过前禁止交付

## 功能概述

定义 ATB 算子从 OPS 接口迁移至 ACLNN 接口的**标准化 7 阶段工作流**，含 Human in the Loop 用户确认机制。

## 调用时机

- `{xxx}Quant`、`{xxx}Norm`、`Softmax` 等算子的 OPS→ACLNN 迁移
- 910B/950 设备启用 ACLNN 加速
- 保持对其他设备的兼容性

## 资源目录（按需读取）

| 资源 | 说明 |
|------|------|
| [`TASK_TEMPLATE.md`](TASK_TEMPLATE.md) | 任务提交模板 |
| [`references/workflow-gates-and-matrix.md`](references/workflow-gates-and-matrix.md) | Gates 概览、Phase 依赖矩阵、跳步拦截话术、启动自检 |
| [`references/phases-detailed.md`](references/phases-detailed.md) | Phase 0–6 输入输出、检查点、Gate、命令与交付模板 |
| [`references/faq-workflow.md`](references/faq-workflow.md) | HIL 与编译失败 FAQ |

---

## 详细内容

<details>
<summary>🔍 流程缩略图（完整图见 references）</summary>

```
[Phase 0] → [Phase 1] → Gate 1 → [Phase 2] → Gate 2 → [Phase 3] → [Phase 4]
    → [Phase 5a] → [Phase 5b] → Gate 5b → [Phase 6] → Gate 6
```

</details>

---

## 禁止跳步规则

**每次 Phase 转换须满足 Gate 与依赖矩阵**。完整矩阵、拦截话术与自检命令见 [`references/workflow-gates-and-matrix.md`](references/workflow-gates-and-matrix.md)。

---

## Skills 调用时序

| 阶段 | 调用的 Skill |
|------|-------------|
| Phase 1 | `atb-aclnn-operator-replacement-designer` |
| Phase 2 | `atb-csv-testcase-generator` |
| Phase 3 | `atb-aclnn-operator-migration` |
| Phase 4 | `atb-testframework-build` |
| Phase 5a | `atb-csv-tester`（正例/反例默认1次，性能默认400次） |
| Phase 5b | `atb-csv-tester` (Gate 5 全量回归) |
| 调试 | `atb-debug-guide` |

---

## 命令速查

```bash
# Phase 0-1: 设计和用例生成
# → atb-aclnn-operator-replacement-designer
# → atb-csv-testcase-generator
# → [等待用户确认 Gate 1 & 2]

# Phase 3: 实际迁移
# → atb-aclnn-operator-migration

# Phase 4: 编译
# → atb-testframework-build
# → [失败] atb-debug-guide

# Phase 5a: 小范围验证
# → atb-csv-tester（不指定 -t，正例/反例默认1次，性能默认400次）
# → [失败] atb-debug-guide
#
# Phase 5b: 全量回归
# → atb-csv-tester (Gate 5)
# → [失败] atb-debug-guide
```

各 Phase 的脚本级命令、Subagent 模板与交付报告结构见 [`references/phases-detailed.md`](references/phases-detailed.md)。

---

## 常见问题

见 [`references/faq-workflow.md`](references/faq-workflow.md)。

---

## 相关文档

- [任务提交模板](TASK_TEMPLATE.md)
- [ATB Skills 索引](../../SKILL.md)
