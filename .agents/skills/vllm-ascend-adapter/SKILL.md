---
name: vllm-ascend-adapter
description: vllm-ascend 模型接入与部署技能——双段门禁（dummy 冒烟 + 真权重强制验证）、register_model / register_quantization_config / 注意力后端注册（AscendAttentionBackendImpl）、entry_points 插件落点、torch_npu 融合算子替换。Use when the user wants to adapt a new model to vllm-ascend, register a model/quantization config/attention backend, verify model loading via the two-stage gate, replace torch_npu fused operators (FIA / MLA absorb / RoPE / KV write / QK Norm / MoE GMM), or deploy an out-of-tree plugin; 中文触发：vllm-ascend、模型接入、注意力后端、量化注册、融合算子、插件。
---

# vllm-ascend 模型接入与融合算子替换（阶梯 3/4）

vllm-ascend 是本工程主力引擎（真机当前运行 `vllm-ascend:v0.21.0rc1` 服务容器）。模型接入走**注册表 + entry_points 插件**（阶梯 3），融合算子替换落 `repos/targets/vllm-ascend/`（阶梯 4）。挂载点索引见 [docs/03 硬件与引擎 §3.1](../../../docs/03-ascend-hardware-and-engines.md)。

## 触发

新模型在 vllm-ascend 上加载失败/走 fallback、config 字段不被识别、注意力后端未分派、量化配置未生效、或要替换 torch_npu 融合算子（FIA / MLA absorb / RoPE / KV write / QK Norm / MoE GMM）→ 用本技能。

## 前置契约

- 环境：容器内 vllm-ascend 镜像（如 `quay.io/ascend/vllm-ascend` 或内网 harbor 镜像）；宿主无 torch，**起容器跑**（见 [ascend-910b-server](../ascend-910b-server/SKILL.md)）。
- 源码：`repos/targets/vllm-ascend/`、`repos/targets/vllm/`（先 `bash scripts/manage_repos.sh clone <name>`）；改动 `repos/targets/` 必须以 `export-patch` 交付。
- **类名/接口以实际源码为准**：本文列出的注册 API 与 `AscendAttentionBackendImpl` 名称对应 [docs/03 §3.1](../../../docs/03-ascend-hardware-and-engines.md) 的口径；编码前 grep 实际源码确认，禁止臆造不存在的类名。

## 主流程

### 1. 两段门禁（接入冒烟，J1.5 入口检查点）

- **dummy 快步冒烟**：小权重/随机权重起服务，验证模型可加载、注册路径不报错（不进正确性判定）。
- **真权重强制验证**：换真权重，锚定独立 golden（transformers eager / 官方实现）比对 logits 与 token 序列。

**完成标准**：dummy 快步通过 → 真权重强制验证通过（含 RoPE scaling、attention mask、MoE 路由、tie embedding、量化 scale 反量化等易错点单测）；**「改造前后对比」不作正确性锚点**（J1.5 纪律）。

### 2. 模型接入（register_model + 权重名映射）

- 挂载点：`vllm/model_executor/models/registry.py` 的 `@ModelRegistry.register_model("Arch", "path.to.Model")`。
- 权重名映射：safetensors 键名 ↔ 建模层参数名逐层对齐；`config.json` 不被识别的字段（`tie_word_embeddings`、RoPE scaling、MoE 路由、量化 scale 布局）单独处理。

**完成标准**：模型类加载成功，权重名映射无遗漏（加载后无「weight not found」类告警，具体报错形态须上机核实）；非标结构判定落阶梯 3/4。

### 3. 注意力后端注册（勿臆造类名）

- 挂载点：vLLM `vllm/v1/attention/backends/registry.py`，`@register_backend(AttentionBackendEnum.CUSTOM, "ASCEND")`，实现为 **`AscendAttentionBackendImpl`**。
- 底层调用昇腾融合注意力 `npu_fused_infer_attention_score`；按平台/头维/KV dtype 分派。

**完成标准**：服务日志/代码路径确认走了 ASCEND 后端而非 fallback（如 naive attention）；`msprof op` 可见融合注意力算子生效。**禁止**臆造昇腾注意力类名——昇腾侧无 FlashAttention 系类名，实现是 `AscendAttentionBackendImpl`。

