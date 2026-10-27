# 一致性校验规则（Step 5）

## 3 项校验

### 1. 文件路径存在性

```python
def check_file_paths(entry, atb_repo):
    """验证 §1 Source Map 中所有文件路径在 ATB 仓中存在"""
    for f in entry.source_files:
        full = os.path.join(atb_repo, entry.op_repo_path, f)
        if not os.path.exists(full):
            yield f"文件不存在: {f}"
```

### 2. 参数数量匹配

```python
def check_param_count(entry, atb_repo):
    """验证 §3 参数约束表中的参数数量与源码 struct 一致"""
    param_header = os.path.join(atb_repo, entry.param_header)
    struct_members = parse_struct_members(param_header, entry.op_name)
    entry_params = entry.param_table_rows
    if len(struct_members) != len(entry_params):
        yield f"参数数量不匹配: 源码{len(struct_members)} vs 条目{len(entry_params)}"
```

### 3. Runner 逻辑可解析

```python
def check_runner_logic(entry, atb_repo):
    """验证 §5 中的 Runner 名称在源码中确实被创建"""
    op_cpp = os.path.join(atb_repo, entry.op_repo_path, f"{entry.op_name}_operation.cpp")
    for runner in entry.runners:
        if f"make_shared<{runner}>" not in open(op_cpp).read():
            yield f"Runner {runner} 在源码中未找到"
```

## 模拟变更测试

对已有知识条目的 Op 模拟 3 种变更类型，验证增量更新只修改受影响章节：

| 变更 | 预期影响 | 验证方式 |
|------|---------|---------|
| param struct 新增字段 | §3 §4 变更 | diff 确认仅 §3-4 修改 |
| CreateRunner 新增平台分支 | §5 变更 | diff 确认仅 §5 修改 |
| 常量 ALIGNMENT 修改 | §3 §6 变更 | diff 确认仅 §3 §6 修改 |
