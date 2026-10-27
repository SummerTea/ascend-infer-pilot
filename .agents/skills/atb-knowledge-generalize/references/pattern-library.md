# 模式库 — 6 类 Op 泛化模板

## 1. Norm 类

**模板 Op**: `layer_norm` | **覆盖**: layer_norm, rms_norm, cohere_layernorm, layer_norm_with_stride, rms_norm_with_stride, rms_norm_backward

**共享模式**:
- layerType 三态: NORM / PRENORM / POSTNORM
- 量化支持: UNQUANT / INT8 + scale/offset
- epsilon 下限: 2e-38
- 最后维对齐: 32 bytes (量化模式)
- Runner: 950→ACLNN, 其他→Ops

**变体差异**:
- rms_norm: 无均值中心化，多 AddRmsNorm 融合
- cohere_layernorm: Cohere 特定
- _with_stride: stride 参数
- _backward: 反向传播

## 2. Attention 类

**模板 Op**: `self_attention` | **覆盖**: self_attention, paged_attention, multi_latent_attention, relay_attention, razor_fusion_attention, faupdate, ring_mla

**共享模式**:
- Pipeline: BMM1→Scale→Softmax→BMM2
- 精度控制: KernelType / innerPrecise
- Multi-SoC: 910A/910B/BNSD 变体
- Mask 类型: NORM/ALIBI/SLIDING_WINDOW/CAUSAL
- KVCache 管理

**变体差异**:
- paged_attention: Block 分页 KV
- multi_latent_attention: MLA 架构
- ring_mla: Ring 拓扑

## 3. Activation 类

**模板 Op**: `swiglu_quant` | **覆盖**: swiglu_quant, activation, elewise, rope, softmax, fused_add_topk_div, gating

**共享模式**:
- Dtype 断点: fp16/bf16 → int8 (量化融合)
- 逐元素/单阶段为主
- ACLNN + Ops 双路径

**变体差异**:
- swiglu_quant: 激活+量化融合 + smoothScales
- activation: 通用激活 (SiLU/ReLU/GELU)
- elewise: 通用逐元素 + DynamicQuant

## 4. Communication 类

**模板 Op**: `all_reduce` | **覆盖**: all_gather, all_gatherv, all_reduce, all_to_all, all_to_allv, all_to_allvv2, broadcast, send, recv, reduce_scatter, reduce_scatterv

**共享模式**:
- S 级复杂度 (4-6 文件)
- 纯 Ops 路径 (无 ACLNN)
- 无 dtype 断点
- 通信域/rank 参数

## 5. Other 类 (41 Op)

**覆盖**: elewise, linear, reshape_and_cache, as_strided, concat, cumsum, fill, gather, reduce, repeat, rope, slice, softmax, sort, split, transdata, transpose, block_copy, dynamic_ntk, faupdate, gating, group_topk, index_add, kv_cache, multinomial, nonzero, onehot, pad, scatter_elements_v2, set_value, unpad, where, grouped_matmul_with_routing, linear_parallel, linear_sparse, paged_cache_load, fused_add_topk_div, grouped_matmul_inplace_add, reshape_and_cache_omni, reshape_and_cache_with_stride, rope_q_concat, topk_topp_sampling

**共享模式**:
- 大部分 S/M 级，4-10 文件
- 轻量知识条目（路由级描述）
- Ops 或 ACLNN+Ops 路径

## 6. Train 类 (4 Op)

**覆盖**: rope_grad, strided_batch_matmul, pad_with_hidden_state, unpad_with_hidden_state

**共享模式**:
- S 级，4 文件
- 单一 OpsRunner
- 训练侧算子（反向/数据重排）

## 当前状态: 82/82 Op 知识条目已完成 (100%)
