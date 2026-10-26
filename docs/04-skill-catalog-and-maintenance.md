# 04 · 技能全景、工具对照与维护计划

> **定位**：三层技能矩阵（自研知识 / vendored 7 / external 21）、第三方技能昇腾相关性评估、NVIDIA↔昇腾工具对照、维护计划与风险表。
> **配套**：[流水线与物理账本](01-pipeline-and-ledger.md) ｜ [诊断 SOP](02-ascend-diagnosis-sop.md) ｜ [硬件与引擎](03-ascend-hardware-and-engines.md) ｜ [AGENTS.md](../AGENTS.md)
> **同步入口**：`bash scripts/sync_ascend_skills.sh --category all`（或 `--category {operators,network,tooling,engines} [--only <name>]`，`--list` 离线查看）。

---

## 1. 三层技能矩阵总览

| 层 | 数量 | 目录 / 名称 | 来源 | 覆盖能力 |
| :--- | :--- | :--- | :--- | :--- |
| **自研知识** | 6 篇已并入 `docs/01~04`（主机环境说明在 `AGENTS.md.local`，不入库） | 算子开发与审查 → [01 阶梯 4 实操](01-pipeline-and-ledger.md)；量化与门禁 → [01 J6 实操](01-pipeline-and-ledger.md)；msprof 采集与归因 → [02 msprof 实操](02-ascend-diagnosis-sop.md)；HCCL 排障 → [02 HCCL 实操](02-ascend-diagnosis-sop.md)；CUDA→torch_npu 迁移与图模式 → [03 迁移与图模式](03-ascend-hardware-and-engines.md)；vllm-ascend 接入 → [03 接入与融合算子](03-ascend-hardware-and-engines.md) | 自建（本工程，已内化） | 原 7 篇自研技能：**6 篇**并入 `docs/01~04`，**1 篇**（主机环境）转为 `AGENTS.md.local`；保留全部可执行内容，执行口径一律以 `docs/` 为准 |
| **vendored** | 7 | `evalscope` | modelscope/evalscope | J6 双轨：精度评测（MMLU/GSM8K/ARC，可打 OpenAI 兼容端点）+ 性能压测（TTFT/TPOT/吞吐） |
| | | `mooncake-api` | kvcache-ai/Mooncake | Mooncake Store / Transfer Engine Python API（昇腾传输支持） |
| | | `mooncake-troubleshoot` | kvcache-ai/Mooncake | Mooncake 部署排障（服务/RDMA/env/注册内存/日志） |
| | | `kernel-microbenchmark` | vllm-project/vllm | 单算子微基准方法论（正确性先于计时、多后端、SOL sanity）；**纯中立**，最通用 |
| | | `triton-kernel-writing` | vllm-project/vllm | 写/审 `@triton.jit` kernel（mask/边界/tuning/代表性验证）；昇腾侧映射到 Triton-Ascend |
| | | `kl-consistency-test` | sgl-project/sglang | J6 轨道 A：同一 token 走 prefill/decode 双路径比 logprob KL，抓前缀损坏/状态陈旧 |
| | | `debug-distributed-hang` | sgl-project/sglang | 分布式卡死/挂起排查（集合通信死锁、rank 不齐、超时定位） |
| **external** | 21 | 见 §2 全景索引表 | GitCode/GitHub 源仓 | 4 大域：operators(7) / network(4) / tooling(5) / engines(5) |

> **vendored 上游来源**：`mooncake-api`、`mooncake-troubleshoot` 来自 `repos/refs/Mooncake/`（只读底座）；`evalscope` 上游为 `modelscope/evalscope`（**不在 `repos/manifest.yaml` 内**，直接本地入库）；`kernel-microbenchmark`、`triton-kernel-writing` 来自 `workspace/<scenario-id>/source/vllm/`；`kl-consistency-test`、`debug-distributed-hang` 来自 `workspace/<scenario-id>/source/sglang/`（vllm / sglang 需先 `bash scripts/manage_repos.sh clone <name>` 才有本地源码）。★本工程 `vendored/` 为**本地入库拷贝**，随根仓库跟踪，**不依赖运行时 clone**（上列来源仓仅说明出处）。自研知识已并入 `docs/01~04` 对应章节（主机环境事实见 `AGENTS.md.local`，不入库）。external 落点 `.agents/skills/external/<域>/<组名>/`（该目录内容被 `.gitignore` 忽略，仅保留 README.md 由脚本管理）。

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

