# 04 · 技能全景、工具对照与维护计划

> **定位**：三层技能矩阵（内化核心 7 / vendored 7 / external 21）、NVIDIA↔昇腾工具对照、维护计划与风险表。
> **配套**：[流水线与物理账本](01-pipeline-and-ledger.md) ｜ [诊断 SOP](02-ascend-diagnosis-sop.md) ｜ [硬件与引擎](03-ascend-hardware-and-engines.md) ｜ [AGENTS.md](../AGENTS.md)
> **同步入口**：`bash scripts/sync_ascend_skills.sh --category all`（或 `--category {operators,network,tooling,engines} [--only <name>]`，`--list` 离线查看）。

---

## 1. 三层技能矩阵总览

| 层 | 数量 | 目录 / 名称 | 来源 | 覆盖能力 |
| :--- | :--- | :--- | :--- | :--- |
| **内化核心** | 7 | `ascend-910b-server` | 自建（本工程） | 910B3 评测机运维、环境配套（CANN↔torch_npu↔PyTorch↔驱动）、8 卡健康与锁频、`npu-smi`/DCMI 采集 |
| | | `ascend-msprof-diagnosis` | 自建 | `msprof` / `msprof op` / msOpProf 采集与判读、timeline 气泡分析、950 指标差异适配 |
| | | `ascend-kernel-optim` | 自建 | AscendC / Triton-Ascend / TileLang-Ascend / CATLASS 写核、UB 容量与 Bank、融合度验证、五不准红线审查 |
| | | `ascend-network-hccl` | 自建 | HCCL / hccl_test / RoCE 拓扑与 PFC 探针 / 快慢卡三分类 / DeepEP→CAM / EPLB |
| | | `ascend-migration-and-graph` | 自建 | torch_npu 迁移、`npugraph_ex` / TorchAir / GE 图模式、图断裂修复、算子上下文 |
| | | `vllm-ascend-adapter` | 自建 | vllm-ascend / vLLM 挂载点（register_model / attention / quant / entry_points / 融合算子替换） |
| | | `ascend-quant-and-gate` | 自建 | msmodelslim 量化、MXFP/HiF8 档位、L1/L2/L3 精度门禁、探索态 vs 验收态 |
| **vendored** | 7 | `evalscope` | modelscope/evalscope | J6 双轨：精度评测（MMLU/GSM8K/ARC，可打 OpenAI 兼容端点）+ 性能压测（TTFT/TPOT/吞吐） |
| | | `mooncake-api` | kvcache-ai/Mooncake | Mooncake Store / Transfer Engine Python API（昇腾传输支持） |
| | | `mooncake-troubleshoot` | kvcache-ai/Mooncake | Mooncake 部署排障（服务/RDMA/env/注册内存/日志） |
| | | `kernel-microbenchmark` | vllm-project/vllm | 单算子微基准方法论（正确性先于计时、多后端、SOL sanity）；**纯中立**，最通用 |
| | | `triton-kernel-writing` | vllm-project/vllm | 写/审 `@triton.jit` kernel（mask/边界/tuning/代表性验证）；昇腾侧映射到 Triton-Ascend |
| | | `kl-consistency-test` | sgl-project/sglang | J6 轨道 A：同一 token 走 prefill/decode 双路径比 logprob KL，抓前缀损坏/状态陈旧 |
| | | `debug-distributed-hang` | sgl-project/sglang | 分布式卡死/挂起排查（集合通信死锁、rank 不齐、超时定位） |
| **external** | 21 | 见 §2 全景索引表 | GitCode/GitHub 源仓 | 4 大域：operators(7) / network(4) / tooling(5) / engines(5) |

> **vendored 上游来源**：`mooncake-api`、`mooncake-troubleshoot` 来自 `repos/refs/Mooncake/`（只读底座）；`evalscope` 上游为 `modelscope/evalscope`（**不在 `repos/manifest.yaml` 内**，直接本地入库）；`kernel-microbenchmark`、`triton-kernel-writing` 来自 `repos/targets/vllm/`；`kl-consistency-test`、`debug-distributed-hang` 来自 `repos/targets/sglang/`（vllm / sglang 需先 `bash scripts/manage_repos.sh clone <name>` 才有本地源码）。★本工程 `vendored/` 为**本地入库拷贝**，随根仓库跟踪，**不依赖运行时 clone**（上列来源仓仅说明出处）。internal 核心技能出处见 `AGENTS.md §7`。external 落点 `.agents/skills/external/<域>/<组名>/`（该目录内容被 `.gitignore` 忽略，仅保留 README.md 由脚本管理）。

---

## 2. 21 组 external 全景索引表

