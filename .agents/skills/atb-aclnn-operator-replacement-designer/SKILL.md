---
name: atb-aclnn-operator-replacement-designer
description: >
  自动生成 ATB 到 ACLNN 算子替换的详细设计文档。接收用户提供的 ATB 和 ACLNN 接口文档链接，
  输出包含参数映射、开发自测、风险评估的 7 章结构化设计文档。
  TRIGGER when: 用户需要将 ATB 算子替换为 ACLNN 算子并撰写设计文档。
keywords:
    - atb
    - aclnn
    - operator
    - replacement
    - design
    - 算子
    - 设计文档
    - 昇腾
metadata:
  version: "1.5.1"
  updated: "2026-05-12"
  skill-type: design
  gates:
    - id: gate-design
      description: "设计文档确认"
      trigger: "设计文档生成完成后，必须等待用户确认再进入 CSV 用例设计阶段"
hooks:
  PreToolUse:
    - matcher: "Write|Edit|Bash"
      hooks:
        - type: command
          command: "errors=''; ([ -z \"$CANN_PATH\" ] || [ ! -f \"$CANN_PATH/set_env.sh\" ]) && errors=\"${errors}[PATH CHECK] CANN_PATH 未设置或无效（须含 set_env.sh），请先向用户获取 CANN 路径\\n\"; ([ -z \"$ATB_REPO_PATH\" ] || [ ! -d \"$ATB_REPO_PATH\" ]) && errors=\"${errors}[PATH CHECK] ATB_REPO_PATH 未设置或无效，请先向用户获取 ATB 仓库根路径\\n\"; [ -n \"$errors\" ] && { printf '%b' \"$errors\" >&2; exit 1; } || true"
  PostToolUse:
    - matcher: "Write"
      hooks:
        - type: command
          command: "echo '[HIL GATE 1] 设计文档已生成/修改。若设计文档已完成，请向用户展示确认检查表并等待\"确认通过\"。未收到用户确认前，严禁进入 CSV 用例设计阶段。'"
  Stop:
    - hooks:
        - type: command
          command: "echo '[CHECK] 确认设计文档已获用户确认（Gate 1）后，方可结束此技能。'"
---

# ATB到ACLNN算子替换详设文档生成器

## Quick Reference

**用途**：基于 ATB/ACLNN 接口信息生成替换设计文档（轻量 4 节或完整 7 章），并执行 Gate 1 确认。

**渐进式披露阅读顺序**：

1. 完成「执行前 Checklist」与下方资源链接
2. 阅读 **[references/replacement-design-playbook.md](references/replacement-design-playbook.md)**（规模检测、路径约束、WebFetch 阻断、阶段流程、章节模板、Gate 1）

## 执行前 Checklist

- [ ] **CANN_PATH**：已确认为 **CANN 安装根目录**，且存在 **`$CANN_PATH/set_env.sh`**（命名约定见包内 [`rules/path-placeholders.md`](../../rules/path-placeholders.md)）
- [ ] **ATB_REPO_PATH**：已确认为 **ATB 源码仓库根目录**（含 `scripts/build.sh` 等）
- [ ] 已确认接口文档输入（ATB/ACLNN 链接或附件）
- [ ] 已确认目标算子的规模分级（轻量模板/完整模板）
- [ ] 已确认输出文档需覆盖参数映射与风险项
- [ ] 已确认 Gate 1 必须等待用户确认

环境类排查可交叉参考 **atb-debug-guide** [`references/environment-checklist.md`](../atb-debug-guide/references/environment-checklist.md)。

## 功能概述

该工具能够根据用户提供的 ATB 和 ACLNN 接口文档链接，自动生成完整的算子替换详细设计文档。支持多种算子类型，提供标准化的文档结构和内容。

## 调用时机

在以下情况下调用此技能：

- 用户需要将 ATB 算子替换为 ACLNN 算子并撰写设计文档
- 用户已有 ATB 算子接口和 ACLNN 接口文档链接
- 变更涉及 LayerNorm、Softmax、RmsNorm 等标准算子

## 资源目录（按需读取）

| 资源 | 说明 |
|------|------|
| [`references/replacement-design-playbook.md`](references/replacement-design-playbook.md) | 规模分级、工作流程、章节结构、HIL Gate 1、工具集成 |
| [`templates/design-template.md`](templates/design-template.md) | 设计文档模板 |
| [`references/softmax_aclnn_runner_reference.md`](references/softmax_aclnn_runner_reference.md) | Runner 参考实现 |

---

## 执行结果

> **执行后填写**：技能执行完成后，参照下方格式填写实际执行结果。

### 检查点检查表

| 步骤 | 检查点描述 | 状态 |
|------|-----------|------|
| - | ATB 接口 URL 已提供 | ✅ PASS / ❌ FAIL / ⏭️ SKIP |
| - | ACLNN 接口 URL 已提供 | ✅ PASS / ❌ FAIL / ⏭️ SKIP |
| 1 | ATB 算子参数已提取 | ✅ PASS / ❌ FAIL / ⏭️ SKIP |
| 1 | ACLNN 接口参数已提取 | ✅ PASS / ❌ FAIL / ⏭️ SKIP |
| 2 | 参数映射表已创建 | ✅ PASS / ❌ FAIL / ⏭️ SKIP |
| 2 | 至少一个计算映射已定义 | ✅ PASS / ❌ FAIL / ⏭️ SKIP |
| 3 | 设计文档 7 个章节完整 | ✅ PASS / ❌ FAIL / ⏭️ SKIP |
| 3 | 风险评估表存在 | ✅ PASS / ❌ FAIL / ⏭️ SKIP |
| 4 | AclnnRunner 子类模式已记录 | ✅ PASS / ❌ FAIL / ⏭️ SKIP |
| 4 | 实现代码结构已定义 | ✅ PASS / ❌ FAIL / ⏭️ SKIP |
| HIL | 设计文档已保存至 working_files | ✅ PASS / ❌ FAIL / ⏭️ SKIP |
| HIL | **用户已确认设计文档** | ⬜ 待确认 |

**VERDICT: ✅ SUCCESS / ⚠️ PARTIAL / ❌ FAILED / ⏭️ SKIPPED**

### 问题列表（若有）

| 等级 | 检查点 | 问题描述 | 建议 |
|------|--------|---------|------|
| 🔴 CRITICAL | - | - | - |
| 🟡 WARNING | - | - | - |

### 执行摘要

- **执行时间**：
- **算子类型**：
- **ATB 接口链接**：
- **ACLNN 接口链接**：
- **通过率**：

---

## 相关文档

- [ATB Skills 索引](../../SKILL.md)
