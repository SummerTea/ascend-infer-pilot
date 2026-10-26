---
name: ascend-quant-and-gate
description: 昇腾量化（msmodelslim）与精度/性能门禁技能——model-adapt/evaluate/tuning 流程、L1 逐位一致 / L2 数值门 / L3 有损门三级语义、evalscope/AISBench 评测、探索态与验收态协议、环境硬绑定复测。Use when the user wants to quantize a model with msmodelslim, run the L1/L2/L3 accuracy gates, evaluate with evalscope or AISBench against an OpenAI-compatible endpoint, promote results from exploration state to acceptance state, or re-verify after a CANN/torch_npu/chip upgrade; 中文触发：量化、msmodelslim、精度门禁、逐位一致、数值门、有损门、evalscope、AISBench、探索态、验收态。
---

# 昇腾量化与 L1/L2/L3 门禁（J6 双轨）

本技能是 J6 双轨门禁的昇腾落地：轨道 A 正确性（L1/L2/L3 三级）+ 轨道 B 性能（探索态/验收态）。**门禁脚本/阈值/基线由架构师持有并对 Agent 只读**（[门禁规则](../../../gates/README.md)）；Agent 只交实现与自测，不得改门禁。

## 触发

用 msmodelslim 做量化（model-adapt / evaluate / tuning）、判定量化/等价替换走哪级精度门禁（L1 逐位一致 / L2 数值门 / L3 有损门）、用 evalscope / AISBench 评测、把结果从探索态提升到验收态、或换 CANN/torch_npu/芯片后要求复测 → 用本技能。

## 前置契约

- 工具链：msmodelslim（`repos/refs/msmodelslim/` 只读参考，evaluate/tuning 门禁、EP 并行）；评测走 evalscope / AISBench（可打任意 OpenAI 兼容端点，直接用于 vllm-ascend）。
- 环境硬绑定：量化/性能结论**不可跨版本移植**——换 CANN（本机 9.0.0-beta.1）/ torch_npu / 芯片（910B3 vs 950）必须重跑校准与复测（[AGENTS.md](../../../AGENTS.md) 红线）。
- 测量口径：性能数据只信 `msprof` / `msprof op`；`time.time()` / `torch.npu.Event` / `do_bench` 禁用（[docs/02 诊断 SOP](../../../docs/02-ascend-diagnosis-sop.md)）。

## 主流程

### 1. msmodelslim 量化流程

- `model-adapt`：模型接入与算子适配（HF/本地模型 → 昇腾量化可处理形态）。
- `evaluate`：量化门禁——目标值 + 容差判定，**禁止改评测口径**，0 分自愈链。
- `tuning`：自动量化调优（档位搜索 + EP 并行）。

**完成标准**：导出量化权重（含 scale/zero-point 齐全）；`evaluate` 在目标容差内通过；`tuning` 记录档位与 EP 并行配置。

### 2. 定级门禁路径（先定路径再定阈值）

| 路径 | 门禁档 | 说明 |
| :--- | :--- | :--- |
| 融合 / 重排 / 平替 Kernel（数学等价） | **L1 逐位一致** | 同配置重跑逐位比对（含跨配置 md5 抽查） |
| 单算子级 / 引擎等价替换（bf16/fp16/fp8 基准） | **L2 数值门** | 余弦 + 最大/相对误差**双指标并用** |
| 量化 / KV 压缩（有损） | **L3 有损门** | 下游任务误差预算制，禁「零误差」标准 |

**完成标准**：明确当前改动落 L1/L2/L3 哪一档，并在任务书/门禁记录中声明判据。

### 3. L2 数值门执行

```
torch.testing.assert_close(actual, expect, rtol=..., atol=...)   # 按 dtype 理论浮点容差设定
```

**完成标准**：余弦相似度 + 最大/相对误差**双指标并用**（余弦对整体幅度不敏感，**不可单用**）；改造后落在「正确实现相对 golden 的偏差噪声底」内。

### 4. L3 有损门执行（评测工具）

用 evalscope（或 AISBench）打 vllm-ascend 的 OpenAI 兼容端点评测 MMLU / GSM8K：

