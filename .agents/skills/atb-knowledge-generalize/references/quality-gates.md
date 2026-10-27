# 质量门禁规则（Step 4）

## 4 项门禁

| # | 门禁 | 检查内容 | 通过条件 |
|---|------|---------|---------|
| 1 | 必填章节非空 | 9 个章节每个至少 3 行非空内容 | 全部通过 |
| 2 | 无 TODO/占位符 | 无 `{{...}}` / `TODO` / `TBD` | 0 个 |
| 3 | 交叉引用可解析 | Markdown 链接目标存在 | 全部可解析 |
| 4 | YAML 完整 | 14 个必填字段存在 + 值域合法 | 全部通过 |

## 判定结果

| 结果 | 条件 | 动作 |
|------|------|------|
| **auto-accept** | 4 项全部通过 | 写入 ATB 仓，状态→complete |
| **flag** | 任一项失败 | 写入但标记 needs_review + review_reason |

## 自动通过率目标

- S 级 Op: ≥90%
- M 级 Op: ≥80%
- L 级 Op: ≥70%
- XL 级 Op: 人工审核

## 集成 validate_knowledge_entry.py

门禁 1-4 通过调用 `scripts/validate_knowledge_entry.py` 执行，返回 `passed` + `error_count` + `warning_count`。

```bash
python3 scripts/validate_knowledge_entry.py <index.md> --atb-repo $ATB_REPO_PATH
# exit 0 → auto-accept
# exit 1 → flag
```
