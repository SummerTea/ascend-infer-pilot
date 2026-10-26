# 03 · 昇腾硬件代际物理规格与引擎扩展挂载点

> **定位**：910B/910C vs 950PR/950DT 代际物理规格、910B3 评测基线事实、四大引擎的昇腾扩展挂载点索引、950 落地建议。
> **配套**：[流水线与物理账本](01-pipeline-and-ledger.md)（P_eff/BW_eff 校准）｜ [诊断 SOP](02-ascend-diagnosis-sop.md) ｜ [技能目录](04-skill-catalog-and-maintenance.md)
> **硬件参数以昇腾技能选型指南 §2.2 与 §5 为准**；本文档为 L2 层知识底座，**使用前须核对 CANN / torch_npu / 引擎 commit**（扩展挂载点与支持矩阵随版本变动）。

---

## 1. 910B/910C vs 950PR/950DT 代际物理规格对比

| 维度 | 910B/910C（A2/A3） | **950PR/950DT（A5，arch35）** |
| :--- | :--- | :--- |
| **Vector 单元** | 仅 **SIMD**（MemBase 体系） | **SIMD + SIMT 双模型**（DCache / Warp Scheduler / 128KB RF） |
| **UB（Unified Buffer）** | **16 group × 3 × 4KB** | **8 group × 2 × 16KB**（**Bank 冲突规则重写**，不得沿用 910B 的 Bank 规划） |
| **新增数据类型** | 无（BF16/FP16/INT8/INT4 低比特经 ATB/msmodelslim 路径） | **HiF8（hifloat8_t）**、**MXFP4 / MXFP8**（MXFP8 量化仅 A5/950 硬件支持） |
| **数据通路** | 经典 UB↔HBM / L0 体系 | 新增 **L0C→UB**、**UB→L1**、**SSBuffer** CV 消息通路 |
| **通信引擎** | — | 新增 **CCU**（IO-Die 内），msprof 可采 **CCU 带宽** |
| **msprof 指标** | 支持 **PipelineExecuteUtilization** / **MemoryAccess** | **不支持上述两项**；新增 **CCU / UB 带宽**采集 |
| **核心/Cube/Vector 边界** | Cube（矩阵）+ Vector（SIMD）分工经典；算力受限时先看 Cube 利用率 | SIMT 引入 Warp 级并行，Vector 与 Cube 的负载划分需重新核算；HiF8/MX 精度下 `P_eff` 大幅上移、`B* = P_eff/BW_eff` 同步上移 |
| **工具链支持** | 全套技能覆盖 | CANN 9.0+ 支持（→9.2.0 新增 950 系 8bit/4bit 低精度、MoE Dispatch/Combine 直驱 URMA、Engram、CATLASS Python 核函数）；**技能层仅 4 处内嵌标记** |
| **仿真验证** | — | **NPU Simulator（cannsim）仅支持 950PR/950DT** |

> **取证结论**：950 新特性（HiF8 / SIMT / RegBase / MX）全在 CANN / `cann/asc-devkit` 文档层，多处标注「资料开发中」。**技能生态滞后于硬件发布**——950 场景必须先仿真验证、再上真机（见 §5）。

**对账本公式的直接影响**（联动 [物理账本 §4](01-pipeline-and-ledger.md)）：

| 影响面 | 910B3 | 950 |
| :--- | :--- | :--- |
| `P_eff` 校准 | 大 GEMM 用 BF16/FP8 标定 | 用 HiF8 / MXFP4 / MXFP8 档位标定（`B*` 上移，访存受限区间收窄） |
| `BW_eff` 校准 | 大 copy 标定 HBM 带宽 | 需注意新增通路（L0C→UB / UB→L1 / SSBuffer）在特定算子中替代部分 HBM 往返，`bytes_min` 口径随之改变 |
| msprof 判据 | `PipelineExecuteUtilization` / `MemoryAccess` | 这两项**不可用**，改用 CCU / UB 带宽指标（判据阈值需重标，不得平移） |
| 诊断 SOP | [诊断 SOP](02-ascend-diagnosis-sop.md) 阈值直接可用 | 阈值按 §1 差异重校准后复用 |

