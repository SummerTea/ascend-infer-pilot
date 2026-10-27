---
name: atb-op-knowledge-extract
description: >
  从 ATB 算子源码自动提取结构化知识条目。读取路由文件确定源码清单，
  分析 C++ 源码提取参数约束、Computation Pipeline（dtype 流转）、
  执行路径、Kernel 依赖、已知问题，最终组装为 9 章节 Markdown 知识条目。
  TRIGGER when: 用户需要提取/生成某个 ATB 算子的知识条目，或批量提取分类下全部算子。
keywords:
    - atb
    - knowledge
    - extract
    - operator
    - pipeline
    - dtype
    - 知识提取
    - 算子分析
    - 昇腾
metadata:
  version: "1.0.0"
  updated: "2026-07-03"
  skill-type: analysis
---

# ATB Op 知识提取器

> 从 ATB 算子源码自动提取结构化知识，输出 9 章节 `index.md`。

## Quick Reference

- **输入**: ATB Op 名称（如 `layer_norm`）
- **输出**: `.agent/knowledge/ops/{category}/{op_name}/index.md`（9 章节 + YAML frontmatter）
- **模板**: `templates/knowledge-entry-template.md`
- **验证**: `scripts/validate_knowledge_entry.py`（ATB Knowledge 仓）

## 10 步提取流程

```
Step 1:  路由读取       → 读 routing/{op}.md → 获取文件清单+阅读顺序
Step 2:  Source File Map → 扫描 Op 目录 → 文件角色分类
Step 3:  Parameter Cts   → 解析 param struct + InferShape → 约束表
Step 4:  Computation Pipe→ 6 种 dtype 模式检测 → Pipeline 流转图
Step 5:  Execution Paths → CreateRunner 分析 → 决策树+平台矩阵
Step 6:  Kernel Deps     → Kernel/Tiling/Workspace 提取
Step 7:  Known Issues    → 错误处理模式 + 边界条件提取
Step 8:  Test Coverage   → ATK 测试识别 + 覆盖盲区
Step 9:  Related Ops     → 上下游 + 变体关系推断
Step 10: 组装写入         → 模板填充 → YAML → 9 章节 → index.md
```

## Step 1-3 详细规则

详见:
- `references/source-map-guide.md` — Step 2 文件角色识别规则
- `references/param-extraction-guide.md` — Step 3 参数提取规则
- `references/pipeline-analysis.md` — Step 4 的 6 种 dtype 检测模式（D6）

## 使用方式

```bash
# 单个算子提取
atb-op-knowledge-extract layer_norm

# 批量提取（分类下全部算子）
atb-op-knowledge-extract --category norm --batch

# 仅执行 Step 1-3（参数层）
atb-op-knowledge-extract layer_norm --steps 1-3
```

## 资源目录

| 步骤 | 资源 | 说明 |
|------|------|------|
| 1-2 | [`references/source-map-guide.md`](references/source-map-guide.md) | 路由读取 + 文件角色识别 |
| 3 | [`references/param-extraction-guide.md`](references/param-extraction-guide.md) | 参数约束提取（struct/InferShape/ini） |
| 4 | [`references/pipeline-analysis.md`](references/pipeline-analysis.md) | 6 种 dtype 检测 + Pipeline 组装 ⭐ |
| 5 | [`references/execution-path-guide.md`](references/execution-path-guide.md) | Runner 决策树 + 平台矩阵 |
| 6 | [`references/kernel-deps-guide.md`](references/kernel-deps-guide.md) | Kernel/Tiling/Workspace 提取 |
| 7 | [`references/known-issues-guide.md`](references/known-issues-guide.md) | 错误+边界条件提取 |
| 8 | [`references/test-coverage-guide.md`](references/test-coverage-guide.md) | ATK 测试定位 + 盲区识别 |
| 9 | [`references/related-ops-guide.md`](references/related-ops-guide.md) | 相似/上下游/变体推断 |
| 10 | [`references/assembly-guide.md`](references/assembly-guide.md) | 组装写入 + 质量门禁 |
| - | [`templates/knowledge-entry-template.md`](templates/knowledge-entry-template.md) | 9 章节知识条目模板 |
