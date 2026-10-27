---
name: atb-op-knowledge-update
description: >
  检测 ATB 源码变更并增量更新知识条目。通过 git diff 识别变更文件，
  映射到受影响的 Op，按 11 种变更模式精准重提取受影响章节。
  TRIGGER when: ATB 仓有 git commit 变更，或用户要求更新某个 Op 的知识条目。
keywords:
    - atb
    - knowledge
    - update
    - incremental
    - git-diff
    - 知识更新
    - 增量
metadata:
  version: "1.0.0"
  updated: "2026-07-06"
  skill-type: maintenance
---

# ATB 知识条目增量更新器

> 检测源码变更 → 映射受影响 Op → 增量重提取。

## 工作流

```
1. git diff --name-only                  → 变更文件列表
2. diff-analysis 映射文件→Op              → 受影响 Op 清单
3. change-classification 判定变更类型     → 受影响章节
4. 增量重提取（仅重提取受影响章节）
5. consistency-check 一致性校验           → 交叉引用/路径/参数
6. 写回 index.md + 更新变更日志
```

## 资源目录

| 资源 | 说明 |
|------|------|
| [`references/diff-analysis.md`](references/diff-analysis.md) | git diff → Op 映射规则 |
| [`references/change-classification.md`](references/change-classification.md) | 11 种变更模式 → 受影响章节 (D11) |
| [`references/consistency-checks.md`](references/consistency-checks.md) | 文件存在/参数匹配/Runner 可解析 (D12) |