---

## 2. 910B3 评测基线事实（本机）

| 项 | 值 |
| :--- | :--- |
| 评测服务器 | `10.19.93.115`（SSH 端口 **22022**，密钥 `~/.ssh/910b_ed25519`，`-o IdentitiesOnly=yes`，免密；另有 `puaiuc` 账号）；主机名 `phy-10-19-93-115`，Ubuntu 24.04 LTS，**192 核**，内存约 **1TB（1005 GB）** |
| 卡型 | **8× 910B3**（A2/A3 代际） |
| HBM | **64GB/卡**（`npu-smi` 报 65536MB） |
| 工具版本 | `npu-smi 25.5.1`；驱动 `Version=25.5.1`、`ascendhal_version=7.35.23`（`/usr/local/Ascend/driver/version.info`） |
| CANN | **CANN 9.0.0-beta.1**（`/usr/local/Ascend/cann` → `cann-9.0.0-beta.1`；`latest/version.cfg` 为空文件，用 `cann/version.cfg` 或目录名取版本；`/usr/local/Ascend/cann-9.0.0` 是 0 字节占位文件，勿当目录） |
| 拓扑 | 单机 8 卡**全互联 = HCCS**（`npu-smi info -t topo` 实测，非 RoCE）；CPU 亲和分别绑 0-23/48-71/96-119/144-167；跨机 RoCE 需 `ethtool` / HCCL 诊断 |
| 工具 PATH | `msprof` / `msprof-analyze` / `ascend-dmi` / `atc` / `hccl_test` **不在默认 PATH**（`command -v` 为空），必须先 `source /usr/local/Ascend/ascend-toolkit/set_env.sh` |
| 宿主与容器 | 宿主 Python 3.12.3，**未安装 torch / torch_npu**（`import torch` 失败），评测**一律走 Docker 容器**；Docker 29.8.0（`/snap/bin/docker`），镜像源含 `quay.io/ascend/vllm-ascend`、内网 harbor（`10.19.28.45:8003`、`10.19.32.152:1780`、`10.19.93.215:5000`）、`aisbench/all-services` |
| 磁盘 | `/data` **14T**（已用 59%）；`/` 7.4T（已用 21%）；模型落 `/data/ai-stack-models/models`（含 Qwen2.5/Qwen3 系列等），数据集落 `/data/datasets` |
| 配套版本纪律 | CANN ↔ torch_npu ↔ PyTorch ↔ 驱动（HDK）严格配套，**不可混装**（见 [技能目录 §维护](04-skill-catalog-and-maintenance.md)） |

首次上机按序执行（探针脚本示例；`msprof` 等工具不在默认 PATH，先 source 环境）：

```bash
# 登录评测机（SSH 端口 22022，密钥 910b_ed25519）
ssh -i ~/.ssh/910b_ed25519 -o IdentitiesOnly=yes -p 22022 root@10.19.93.115

# 0) 加载 CANN 工具链（msprof / atc / hccl_test 等不在默认 PATH）
source /usr/local/Ascend/ascend-toolkit/set_env.sh

# 1) 8 卡健康与拓扑
npu-smi info
npu-smi topo

# 2) msprof 最小探针（确认硬件计数器可读，防假活环境；在已装 torch_npu 的容器内执行）
msprof op --output=/tmp/probe --application="python3 -c 'import torch, torch_npu; torch.npu.init(); torch.empty(1, device=\"npu:0\")'"

# 3) 通信基线（hccl_test）
all_reduce_perf -b 8 -e 1G -f 2 -g 8

# 4) P_eff / BW_eff 校准（大 GEMM / 大 copy，msprof op 计时）
msprof op --output=/tmp/gemm_calib --application="python3 calib_gemm.py"
msprof op --output=/tmp/copy_calib --application="python3 calib_copy.py"
```

校准结果落 `cases/<模型>@<硬件>/calibration.md`（α / β / 锁频命令 / CANN↔torch_npu↔PyTorch↔驱动配套版本）。

