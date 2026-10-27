# 工作流 Gates 与 Phase 依赖

本文档为 `atb-ops-to-aclnn-migration-workflow` 主 SKILL 的延伸阅读：禁止跳步规则、依赖矩阵与自检话术。

## 阶段 Gates 概览

```
[Phase 0] 前置知识学习
    │
    ▼
[Phase 1] 设计文档生成 ────→ [用户确认 Gate 1] ───┐
    │                                         │
    ▼                                         │
[Phase 2] CSV用例设计 ─────→ [用户确认 Gate 2] ───┤
    │                                         │
    ▼                                         ▼
[Phase 3] 实际迁移（TDD） ←───────────────────────┘
    │
    ▼
[Phase 4] 编译验证（≤3次尝试）
    │
    ▼
[Phase 5a] 小范围验证
    ├─ Step 1: 前台跑 _func.csv（正例+反例, ~30s）
    └─ Step 2: 后台 subagent 跑 _perf.csv（性能, ~10min, 不阻塞）
    │
    ▼
[Phase 5b] 全量回归（所有相关 CSV）──→ [Gate 5b: 全量通过] ──┐
    │ （汇合 subagent 性能结果）                               │
    ▼                                                        ▼
[Phase 6] 交付报告 ←──────────────────────────────────────────┘
```

## Phase 依赖矩阵

| Phase | 前置 Gate | 未通过时的行为 |
|-------|----------|---------------|
| Phase 1 | Gate 0 (文档齐全) | **阻断** — 缺少接口文档时禁止进入设计阶段 |
| Phase 2 | Gate 1 (设计确认) | **阻断** — 用户未确认设计文档前禁止写 CSV |
| Phase 3 | Gate 2 (CSV 确认) | **阻断** — 用户未确认 CSV 用例前禁止写代码 |
| Phase 4 | Phase 3 完成 | 可执行（编译验证） |
| Phase 5a | Phase 4 通过 | **先跑 Phase 2 再跑 Phase 5a** — 用例未设计完禁止测试 |
| Phase 5b | Phase 5a 通过 | **全量回归** — 所有相关 CSV 必须全部运行并通过 |
| Phase 6 | Gate 5b 通过 | 可执行（交付报告） |

## 每阶段开始时必须执行的检查

```
1. 确认上一阶段 Gate 状态:
   - Gate X 是否已获用户确认?
   - 确认记录在哪里 (commit message / working_files / 对话记录)?

2. 如果 Gate 未通过:
   - 立即停止
   - 向用户报告: "Phase Y 需要 Gate X 确认，当前 Gate X 状态: 未确认"
   - 等待用户指示

3. 如果 Gate 已通过:
   - 明确告知用户: "Gate X 已通过，进入 Phase Y"
   - 继续执行
```

## 常见跳步错误与拦截话术

| 错误行为 | Agent 自查问题 | 拦截话术 |
|---------|--------------|---------|
| 编译后直接跑测试 | "CSV 用例是否已设计并确认?" | Phase 5a 需要 Gate 2 确认。当前 Gate 2 状态: 未确认。请先完成 Phase 2 CSV 用例设计。 |
| 5a 通过后直接写交付报告 | "全量回归是否已执行?" | Gate 5b 未通过: 全量回归测试未完成。请先执行 Phase 5b 并确认所有相关 CSV 通过。 |
| 实现后跳过设计文档 | "设计文档是否已生成?" | Phase 3 需要 Gate 1 确认。当前 Gate 1 状态: 未确认。请先完成 Phase 1 设计文档。 |
| WebFetch 失败后从代码反推 | "接口文档是否完整?" | Gate 0 未通过: ATB/ACLNN 接口文档获取失败，禁止从代码反推。请用户提供文档。 |
| CSV 设计完直接写代码 | "用户是否已确认 CSV?" | Phase 3 需要 Gate 2 确认。请先等待用户确认 CSV 用例。 |

## Agent 启动时的 Phase 状态自检

每次 Agent 被调用执行迁移任务时，必须先执行：

```
1. git log --oneline -5    → 检查当前分支做了什么
2. ls working_files/        → 检查哪些阶段产物已存在
3. 判断当前处于哪个 Phase  → 报告用户当前状态
4. 确认下一 Phase 的前置 Gate 是否通过 → 按依赖矩阵校验
```