> **权威指向**：源 url / branch 以 `bash scripts/sync_ascend_skills.sh --list` 为**唯一权威**，本表仅作索引；若不一致以脚本为准。

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
| CUDA / AscendCL | **CANN**（+ ACL 运行时） | 等价 | 主机环境核对见 `AGENTS.md.local`；[03 §主机环境核对](03-ascend-hardware-and-engines.md) |
| cuDNN | **ops-nn + aclnn 单算子接口** | 近似 | — |
| cuBLAS | **ops-blas / ops-blasLt** | 近似 | — |
| CUDA C | **AscendC** | 等价 | [01 阶梯 4 实操](01-pipeline-and-ledger.md)（写核/审查/UB 预算/mssanitizer） |
| CUTLASS | **CATLASS** | 近似（非移植：达芬奇 Cube/Vector 异构模型） | external `catlass` |
| Triton / cuTile | **Triton-Ascend / PyPTO / TileLang-Ascend** | 等价 | external `tilelang-ascend`、`xllm` |
| nvcc | **毕昇编译器（bisheng，AscendNPU IR）** | 近似 | — |
| NCCL / nccl-tests | **HCCL / hccl_test** | 等价 | [02 HCCL 实操](02-ascend-diagnosis-sop.md)（基线/快慢卡/RoCE/PD 分离） |
| NVSHMEM | **SHMEM**（对称内存 + RMA/AMO） | 近似 | — |
| CUPTI | **MSPTI**（Activity/Callback API + PM Sampling） | 等价 | — |
| NVTX | **MSTX**（`mstxMarkA` 打点） | 等价 | — |
| Compute Sanitizer | **mssanitizer**（memcheck/racecheck/initcheck/synccheck） | 等价 | external `ascend-agent-skills`（ascendc-operator-mssanitizer） |
| Nsight Systems | **msprof + MindStudio Insight + msprof-analyze** | 近似 | [02 msprof 实操](02-ascend-diagnosis-sop.md)（采集/五表/AICPU/GPU↔NPU 对比） |
| Nsight Compute | **msOpProf + MindStudio Insight**（指令流水/源码/Roofline） | 近似 | [02 msprof 实操](02-ascend-diagnosis-sop.md) |
| DCGM | **DCMI（对标 NVML）+ npu-exporter + msMonitor** | 近似 | 主机环境核对见 `AGENTS.md.local`；[03 §主机环境核对](03-ascend-hardware-and-engines.md) |
| TensorRT | **MindIE-RT + ATC（→ .om）** | 近似 | external `ascend-agent-skills` |
| TensorRT-LLM | **MindIE-LLM**（+ MindIE-Motor 服务化 / MindIE-Turbo 通用加速） | 近似 | external `mindie-llm`、`mindie-motor` |
| Triton Inference Server | **MindIE-Motor** 或直接适配（triton-inference-server-ge-backend） | 近似 | external `mindie-motor` |
| NIM | **MIS（昇腾推理微服务）** | 近似 | — |
| Dynamo | **MindIE-Motor（PD 分离+调度） + MindCluster（K8s） + LLM-DataDist（KV）** | 近似（缺 KV-aware Router） | external `mindie-motor` |
| NIXL | **LLM-DataDist / hixl / CANN KV 库** | 近似 | — |
| ModelOpt / llm-compressor | **msmodelslim** | 近似 | [01 J6 实操](01-pipeline-and-ledger.md)（量化与门禁） + external `msmodelslim` |
| Megatron-LM | **MindSpeed / ModelLink / MindSpeed-LLM** | 近似 | — |
| TransformerEngine | **TransformerEngineNPU / MindSpeed TE 模块** | 等价 | — |
| DALI / NVDEC | **MindData（数据管线）/ DVPP（硬件编解码）** | 近似 | — |
| lm-eval | **AISBench**（+ EvalScope 支持昇腾） | 近似 | external `evalscope` |
| —（CUDA Graph） | **GE / npugraph_ex / TorchAir** | 等价 | [03 CUDA→torch_npu 迁移与图模式修复](03-ascend-hardware-and-engines.md) |
| —（PyTorch CUDA 后端） | **torch_npu / op-plugin / TorchAir** | 近似 | [03 CUDA→torch_npu 迁移与图模式修复](03-ascend-hardware-and-engines.md) |

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
| **B. 环境硬绑定复测（最高风险）** | 量化/性能类技能（`quantization-dev`、`fla-ascend-performance`、tilelang-perf 等均明示「换 CANN/torch_npu/芯片必须复测」） | **每次升级 CANN / torch_npu / 芯片后重跑验证 SOP**；把「已核验到 CANN x.y + torch_npu a.b.c」记入 `workspace/_shared/calibration.md` 台账 | 每次环境升级 |
| **C. 版本配套表** | CANN ↔ torch_npu ↔ PyTorch ↔ 驱动（HDK） | **严格对应、不可混装**；用 `migration-ascend-torchnpu-skills-environment-setup` 的配套表；910B3 基准工具版本见 `AGENTS.md.local` | 每次建环境 |
| **D. 需自建并长期维护** | ① **950 代际约束**（SIMT / HiF8 / UB Bank 重写 / CCU / msprof 指标差异）；② **本机 msprof 基线**（P_eff / BW_eff 实测 + 锁频命令）；③ **docs/01~04 自研知识章节** | 950 约束与基线写入本工程 `docs/` + `workspace/<scenario-id>/ledger/`（不入库；规范见 [docs/05](05-case-library-and-ledger.md)）；自研知识章节随每次实验迭代 | 持续 |