---

## 3. 引擎扩展挂载点索引（昇腾版）

> **路径一律为本工程 `repos/` 相对路径**；使用前先 `bash scripts/manage_repos.sh clone <name>`（manifest 见 `repos/manifest.yaml`）才有本地源码。**只读参考**一律放 `repos/refs/<repo>/`，严禁修改。改引擎必须走 `repos/targets/<engine>/` 并用 `bash scripts/manage_repos.sh export-patch <engine> <case_name>` 导出补丁。

### 3.1 vllm-ascend / vLLM（`repos/targets/vllm-ascend/`、`repos/targets/vllm/`）

| 挂载点 | 位置（昇腾侧） | 用途 |
| :--- | :--- | :--- |
| `register_model` | vLLM `vllm/model_executor/models/registry.py`（`@ModelRegistry.register_model("Arch", "path.to.Model")`） | 挂载非标模型结构（阶梯 3/4） |
| `register_backend` / `AttentionBackend` | vLLM `vllm/v1/attention/backends/registry.py`（`@register_backend(AttentionBackendEnum.CUSTOM, "ASCEND")`，实现为 `AscendAttentionBackendImpl`） | 按平台/头维/KV dtype 分派 FIA（AscendAttentionBackend / `npu_fused_infer_attention_score`）等昇腾后端 |
| `register_quantization_config` | vLLM `vllm/model_executor/layers/quantization/__init__.py`（继承 `QuantizationConfig`） | 权重加载期转置/重排与低比特路径（ATB 量化解码 / msmodelslim 导出权重） |
| entry_points 插件 | vllm-ascend 的 pyproject entry points + 扩展包加载 | 昇腾专属算子与 hook 以插件形态隔离集成（阶梯 3） |
| torch_npu 融合算子替换 | `repos/targets/vllm-ascend/`（ops/ 目录：FIA / MLA absorb / MoE GMM / RoPE / KV write） | 识别并替换 torch_npu 融合算子（诊断 SOP 瓶颈 1 的「融合度验证」落点） |

### 3.2 MindIE-LLM / MindIE-Motor / MindIE-Turbo（`repos/targets/MindIE-LLM/`、`repos/targets/MindIE-Motor/`）

> ⚠️ **MindIE-Turbo 无独立 clone**（manifest 无该仓），作为面向第三方引擎（vLLM / SGLang）的通用 NPU 加速层引用，**勿**寻找 `repos/targets/MindIE-Turbo/`。

| 引擎 | 挂载点 | 用途 |
| :--- | :--- | :--- |
| **MindIE-LLM** | ATB / ACLNN 算子层（`atb::*`、`aclnn*` 单算子接口） | 昇腾原生 LLM 引擎；建模层算子替换 / 低比特路径（阶梯 2/4） |
| **MindIE-Motor** | PD 分离与集群服务化（deploy/diagnosis/validation 技能族） | 对标 Dynamo/vLLM-router 的编排层：Prefill/Decode 分离、请求分派、KV 拉取（阶梯 3 / J4 前置选项） |
| **MindIE-Turbo** | 面向第三方引擎（vLLM / SGLang）的通用 NPU 加速组件 | 不换引擎时引入的通用加速层（J4 前置「换宿主」的轻量替代） |

### 3.3 xLLM（`repos/targets/xllm/`）

| 挂载点 | 位置 | 用途 |
| :--- | :--- | :--- |
| **TileLang-Ascend 集成** | xLLM 推理栈内嵌 TileLang backend（配合 `repos/targets/tilelang-ascend/`，分支 `ascendc_pto`） | Triton→TileLang 语义映射、kernel 级移植与编译器 Pass 直达（阶梯 4/5）；`tilelang-perf-optimization` 技能强制 `msprof op` 度量 |

### 3.4 SGLang-Ascend（`repos/targets/sglang/`）

