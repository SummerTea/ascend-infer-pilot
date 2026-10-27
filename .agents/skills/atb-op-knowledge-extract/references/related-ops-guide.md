# Related Ops 推断规则（Step 9）

## 目标

识别功能相似算子、上下游组合关系、变体关系。

---

## 9.1 功能相似推断

### 按命名前缀分组

```python
# 从 inventory.csv 中按名称相似度分组
def find_similar_ops(op_name, all_ops):
    """基于名称前缀/后缀的相似度"""
    similar = []
    for other in all_ops:
        if other == op_name: continue
        
        # 共享前缀: layer_norm / layer_norm_with_stride
        common_prefix = os.path.commonprefix([op_name, other])
        if len(common_prefix) >= 5:
            similar.append((other, 'prefix', '变体/同族算子'))
        
        # 共享关键词: rms_norm / rms_norm_backward
        for kw in extract_keywords(op_name):
            if kw in other and len(kw) > 3:
                similar.append((other, 'keyword', f'共享关键词 {kw}'))
    
    return similar
```

### 按功能分类

| 分类 | 关键词 | 竞争关系 |
|------|--------|---------|
| norm | norm, rms, layer | LayerNorm ↔ RmsNorm（功能替代） |
| attention | attention, attn, mla, fa | SelfAttention ↔ PagedAttention（场景不同） |
| activation | activation, softmax, swiglu, rope | 各自独立 |
| communication | all_gather, all_reduce, send, recv | 通信原语互补 |

## 9.2 上下游推断

### 从 Transformer 架构推断

```python
# 标准 Transformer 上下游
transformer_pipeline = {
    'rms_norm':    {'up': ['matmul', 'linear', 'add'], 'down': ['attention', 'matmul']},
    'layer_norm':  {'up': ['matmul', 'linear', 'add'], 'down': ['attention', 'matmul']},
    'self_attention': {'up': ['rms_norm', 'layer_norm'], 'down': ['add', 'rms_norm']},
    'swiglu_quant':   {'up': ['linear', 'matmul'], 'down': ['rms_norm', 'matmul']},
    'rope':           {'up': [], 'down': ['self_attention', 'attention']},
}
```

## 9.3 变体关系

| 变体模式 | 关系 | 示例 |
|---------|------|------|
| `{op}_with_stride` | stride 支持 | layer_norm_with_stride |
| `{op}_backward` (train) | 反向传播 | rms_norm_backward |
| `{op}_grad` (train) | 梯度计算 | rope_grad |
| `gather_pre_{op}` | 融合前置 | gather_pre_rms_norm |
| `mm_deq_{op}_mm_deq` | 全流水线 | mm_deq_swiglu_quant_mm_deq |

### 提取规则

```python
def find_variants(op_name, all_ops):
    variants = []
    for other in all_ops:
        if other == op_name: continue
        # {op}_with_stride
        if other == f"{op_name}_with_stride" or other.startswith(op_name + "_"):
            variants.append((other, '变体', extra_info(other, op_name)))
        # gather_pre_{op}
        if other.endswith("_" + op_name):
            variants.append((other, '融合前置', 'Gather + 本Op'))
        # mm_deq_{op}_mm_deq
        if op_name in other and other != op_name:
            for kw in ['deq', 'quant', 'mm', 'gmm']:
                if kw in other:
                    variants.append((other, '复合变体', '含本Op的融合流水线'))
                    break
    return variants
```
