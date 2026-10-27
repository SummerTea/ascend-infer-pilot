---
name: atb-knowledge-generalize
description: >
  批量泛化知识提取。基于模式库将已验证的模板 Op 知识泛化到同分类其他 Op，
  按缺口盘点（PENDING/STALE/OK）批量编排提取任务，经质量门禁自动接受或标记人工审核。
keywords: [atb, knowledge, generalize, batch, pattern, 批量, 泛化]
metadata:
  version: "1.0.0"
  updated: "2026-07-06"
  skill-type: orchestration
---

# ATB 知识批量泛化器

## 6 类模式库

| 分类 | 模板 Op | 模式特征 |
|------|--------|---------|
| norm | layer_norm | Norm/PreNorm/PostNorm + 量化 |
| attention | self_attention | BMM1→Softmax→BMM2 + multi-SoC |
| activation | swiglu_quant | 激活+量化融合 + dtype 断点 |
| communication | all_reduce | 通信原语 |
| other | — | 41 Op 轻量条目 |
| train | — | 4 Op 训练侧算子 |

## 资源目录

| 资源 | 说明 |
|------|------|
| [`references/pattern-library.md`](references/pattern-library.md) | 4 类模式库详细定义 |
| [`references/batch-strategy.md`](references/batch-strategy.md) | 批量编排 + 缺口盘点 (D11) |
| [`references/quality-gates.md`](references/quality-gates.md) | 质量门禁 (D12) |