```
# evalscope 可打任意 OpenAI 兼容端点（vllm-ascend 直接可用）；AISBench 为昇腾官方评测
# 具体子命令以 evalscope/AISBench 当前版本为准，须上机核实
```

**完成标准**：任务阈值按**任务与评测噪声**校准（多次运行 + 置信区间），不用「综合得分掉点 ≤ 1.0%」这类跨任务一刀切；**禁止「零误差」标准**。

### 5. 探索态 → 验收态（轨道 B 性能门禁）

- **探索态**：开发分支快速迭代，同窗 A/B（同并行度 / 同 batch / 同 shape / 同图分桶）验证方向；数据**不得入库**。
- **验收态**：冻结环境（版本快照）+ 门禁在干净容器/CI 独立执行，固定权重/数据集；附从零复现命令；**通过后才允许入库**。

**完成标准**：相对基线收益 ≥ 预估收益 80%（禁止 J2 物理下界作分母）；开环负载 Goodput 达标（P95 TTFT/TPOT）；验收态报告与版本快照归档 `cases/<case>/gates/`。

### 6. 环境硬绑定复测

记录 CANN / torch_npu / PyTorch / 驱动 / 引擎 commit 快照；任何一项变更后重跑校准与门禁。

**完成标准**：版本快照与门禁结果随报告归档；「换台机器跑不出同样结果」即未通过。

## 关键命令与判定表

| 检查项 | 工具/命令 | 判定 |
| :--- | :--- | :--- |
| 量化流程 | msmodelslim `model-adapt` / `evaluate` / `tuning` | evaluate 在目标容差内通过 |
| L1 | 同配置重跑逐位比对 | 逐位一致（不要求长生成 100% 逐字吻合作硬门禁） |
| L2 | `torch.testing.assert_close` | 余弦 + 最大/相对误差双指标在噪声底内 |
| L3 | evalscope / AISBench 评测 MMLU / GSM8K | 任务误差预算内（按评测噪声校准） |
| 性能门禁 | `msprof op` / 压测 | 收益 ≥ 预估 80%；探索态数据不得入库 |
| 版本快照 | 记录 CANN/torch_npu/驱动/引擎 commit | 换版本必须复测 |

## 常见坑

1. **把「100% 逐字吻合」当 L1 硬门禁**：bf16 下归约顺序一变 logits 就抖 ~1e-3，长生成必现个别 top-1 翻转，该门禁不可稳定通过——L1 语义是「数学等价路径的最低档」，正确实现也可能有噪声底。
2. **L2 单用余弦**：余弦对整体幅度不敏感，必须与最大/相对误差**双指标并用**；logprob 指标用 `mean |Δlogp|` / top-k KL，不用平均相对偏差（logp 接近 0 时分母爆炸）。
3. **L3 用「零误差」或跨任务一刀切**：有损路径必须下游任务误差预算制，阈值按任务与评测噪声校准。
4. **用探索态数据入库**：只有**验收态**（冻结环境 + 干净容器独立执行 + 完整复现链）才能入库；探索态 A/B 只作参考。
5. **换版本不复测**：量化/性能结论硬绑定 CANN / torch_npu / 芯片，换任一必须重跑校准与门禁（最高风险项）。
6. **门禁脚本可被交付方改写**：所有权必须分离（架构师持有、Agent 只读）；任务书中声明门禁路径禁写。

## 关联

- 三级门禁语义与所有权：[门禁规则](../../../gates/README.md)；J6 双轨方法论：[docs/01 流水线与物理账本](../../../docs/01-pipeline-and-ledger.md)
- 量化参考底座：`repos/refs/msmodelslim/`（只读）；评测端点对接见 [vllm-ascend-adapter](../vllm-ascend-adapter/SKILL.md)
- 环境前置与红线：[ascend-910b-server](../ascend-910b-server/SKILL.md)、[AGENTS.md](../../../AGENTS.md) §5/§9；测量口径 [ascend-msprof-diagnosis](../ascend-msprof-diagnosis/SKILL.md)