> **逐字照抄 `scripts/sync_ascend_skills.sh` 内置源数据表（4 列，共 21 行）**；`--category` 与域名一一对应。所有仓均先经 `sync_ascend_skills.sh` 浅克隆缓存（`.cache/skills/`）再自动发现 `SKILL.md` 落盘，落 `.agents/skills/external/<域>/<组名>/`。

```
operators | cannbot-skills          | https://gitcode.com/cann/cannbot-skills.git                     | master
operators | tilelang-ascend         | https://github.com/tile-ai/tilelang-ascend.git                  | ascendc_pto
operators | xllm                    | https://github.com/xLLM-AI/xllm.git                             | main
operators | pto-kernels             | https://github.com/huawei-csl/pto-kernels.git                   | main
operators | catlass                 | https://gitcode.com/cann/catlass.git                            | master
operators | ascend-agent-skills     | https://gitcode.com/Ascend/agent-skills.git                     | master
operators | xllm-workflow           | https://github.com/xLLM-AI/xllm-workflow.git                    | main
network   | god                     | https://github.com/XiaoLuoLYG/GOD.git                           | main
network   | msagent                 | https://gitcode.com/Ascend/msagent.git                          | master
network   | msagent-mirror          | https://github.com/kali20gakki/msAgent.git                      | master
network   | mindie-motor            | https://github.com/Ascend/MindIE-Motor.git                      | master
tooling   | msmodelslim             | https://gitcode.com/Ascend/msmodelslim.git                      | master
tooling   | mindie-sd               | https://github.com/Ascend/MindIE-SD.git                         | dev
tooling   | evalscope               | https://github.com/modelscope/evalscope.git                     | main
tooling   | model-agent             | https://gitcode.com/Ascend/model-agent.git                      | master
tooling   | awesome-ascend-skills   | https://github.com/ascend-ai-coding/awesome-ascend-skills.git   | main
engines   | vllm-ascend             | https://github.com/vllm-project/vllm-ascend.git                 | main
engines   | ascend-sglang-skills    | https://github.com/LinyuanLi0046/Ascend-SGLang-Skills.git       | main
engines   | cann-recipes-infer      | https://gitcode.com/cann/cann-recipes-infer.git                 | master
engines   | mindie-llm              | https://gitcode.com/Ascend/MindIE-LLM.git                       | master
engines   | sglang                  | https://github.com/sgl-project/sglang.git                       | main
```

**覆盖能力简表**：

| 域 | 组名 | 覆盖能力 |
| :--- | :--- | :--- |
| operators | cannbot-skills | model-infer-* 家族（kvcache/fusion/multi-stream/prefetch/superkernel/quantization/perf-breakdown/parallel）、tilelang-op-orchestrator、ascendc-operator-* |
| operators | tilelang-ascend | tilelang kernel 编写 / perf-optimization（强制 msprof op）/ pass-generate（唯一直达编译器 Pass 层 = 阶梯 5） |
| operators | xllm | tilelang-ascend-kernel（Triton→TileLang 语义映射表）、xllm-npu-profiler（五表输出契约） |
| operators | pto-kernels | A2A3（910B）/ A5（950）双代算子参考实现与测试（testing-pto-kernels） |
| operators | catlass | Cube/Vector 矩阵乘模板（catlass-operator-{dev,code-gen,design,performance-optim}） |
| operators | ascend-agent-skills | triton/ascendc-operator-* 全集、hccl-test、ascend-profiling-anomaly、atb-aclnn-operator-migration（明确支持 910B/950） |
| operators | xllm-workflow | 22 个 Ascend 专用技能（perf-runner/benchmark/profiler/eval/accuracy/incident-triage/capacity-planner/compute-simulation 等） |
| network | god | deepep-to-cam-converter（DeepEP→CAM、NCCL→HCCL、CUDA→NPU） |
| network | msagent | cluster-fast-slow-rank-detector（快慢卡三分类）、性能分析子代理 |
| network | msagent-mirror | ascend-prof-compare（唯一 GPU↔NPU 双 Prof 对比，msprof-analyze compare） |
| network | mindie-motor | motor-deploy/diagnosis/validation-*（PD 分离服务全生命周期，对标 Dynamo/vLLM-router） |
| tooling | msmodelslim | evaluate / tuning（量化精度门禁：目标值+容差判定、禁止改评测口径、0 分自愈链） |
| tooling | mindie-sd | 24 技能，**扩散/多模态仓（非 LLM）**；accuracy-gate（L1/L2/L3 门禁）/ perf-gate（探索态 vs 验收态）/ quantization-dev（MXFP8 档位）方法论可迁移 |
| tooling | evalscope | 精度评测 + 性能压测 + RAG 评测（可打 vLLM-Ascend 端点） |
| tooling | model-agent | 301+ 技能 / 11 类（Deployment/Optimization/Adaptation/Verification）；带 9 维技能评测系统 |
| tooling | awesome-ascend-skills | 聚合入口：torch_npu 环境/迁移、profiling-analysis 三阈值、MindStudio 镜像 |
| engines | vllm-ascend | vllm-ascend-model-adapter（双段门禁：dummy 快步 + 真权重强制）、vllm-ascend-deploy（含 950DT 镜像 tag） |
| engines | ascend-sglang-skills | SGLang-NPU 社区 3-skill 小仓（NPU 专项几乎空白，用 vllm-ascend 技能替代） |
| engines | cann-recipes-infer | CANN 官方推理优化参考仓（模型级优化套路） |
| engines | mindie-llm | MindIE-LLM 引擎技能（ATB/ACLNN 算子、部署与精度调试） |
| engines | sglang | SGLang 主仓技能（llm-torch-profiler-analysis / kl-consistency-test / debug-distributed-hang 方法源） |

