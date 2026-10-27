# Git Diff → Op 映射规则（Step 1-2）

## 文件路径 → Op 名映射

### 规则 1: 直接映射

```
src/ops/ops_{infer|train}/{op_name}/* → {op_name}
include/atb/{infer|train}_op_params.h → 需解析 diff 内容确定
```

### 规则 2: 共享文件映射

```
src/kernels/mixkernels/laser_attention/ → self_attention, paged_attention, multi_latent_attention, relay_attention, swiglu_quant, linear, rms_norm
src/kernels/kernels/norm/ → layer_norm, rms_norm, cohere_layernorm
```

### 规则 3: 保守策略

共享文件变更 → 全量重提取所有关联 Op（不误更、不漏更）

## 解析示例

```python
def map_diff_to_ops(diff_files):
    ops = set()
    for f in diff_files:
        m = re.match(r'src/ops/ops_(infer|train)/(\w+)/', f)
        if m:
            ops.add(m.group(2))
        elif 'laser_attention' in f:
            ops.update(LASER_ATTENTION_OPS)
        elif 'kernels/norm' in f:
            ops.update(NORM_OPS)
        elif 'infer_op_params.h' in f:
            ops.update(extract_param_ops_from_diff(f))
    return ops
```