| 挂载点 | 位置 | 用途 |
| :--- | :--- | :--- |
| **LMCache 存储后端** | `python/sglang/srt/mem_cache/storage/lmcache/` | 昇腾侧 KV 远端缓存接入（LMCache 适配层，前缀复用 / KV offload） |
| **PD 解耦 hook** | `python/sglang/srt/arg_groups/pd_disaggregation_hook.py` | Prefill/Decode 解耦的调度与 KV 传输 hook（J4 前置「PD 分离」落点） |

### 3.5 只读参考（`repos/refs/<repo>/`）

| 参考仓 | 用途 |
| :--- | :--- |
| `repos/refs/cann-recipes-infer/` | CANN 官方大模型推理优化典型样例（融合/量化/KV 套路参考） |
| `repos/refs/msmodelslim/` | 昇腾量化与模型压缩工具链源码（`evaluate`/`tuning` 门禁、EP 并行） |
| `repos/refs/catlass/` | Cube/Vector 矩阵乘模板库（阶梯 4 移植参考） |
| `repos/refs/pto-kernels/` | **A2A3（910B）/ A5（950）双代**算子参考实现（双代差异直接对照） |
| `repos/refs/Mooncake/` | KV 跨机传输与 PD 解耦参考底座 |

> **阶梯 2/4/5 必须改引擎时**：改 `repos/targets/<engine>/`（如 `repos/targets/vllm-ascend/`、`repos/targets/vllm/`、`repos/targets/sglang/`、`repos/targets/MindIE-LLM/`、`repos/targets/MindIE-Motor/`、`repos/targets/xllm/`、`repos/targets/tilelang-ascend/`）；若引擎已是克隆仓，直接在仓内修改并 `export-patch`。

---

## 4. 引擎能力速查（选型用）

| 引擎 | 生态位 | 昇腾适配现状 | 主要挂载手段 | 技能支撑 |
| :--- | :--- | :--- | :--- | :--- |
| **vllm-ascend** | vLLM 昇腾官方硬件插件宿主 | 官方维护，主力引擎 | 注册表（model/attention/quant）+ entry_points 插件 + torch_npu 融合算子 | `vllm-ascend-model-adapter` / `vllm-ascend-deploy`（含 950DT 镜像 tag）/ `vllm-ascend-developer` |
| **MindIE-LLM / Motor / Turbo** | 昇腾原生引擎 + 编排 + 通用加速 | 华为官方；Motor 23 技能覆盖 PD 分离全生命周期 | ATB/ACLNN 算子、Motor 服务化、Turbo 加速层 | `MindIE-Motor` 技能族（deploy/diagnosis/validation） |
| **xLLM** | OpenAtom 高性能推理引擎（TileLang 深度集成） | xLLM 专用技能仓 22 个 | TileLang-Ascend kernel、xllm-npu-profiler 五表输出 | `tilelang-ascend-kernel` / `xllm-npu-profiler` |
| **SGLang-Ascend** | 高吞吐 + 前缀缓存标杆 | NPU 专项技能几乎空白（仅社区 3-skill 小仓） | LMCache 存储后端、PD 解耦 hook | 用 vllm-ascend 技能替代；方法论从 SGLang 主仓技能取 |

---

## 5. 950 落地建议

1. **以一个 910B 技能为主体**（推荐 cannbot `model-infer-*` 家族），配合 **MXFP8 档位经验**（`dit-perf-opt`，仅 A5/950 硬件支持）做精度前提。
2. **用 950DT 镜像 tag 起服务**（vllm-ascend-deploy 的 `*-950dt` tag 线索；TorchNPU 26.1.0 官方适配 950DT）。
3. **先做 950 算子级仿真验证**：NPU Simulator（cannsim）仅支持 950PR/950DT；`hccl_test` 支持 950 系 **32K rank**；msprof 支持 950 系系统数据采集（CCU/PCIe/SIO/UB 带宽、SoC 频率上限 10000）。
4. **950 专项技能需自建**：把 §1 的代际差异（**SIMT / HiF8 / UB Bank 重写 / L0C→UB、UB→L1、SSBuffer / CCU / msprof 指标差异**）写成 950 专属约束，注入 910B 技能与诊断 SOP 阈值重校准中（落 `docs/` 与本机校准台账）。