**同步方式**：`bash scripts/sync_ascend_skills.sh --category all` —— 对每个条目浅克隆源仓到 `.cache/skills/<name>`，仓内 `find SKILL.md` 自动发现技能目录（各仓异构：skills/、.agents/skills/、.claude/skills/、plugins-*/），保留仓内相对路径结构落 `.agents/skills/external/<域>/<组名>/`；**`external/` 内容被 `.gitignore` 忽略**（仅 README.md 入库）。`--category {operators,network,tooling,engines,all} [--only <name>]` 定向重同步；单仓失败不中断整体，末尾输出 `OK n / FAIL m`。

---

## 3. NVIDIA ↔ 昇腾工具对照表

### 3.1 官方工具链逐层对照（昇腾侧操作手段）

| NVIDIA | 昇腾对应 | 相似度 | 配套技能 |
| :--- | :--- | :--- | :--- |
| CUDA / AscendCL | **CANN**（+ ACL 运行时） | 等价 | 内化 `ascend-910b-server` |
| cuDNN | **ops-nn + aclnn 单算子接口** | 近似 | — |
| cuBLAS | **ops-blas / ops-blasLt** | 近似 | — |
| CUDA C | **AscendC** | 等价 | 内化 `ascend-kernel-optim` |
| CUTLASS | **CATLASS** | 近似（非移植：达芬奇 Cube/Vector 异构模型） | external `catlass` |
| Triton / cuTile | **Triton-Ascend / PyPTO / TileLang-Ascend** | 等价 | external `tilelang-ascend`、`xllm` |
| nvcc | **毕昇编译器（bisheng，AscendNPU IR）** | 近似 | — |
| NCCL / nccl-tests | **HCCL / hccl_test** | 等价 | 内化 `ascend-network-hccl` |
| NVSHMEM | **SHMEM**（对称内存 + RMA/AMO） | 近似 | — |
| CUPTI | **MSPTI**（Activity/Callback API + PM Sampling） | 等价 | — |
| NVTX | **MSTX**（`mstxMarkA` 打点） | 等价 | — |
| Compute Sanitizer | **mssanitizer**（memcheck/racecheck/initcheck/synccheck） | 等价 | external `ascend-agent-skills`（ascendc-operator-mssanitizer） |
| Nsight Systems | **msprof + MindStudio Insight + msprof-analyze** | 近似 | 内化 `ascend-msprof-diagnosis` |
| Nsight Compute | **msOpProf + MindStudio Insight**（指令流水/源码/Roofline） | 近似 | 内化 `ascend-msprof-diagnosis` |
| DCGM | **DCMI（对标 NVML）+ npu-exporter + msMonitor** | 近似 | 内化 `ascend-910b-server` |
| TensorRT | **MindIE-RT + ATC（→ .om）** | 近似 | external `ascend-agent-skills` |
| TensorRT-LLM | **MindIE-LLM**（+ MindIE-Motor 服务化 / MindIE-Turbo 通用加速） | 近似 | external `mindie-llm`、`mindie-motor` |
| Triton Inference Server | **MindIE-Motor** 或直接适配（triton-inference-server-ge-backend） | 近似 | external `mindie-motor` |
| NIM | **MIS（昇腾推理微服务）** | 近似 | — |
| Dynamo | **MindIE-Motor（PD 分离+调度） + MindCluster（K8s） + LLM-DataDist（KV）** | 近似（缺 KV-aware Router） | external `mindie-motor` |
| NIXL | **LLM-DataDist / hixl / CANN KV 库** | 近似 | — |
| ModelOpt / llm-compressor | **msmodelslim** | 近似 | 内化 `ascend-quant-and-gate` + external `msmodelslim` |
| Megatron-LM | **MindSpeed / ModelLink / MindSpeed-LLM** | 近似 | — |
| TransformerEngine | **TransformerEngineNPU / MindSpeed TE 模块** | 等价 | — |
| DALI / NVDEC | **MindData（数据管线）/ DVPP（硬件编解码）** | 近似 | — |
| lm-eval | **AISBench**（+ EvalScope 支持昇腾） | 近似 | external `evalscope` |
| —（CUDA Graph） | **GE / npugraph_ex / TorchAir** | 等价 | 内化 `ascend-migration-and-graph` |
| —（PyTorch CUDA 后端） | **torch_npu / op-plugin / TorchAir** | 近似 | 内化 `ascend-migration-and-graph` |