### 4. 量化配置注册（register_quantization_config）

- 挂载点：`vllm/model_executor/layers/quantization/__init__.py`，继承 `QuantizationConfig` 注册 `@register_quantization_config("method")`。
- 用途：权重加载期转置/重排与低比特路径（ATB 量化解码 / msmodelslim 导出权重，见 [ascend-quant-and-gate](../ascend-quant-and-gate/SKILL.md)）。

**完成标准**：量化方法被引擎识别，权重加载走注册路径；加载期一次完成重排/反量化（五不准红线 2，前向禁止动态转换权重）。

### 5. entry_points 插件落点（阶梯 3）

vllm-ascend 的 pyproject entry points + 扩展包加载，昇腾专属算子与 hook 以插件形态隔离集成。

**完成标准**：插件落 `src/plugins/`（本工程源码落点，[AGENTS.md](../../../AGENTS.md) §2），独立加载、不侵入引擎主干；可热替换/回退。

### 6. torch_npu 融合算子替换（阶梯 4）

按 [docs/02 诊断 SOP](../../../docs/02-ascend-diagnosis-sop.md) 瓶颈 1 的「融合度验证」识别未生效的融合算子，在 `repos/targets/vllm-ascend/` 的 ops/ 目录替换：

| 算子族 | 替换目标 |
| :--- | :--- |
| 注意力 | FIA（`npu_fused_infer_attention_score`）/ MLA absorb |
| 位置编码 | RoPE 融合 |
| KV 管理 | KV write 融合 |
| 归一化 | QK Norm |
| MoE | GMM（Grouped GEMM） |

**完成标准**：替换后 `msprof op` 确认融合算子生效且有效带宽/耗时改善；按 J6 双轨门禁验收（[门禁规则](../../../gates/README.md)）。

## 关键命令与判定表

| 检查项 | 命令/挂载点 | 判定 |
| :--- | :--- | :--- |
| 接入冒烟 | 起容器 + dummy/真权重两段 | 两段均过，正确性锚定 golden |
| 后端分派 | `vllm/v1/attention/backends/registry.py` + 服务日志 | 走 ASCEND 后端，无 fallback |
| 融合度 | `msprof op` 看融合算子 | 融合生效、占比下降 |
| 插件加载 | entry_points group + 扩展包 | 独立加载、可回退 |
| 类名核对 | `rg -n 'AscendAttentionBackend' repos/targets/vllm-ascend/` | 以实际源码为准；未核验的昇腾类名**禁止**出现在交付物 |

## 常见坑

1. **臆造注意力后端类名**：昇腾侧不存在 FlashAttention 系类名；昇腾后端实现是 `AscendAttentionBackendImpl`，底层 `npu_fused_infer_attention_score`——编码前 grep 实际源码。
2. **注册后仍走 fallback**：`register_backend` 只登记，分派还看平台/头维/KV dtype 条件；服务日志确认走了 ASCEND 后端才作数。
3. **config 不识别字段硬塞**：`tie_word_embeddings`、RoPE scaling、MoE 路由等字段须显式处理，否则静默用默认值 → 精度错而加载不报错。
4. **前向动态转换权重**：反量化/`.contiguous()` 必须在加载期一次完成（红线 2）；`.t()` 只改 stride 也会留非连续布局，同样在加载期消除。
5. **只用「改造前后对比」当正确性**：必须锚定独立 golden；两段门禁的**真权重强制验证**不可跳过。
6. **改 `repos/targets/` 不 export-patch**：引擎改动以 patch 交付（`bash scripts/manage_repos.sh export-patch <engine> <case>`），否则交付不可复现。

## 关联

- 挂载点与引擎速查：[docs/03 硬件与引擎](../../../docs/03-ascend-hardware-and-engines.md)；引擎清单 [repos/manifest.yaml](../../../repos/manifest.yaml)
- 接入冒烟与 golden 纪律：[docs/01 流水线与物理账本](../../../docs/01-pipeline-and-ledger.md)；测量 [ascend-msprof-diagnosis](../ascend-msprof-diagnosis/SKILL.md)
- 量化与门禁：[ascend-quant-and-gate](../ascend-quant-and-gate/SKILL.md)；红线与落点：[AGENTS.md](../../../AGENTS.md) §2/§5
