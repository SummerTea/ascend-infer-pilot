---
name: atb-csv-tester
description: >
  运行 ATB (Ascend Transformer Boost) CSV 测试。当用户需要执行 CSV 格式的 ATB 测试用例、
  验证算子正确性、或运行任何ATB下的 CSV 测试文件时调用此技能。
  需配合 CANN 环境和已编译的 ATB 测试框架使用。
keywords:
    - atb
    - csv
    - test
    - csv-test
    - ascend-transformer-boost
    - 昇腾
    - 算子测试
metadata:
  version: "1.9.4"
  updated: "2026-05-11"
  skill-type: test
  allowed-tools: Bash(docker|bash|cd|ls|grep|find|echo|cat) Read(*)
  gates:
    - id: gate-5
      description: "全量回归门控"
      trigger: "Phase 5b 完成后，所有相关 CSV 必须全部通过，方可进入 Phase 6 交付"
hooks:
  PreToolUse:
    - matcher: "Write|Edit|Bash"
      hooks:
        - type: command
          command: "([ -z \"$CANN_PATH\" ] || [ ! -f \"$CANN_PATH/set_env.sh\" ]) && { echo '[PATH CHECK] CANN_PATH 未设置或无效，请先向用户获取 CANN 路径' >&2; exit 1; }; ([ -z \"$ATB_REPO_PATH\" ] || [ ! -d \"$ATB_REPO_PATH\" ]) && { echo '[PATH CHECK] ATB_REPO_PATH 未设置或无效，请先向用户获取 ATB 路径' >&2; exit 1; }"
  PostToolUse:
    - matcher: "Write|Edit"
      hooks:
        - type: command
          command: "echo '[REMINDER] 若 910B 测试全部通过，请提示用户在 Ascend950 设备上手动运行 CSV 测试。'"
    - matcher: "Bash"
      hooks:
        - type: command
          command: "echo '[PHASE 5A→5B REMINDER] 若 Phase 5a 设计用例已全部通过，请输出全量回归 CSV 列表，提示用户进入 Phase 5b。全量回归未完成前，禁止交付。'"
        - type: command
          command: "echo '[GATE 5 REMINDER] 若刚完成 CSV 测试，请确认: (1) 所有相关 CSV 已列出? (2) 是否已全部运行并通过? 未完成全量回归前，禁止交付。'"
  Stop:
    - hooks:
        - type: command
          command: "echo '[GATE 5 CHECK] 提醒：所有相关 CSV 测试文件是否已全部运行并通过？若未全部通过，严禁进入 Phase 6 交付。'"
---

# ATB CSV Tester

## Quick Reference

**用途**：执行 CSV 用例并完成 Gate 5 全量回归门控检查，给出可交付测试结论。

**渐进式披露阅读顺序**：

1. 完成「执行前 Checklist」与路径约束
2. 打开 **[references/csv-test-execution-playbook.md](references/csv-test-execution-playbook.md)** 按场景执行（含 `-n` 增量、Gate 5、Phase 5a/5b、NO_ERROR 配置与 Debug）

## 执行前 Checklist

- [ ] 已确认 `CANN_PATH`、`ATB_REPO_PATH` 有效
- [ ] 已确认先跑新增/修改用例（`-n`）再决定全量
- [ ] 已确认目标设备与 `SocVersion` 匹配
- [ ] 已确认 Gate 5 前必须完成相关 CSV 全量回归

## 功能概述

运行 ATB CSV 测试用例，验证算子正确性。需配合 CANN 环境和已编译的 ATB 测试框架。

## 路径约束

**必须从用户处获取以下路径**：

- `<CANN_PATH>`: CANN 安装路径（如 `/usr/local/Ascend/ascend-toolkit/latest`）
- `<ATB_REPO_PATH>`: ATB 仓库路径

**若路径无效，立即停止并报错。**

## 调用时机

- 运行 ATB CSV 测试（如 `linear.csv`）
- 验证已迁移算子的正确性
- CANN 环境下的算子级别功能测试

## 资源目录（按需读取）

| 资源 | 说明 |
|------|------|
| [`references/csv-test-execution-playbook.md`](references/csv-test-execution-playbook.md) | 测试优先级、设备与 Gate 5、Docker/CANN/ATB 步骤、`-t` 行为、Phase 5a/5b、格式说明、FAQ、NO_ERROR、Debug |
| [`scripts/run-csv-tests.sh`](scripts/run-csv-tests.sh) | CSV 测试批量执行脚本 |
| [`tests/run-tests.sh`](tests/run-tests.sh) | 脚本级测试入口 |

---

## 相关文档

- [ATB Skills 索引](../../SKILL.md)
- [ATB 测试框架编译](../atb-testframework-build/SKILL.md)
- [ATB Golden Developer](../atb-golden-developer/SKILL.md) — 编写 golden 参考实现
- [ATB Debug Guide](../atb-debug-guide/SKILL.md) — 测试失败排查
