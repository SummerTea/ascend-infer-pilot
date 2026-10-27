# 批量编排策略（Step 2-3）

## 缺口盘点

对 82 Op 逐一标记状态：

| 标记 | 含义 | 判定条件 |
|------|------|---------|
| **OK** | 知识条目存在且最新 | index.md 存在 + source_commit == HEAD |
| **STALE** | 条目存在但源码已变更 | index.md 存在 + source_commit < HEAD |
| **PENDING** | 无知识条目 | index.md 不存在 |

## 批量提取优先级

```
PENDING > STALE > OK (跳过)
   S级优先 → M级 → L级 → XL级（复杂 Op 最后处理）
```

### 按分类批量编排

```python
BATCH_ORDER = [
    ('norm', 'S'),           # ~3 S 级 norm Op
    ('communication', 'S'),  # ~11 S 级通信 Op (结构最简单)
    ('activation', 'S'),     # ~5 S 级激活 Op
    ('norm', 'M'),           # ~2 M 级 norm Op
    ('attention', 'M'),      # ~4 M 级 attention Op
    ('activation', 'M'),     # ~5 M 级激活 Op
    ('attention', 'L'),      # ~7 L 级 attention Op
    ('norm', 'L'),           # ~1 L 级 norm Op
    ('other', '*'),          # ~35 S/M other Op
    ('attention', 'XL'),     # 最后: self_attention (最复杂)
]
```

## S 级优先策略

S 级 Op 结构简单（4-6 文件），模式一致，自动通过率高（目标 ≥90%）：
1. 用分类模板 Op 的模式推断参数位置
2. 自动生成 §1-9 全部章节
3. 质量门禁 auto-accept

## 批量执行流程

```
1. 缺口盘点 → 生成 PENDING/STALE 清单
2. 按 BATCH_ORDER 排序
3. 对每个 (category, tier) 组:
     a. 选分类模板 Op
     b. 对组内每个 Op 调用 atb-op-knowledge-extract
     c. 运行 validate_knowledge_entry.py
     d. auto-accept (通过门禁) / flag (失败)
4. 生成 batch-report.md
```

## 知识条目格式分层（经验总结）

| Tier | 格式 | 适用 |
|------|------|------|
| S | 轻量 (4-6 节) | 单一路径，模式简单 |
| M | 标准 (7-9 节) | 多 Runner 或量化变体 |
| L/XL | 深度 (9 节 + Pipeline) | 多 SoC 或多阶段融合 |