---

## 5. 风险表

| 风险 | 涉及 | 缓解 |
| :--- | :--- | :--- |
| **GitHub 镜像是旧的** | `Ascend/agent-skills` GitHub 版 2026-05 后停更 | 以 **GitCode 为准**，或走 `awesome-ascend-skills` 的 external 镜像 |
| **领域错配** | `MindIE-SD` 是**扩散/多模态**仓（非 LLM）；`xllm` 绑 OpenAtom xLLM 引擎 | 只取其**方法论**（accuracy-gate / perf-gate / quantization-dev）；执行前确认领域 |
| **环境硬绑定** | 量化/性能类技能结论**不可跨版本移植** | 见维护计划 B 类；每次升级复测 |
| **中文为主 + 真机依赖** | 绝大多数技能中文、需 CANN + NPU 真机 | 训练/推理环境先按配套表装齐（主机事实与配套表见 `AGENTS.md.local`） |
| **大仓质量参差** | `model-agent` 301 技能含长尾（148 个 Tier3） | 只用其评分高的；优先 cannbot 系 |
| **单维护者项目** | `triton-agent`（Helix）、`vllm-ascend-developer` 等小仓 | 自留快照；核心逻辑可借鉴但勿强依赖 |
| **license 缺失** | `awesome-ascend-skills`、部分 Ascend 仓技能未声明 license | 仅内部参考；分发前核实 |
| **未实测** | 全部 external 技能 | 首次使用前按各技能自带的 env-check / 冒烟验证跑一遍（需真机 + msprof 权限） |

---

## 第三方技能昇腾相关性评估

> **取用原则**：第三方技能均为**上游原文**（`vendored/` 本地入库拷贝、`external/` 联网同步目录），可直接取用其**方法**，但**执行口径一律以本工程 msprof 铁律与 `docs/` 为准**——凡涉性能数据，只信 `msprof` / `msprof op`（[02 §测量铁律](02-ascend-diagnosis-sop.md)），阈值与门禁口径见 [01](01-pipeline-and-ledger.md) 与 [门禁规则](../gates/README.md)。`external/` 需先 `bash scripts/sync_ascend_skills.sh --category all` **联网同步**才有本地副本（内容不入库）。