**反向项（昇腾有、NVIDIA 无官方对应）**：

| 工具 | 说明 |
| :--- | :--- |
| **msprobe** | dump→精度比对→可视化的跨平台精度调试工具链（NVIDIA 无官方对位） |
| **msprof-analyze calibrate_npu_gpu** | 自动比对 nsys SQLite 与 NPU profile 出 Excel 报告（NVIDIA 无跨厂商性能比对） |
| **TorchAir / GE** | 独立图引擎组件 |
| **MindIE-Turbo** | 面向第三方引擎（vLLM/SGLang）的通用 NPU 加速组件 |

---

## 4. 维护计划

| 类型 | 涉及 | 动作 | 频率 |
| :--- | :--- | :--- | :--- |
| **A. GitCode 权威源与镜像** | `cannbot-skills` / `model-agent` / `msmodelslim` / `msagent` | GitCode 权威、GitHub 是镜像（`Ascend/agent-skills` GitHub 版 2026-05 后停更）；取用走 `awesome-ascend-skills` 的 external 镜像（有 CI 同步）；**cannbot `plugins-*` 正在迁移，入口会变**。`sync_ascend_skills.sh --category all` 重同步 | 季度 |
| **B. 环境硬绑定复测（最高风险）** | 量化/性能类技能（`quantization-dev`、`fla-ascend-performance`、tilelang-perf 等均明示「换 CANN/torch_npu/芯片必须复测」） | **每次升级 CANN / torch_npu / 芯片后重跑验证 SOP**；把「已核验到 CANN x.y + torch_npu a.b.c」记入 `cases/<模型>@<硬件>/calibration.md` 台账 | 每次环境升级 |
| **C. 版本配套表** | CANN ↔ torch_npu ↔ PyTorch ↔ 驱动（HDK） | **严格对应、不可混装**；用 `migration-ascend-torchnpu-skills-environment-setup` 的配套表；910B3 基准：`npu-smi 25.5.1` | 每次建环境 |
| **D. 需自建并长期维护** | ① **950 代际约束**（SIMT / HiF8 / UB Bank 重写 / CCU / msprof 指标差异）；② **本机 msprof 基线**（P_eff / BW_eff 实测 + 锁频命令）；③ 内化核心 7 技能本体 | 950 约束与基线写入本工程 `docs/` + `cases/` 台账；内化核心随每次实验迭代 | 持续 |

---

## 5. 风险表

| 风险 | 涉及 | 缓解 |
| :--- | :--- | :--- |
| **GitHub 镜像是旧的** | `Ascend/agent-skills` GitHub 版 2026-05 后停更 | 以 **GitCode 为准**，或走 `awesome-ascend-skills` 的 external 镜像 |
| **领域错配** | `MindIE-SD` 是**扩散/多模态**仓（非 LLM）；`xllm` 绑 OpenAtom xLLM 引擎 | 只取其**方法论**（accuracy-gate / perf-gate / quantization-dev）；执行前确认领域 |
| **环境硬绑定** | 量化/性能类技能结论**不可跨版本移植** | 见维护计划 B 类；每次升级复测 |
| **中文为主 + 真机依赖** | 绝大多数技能中文、需 CANN + NPU 真机 | 训练/推理环境先按配套表装齐（`10.19.93.115:22022`） |
| **大仓质量参差** | `model-agent` 301 技能含长尾（148 个 Tier3） | 只用其评分高的；优先 cannbot 系 |
| **单维护者项目** | `triton-agent`（Helix）、`vllm-ascend-developer` 等小仓 | 自留快照；核心逻辑可借鉴但勿强依赖 |
| **license 缺失** | `awesome-ascend-skills`、部分 Ascend 仓技能未声明 license | 仅内部参考；分发前核实 |
| **未实测** | 全部 external 技能 | 首次使用前按各技能自带的 env-check / 冒烟验证跑一遍（需真机 + msprof 权限） |
