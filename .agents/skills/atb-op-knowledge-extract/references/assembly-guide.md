# 组装与写入规则（Step 10）

## 目标

将 Step 1-9 提取的内容按模板组装为完整 `index.md` 并写入 ATB 仓。

---

## 10.1 组装流程

```
Step 1-2 结果 → §1 Source File Map + §2 Reading Order
Step 3 结果   → §3 Parameter Constraints
Step 4 结果   → §4 Computation Pipeline
Step 5 结果   → §5 Execution Paths
Step 6 结果   → §6 Kernel Dependencies
Step 7 结果   → §7 Known Issues
Step 8 结果   → §8 Test Coverage
Step 9 结果   → §9 Related Ops
inventory     → YAML frontmatter 元数据
```

## 10.2 YAML Frontmatter 填充

```python
def build_frontmatter(op_name, category, tier, results):
    """从 inventory.csv + 提取结果组装 YAML"""
    return f"""```yaml
op:
  name: "{op_name}"
  category: "{category}"
  tier: "{tier}"
  type: "{results.get('op_type', 'single')}"

source:
  repo_path: "src/ops/ops_{category}/{op_name}/"
  kernel_path: "{results.get('kernel_path', '')}"
  param_header: "include/atb/{'infer' if category == 'infer' else 'train'}_op_params.h"

knowledge:
  status: "complete"
  last_extracted: "{today()}"
  last_source_commit: "{git_sha()}"
  extractor_version: "1.0.0"

test:
  atk_test_path: "atk_test/atk_cida_atb/atb/{category}/{to_camel(op_name)}Operation/"
  has_atk_tests: {results.get('has_atk_tests', False)}
```"""
```

## 10.3 写入路径

```python
# ATB 仓 .agent/knowledge/ops/{category}/{op_name}/index.md
output_path = f"{atb_repo}/.agent/knowledge/ops/{category}/{op_name}/index.md"
os.makedirs(os.path.dirname(output_path), exist_ok=True)
```

## 10.4 后处理

```python
# 1. 更新主索引 README.md 中该 Op 的知识条目链接
update_readme_index(op_name, category)

# 2. 运行验证脚本
run_validate(output_path)

# 3. 标记提取元数据
append_extraction_metadata(output_path, {
    'extract_time_sec': elapsed,
    'files_read': len(source_files),
    'confidence_score': calculate_confidence(results),
})
```

## 10.5 质量门禁

| 门禁 | 检查 | 失败动作 |
|------|------|---------|
| YAML | required keys present | 拒绝写入 |
| Sections | 9 章节非空 | 标记 flag |
| Paths | 引用路径可解析 | 警告 |
| Pipeline | dtype 流转或单阶段声明 | 警告 |
| TODOs | 无未填充变量 | 警告 |

通过 `validate_knowledge_entry.py` 执行，全部通过 → auto-accept；任一失败 → 标记需人工审核。