### vendored（7，本地入库）

| 技能 / 组 | 昇腾相关性 | 关键注意与替换点 |
| :--- | :--- | :--- |
| `kernel-microbenchmark`（vllm 上游） | 仅 NVIDIA-CUDA 口径 | 主推 **CUPTI** 计时——昇腾侧改用 `msprof` / `msprof op`；**CUPTI 对位是 MSPTI 但本工程不使用其计时**；随附 `benchmarks/*.py` 为 CUDA 脚本，直接跑会失败。取其方法论（正确性先于计时、多后端、SOL sanity） |
| `triton-kernel-writing`（vllm 上游） | 半相关（方法论可迁移） | 调优旋钮 `num_warps` / `num_stages` **在昇腾不可用**（见 [01 阶梯 4 实操](01-pipeline-and-ledger.md)）；Triton 语义（类型提升/整除/广播/边界）与生成代码检视方法可迁移到 Triton-Ascend |
| `debug-distributed-hang`（sglang 上游） | 半相关（方法论可迁移） | `cuda-gdb` / CUDA coredump / `NCCL_DEBUG` 为 CUDA 侧手段（需替换）；**`py-spy` 为通用 Python 栈采样器，昇腾侧仍可用**（SGLang watchdog 即依赖 `py-spy dump`）；昇腾通信分析以 HCCL / `hccl_test` / `msprof` 为主（见 [02 HCCL 实操](02-ascend-diagnosis-sop.md)）；rank 状态发散与二分定位法通用 |
| `kl-consistency-test`（sglang 上游） | 半相关（方法论可迁移） | prefill/decode 双路径 logprob KL 方法通用（J6 轨道 A）；可直接用于 SGLang-Ascend / vllm-ascend 端点 |
| `evalscope`（modelscope） | 半相关（方法论可迁移） | 评测可打 OpenAI 兼容端点（vllm-ascend 直接可用）；性能压测数值口径须换算为 msprof 设备侧口径 |
| `mooncake-api`（kvcache-ai/Mooncake） | 昇腾相关 | Mooncake 支持昇腾传输（vllm-ascend 内置 Mooncake KV connector 参考落点）；Store / Transfer Engine API 语义通用 |
| `mooncake-troubleshoot`（kvcache-ai/Mooncake） | 昇腾相关 | 部署排障（服务/RDMA/env/内存注册/日志）通用；RDMA 侧在昇腾对应 HCCS/RoCE 环境，结合 [02 HCCL 实操](02-ascend-diagnosis-sop.md) |

### external（21，联网同步）

| 技能 / 组 | 昇腾相关性 | 关键注意与替换点 |
| :--- | :--- | :--- |
| `cannbot-skills`（operators） | 昇腾相关 | CANN 官方 model-infer-* 家族（kvcache/fusion/multi-stream/prefetch/superkernel/quantization 等）；`plugins-*` 正在迁移，入口会变；GitCode 权威、GitHub 镜像 2026-05 后停更 |
| `tilelang-ascend`（operators） | 昇腾相关 | tilelang kernel 编写 / perf-optimization（强制 `msprof op`，与本工程铁律一致）/ pass-generate（唯一直达编译器 Pass 层）；分支 `ascendc_pto` |
| `xllm`（operators） | 昇腾相关 | tilelang-ascend-kernel（Triton→TileLang 语义映射表）、xllm-npu-profiler（五表输出契约）；绑 OpenAtom xLLM 引擎 |
| `pto-kernels`（operators） | 昇腾相关 | A2A3（910B）/ A5（950）双代算子参考实现与测试；双代差异直接对照 |
| `catlass`（operators） | 昇腾相关 | Cube/Vector 矩阵乘模板（非 CUTLASS 移植）；阶梯 4 移植参考 |
| `ascend-agent-skills`（operators） | 昇腾相关 | triton/ascendc-operator-* 全集、hccl-test、ascend-profiling-anomaly、atb-aclnn-operator-migration（明确支持 910B/950） |
| `xllm-workflow`（operators） | 昇腾相关 | 22 个 Ascend 专用技能（perf-runner/benchmark/profiler/eval/accuracy/incident-triage 等）；绑 xLLM 引擎，用前确认领域 |
| `god`（network） | 昇腾相关 | deepep-to-cam-converter（DeepEP→CAM、NCCL→HCCL、CUDA→NPU）；迁移后必跑 `hccl_test` + `msprof` 验证重叠度 |
| `msagent`（network） | 昇腾相关 | cluster-fast-slow-rank-detector（快慢卡三分类）、性能分析子代理；GitCode 权威、GitHub 镜像同步前提见 §4 维护计划 A |
| `msagent-mirror`（network） | 昇腾相关 | ascend-prof-compare（唯一 GPU↔NPU 双 Prof 对比，`msprof-analyze compare`）；GitHub 镜像，联网同步前提 |
| `mindie-motor`（network） | 昇腾相关 | motor-deploy/diagnosis/validation-*（PD 分离服务全生命周期，对标 Dynamo/vLLM-router） |
| `msmodelslim`（tooling） | 昇腾相关 | evaluate / tuning 门禁（目标值+容差判定、禁止改评测口径、0 分自愈链）；量化结论硬绑定环境，换 CANN/torch_npu/芯片必须复测 |
| `mindie-sd`（tooling） | 昇腾相关 | **扩散/多模态仓（非 LLM）**，领域错配——只取 accuracy-gate（L1/L2/L3）/ perf-gate（探索态 vs 验收态）/ quantization-dev（MXFP8 档位）方法论；执行前确认领域 |
| `evalscope`（tooling） | 半相关（方法论可迁移） | 精度评测 + 性能压测 + RAG 评测（可打 vLLM-Ascend 端点）；与 vendored `evalscope` 同源，用其方法、按本工程 msprof 口径执行 |
| `model-agent`（tooling） | 昇腾相关 | 301+ 技能 / 11 类（Deployment/Optimization/Adaptation/Verification），带 9 维技能评测；大仓质量参差，只用评分高者，优先 cannbot 系 |
| `awesome-ascend-skills`（tooling） | 昇腾相关 | 聚合入口/索引：torch_npu 环境/迁移、profiling-analysis 三阈值、MindStudio 镜像；部分技能未声明 license，仅内部参考 |
| `vllm-ascend`（engines） | 昇腾相关 | 官方插件仓（model-adapter 双段门禁、deploy 含 950DT 镜像 tag）；挂载点见 [03 §3.1](03-ascend-hardware-and-engines.md) |
| `ascend-sglang-skills`（engines） | 昇腾相关 | SGLang-NPU 社区 3-skill 小仓（NPU 专项几乎空白），用 vllm-ascend 技能替代；方法论从 SGLang 主仓取 |
| `cann-recipes-infer`（engines） | 昇腾相关 | CANN 官方推理优化参考仓（模型级优化套路：融合/量化/KV）；只读参考 `repos/refs/cann-recipes-infer/` |
| `mindie-llm`（engines） | 昇腾相关 | MindIE-LLM 引擎技能（ATB/ACLNN 算子、部署与精度调试）；昇腾原生引擎 |
| `sglang`（engines） | 半相关（方法论可迁移） | SGLang 主仓，CUDA 口径为主；llm-torch-profiler-analysis / kl-consistency-test / debug-distributed-hang 方法源；昇腾侧用 SGLang-Ascend |

> 表末口径：第三方技能为**上游原文**，可直接取用其**方法**，但**执行口径一律以本工程 msprof 铁律与 `docs/` 为准**；未实测项首次使用前按各技能自带 env-check / 冒烟验证跑一遍（需真机 + msprof 权限）。
