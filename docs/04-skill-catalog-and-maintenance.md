# 04 · 技能全景、工具对照与维护计划

> **定位**：技能盘点（自研知识 / 本地白名单 5 / 同步技能 190 = 共 **195 个技能目录**）、来源仓昇腾相关性评估、算子技能选型、NVIDIA↔昇腾工具对照、维护计划与风险表。
> **配套**：[流水线与物理账本](01-pipeline-and-ledger.md) ｜ [诊断 SOP](02-ascend-diagnosis-sop.md) ｜ [硬件与引擎](03-ascend-hardware-and-engines.md) ｜ [AGENTS.md](../AGENTS.md)
> **同步入口**：`bash scripts/sync_ascend_skills.sh --category all`（或 `--category {dev,ops,gate} [--only <origin>]`；`--list` 离线查看权威源表：**13 仓 / 21 条 allowlist**）。

---

## 1. 技能盘点总览

| 层 | 数量 | 位置 | 入库 |
| :--- | :--- | :--- | :--- |
| **自研 / 个性化知识** | — | `docs/01~05`（方法论与实操章节） | 是 |
| **本地白名单技能** | 5 | `.agents/skills/{evalscope,kl-consistency-test,mooncake-api,mooncake-troubleshoot,debug-distributed-hang}/` | 是 |
| **同步技能（第三方原文）** | 190 | `.agents/skills/<skill-name>/`（**平铺**，无分类子目录） | **否**（`.gitignore` 白名单制） |
| **合计（技能目录）** | **195** | `.agents/skills/`（平铺） | **5 入库 + 190 同步** |

> **白名单 5 技能**：`evalscope`（modelscope/evalscope）、`kl-consistency-test` / `debug-distributed-hang`（sgl-project/sglang）、`mooncake-api` / `mooncake-troubleshoot`（kvcache-ai/Mooncake）——上游原文入库，随根仓库跟踪，不依赖运行时 clone。
> **同步技能**：由 `scripts/sync_ascend_skills.sh` 从 **13 仓 / 21 条 allowlist**（dev 10 / ops 9 / gate 2）发现并同步，**平铺**落到 `.agents/skills/<name>/`，不入库，每次同步重新生成；当前 **190 个**，按来源计数：`cannbot-ops 28` / `mindie-motor 23` / `tilelang 18` / `msagent-profiler 17` / `agent-skills-atb 16` / `xllm-ops 15` / `agent-skills-dev 15` / `cannbot-model 11` / `msagent-operator 8` / `cannbot-graph 6` / `agent-skills-host 6` / `mindie-sd-gate 5` / `agent-skills-catlass 4` / `sglang-npu 3` / `msmodelslim 3` / `god 3` / `fla 3` / `vllm-ascend 2` / `agent-skills-ops 2` / `xllm-tilelang 1` / `pto 1`（合计 190，以 `.agents/skills/.origins/` 实况为准）；分层为 **T1 核心 / T2 支撑** 两档（具体技能见 `.agents/skills/README.md` 路由表，此处不列数字）。
> **权威指向**：源 url / branch / include 以 `bash scripts/sync_ascend_skills.sh --list` 为**唯一权威**，本文各表仅作索引；不一致以脚本为准。

---

## 2. 来源仓昇腾相关性评估（技能家族 → 昇腾相关性）

> 按来源仓盘点 13 个同步源 + 本地白名单 5 技能；「昇腾相关性」一列即原「第三方技能昇腾相关性评估」的口径：第三方技能为**上游原文**，可直接取用其**方法**，但**执行口径一律以本工程 msprof 铁律与 `docs/` 为准**——凡涉性能数据只信 `msprof` / `msprof op`（[02 §测量铁律](02-ascend-diagnosis-sop.md)），阈值与门禁口径见 [01](01-pipeline-and-ledger.md) 与 [门禁规则](../gates/README.md)。

| 来源（仓 / branch） | 提供什么 | 昇腾相关性 | 关键注意 |
| :--- | :--- | :--- | :--- |
| **本地白名单 5 技能**（modelscope/evalscope、sgl-project/sglang、kvcache-ai/Mooncake） | `evalscope`（J6 双轨评测，可打 OpenAI 兼容端点）、`kl-consistency-test`（prefill/decode 双路径 logprob KL）、`mooncake-api` / `mooncake-troubleshoot`（KV 传输 API / 部署排障）、`debug-distributed-hang`（分布式卡死排查） | 半相关→昇腾相关（方法通用，可直接用于昇腾端点） | 性能数值须换算 **msprof 设备侧口径**；`cuda-gdb` / CUDA coredump / `NCCL_DEBUG` 需替换为 HCCL / `hccl_test` / `msprof`（`py-spy` 通用仍可用）；RDMA 侧对应 HCCS / RoCE |
| **Ascend/agent-skills**（master，GitCode 权威） | AscendC 算子开发 14 件套 + TileLang 迁移（agent-skills-dev 15）、ATB/ACLNN 迁移调试 16（agent-skills-atb）、CATLASS 模板 4（agent-skills-catlass）、主机/环境 6（agent-skills-host，含 `vllm-ascend-deploy`）、HCCL 基线 + profiling 异常 2（agent-skills-ops） | 昇腾相关（原生） | GitHub 镜像 2026-05 后停更，脚本直连 GitCode；AscendC 编排入口 `ascendc-operator-dev`；`hccl_test` 为通信基线口径（[02 HCCL 实操](02-ascend-diagnosis-sop.md)） |
| **tile-ai/tilelang-ascend**（ascendc_pto，官方 `tilelang` 源） | TileLang 全栈 **18**：`tilelang-op-*`（design / develop / test-design）、`tilelang-perf-optimization`、`tilelang-pass-*`（唯一直达编译器 Pass 层）、`tilelang-ascend-tile-api`、`tilelang-a5-sim-convert` + 8 个 `tilelang-custom-skill/*`（api-best-practices / debug-helper / env-check / error-fixer / github-operations / programming-model-guide / review / submodule-pull）；另有 `tilelang-op-developer`（cannbot-ops）、`tilelang-vector-ascend-ops-migration`（agent-skills-dev） | 昇腾相关 | `tilelang-perf-optimization` 强制 `msprof op`（与本工程铁律一致）；分支为 `ascendc_pto` 非 main；跨源同名**分流**：近似相同（体积差≤10% 且改动行≤5%）→ 去重保留官方 `tilelang` 版；实质不同 → 改名并存 `cannbot-ops--<name>`（见 [.agents/skills/README.md](../.agents/skills/README.md) §同名分流） |
| **huawei-csl/pto-kernels**（main） | `testing-pto-kernels`——A2A3（910B）/ A5（950）双代算子参考实现与测试 | 昇腾相关 | PyPTO 参考实现，双代差异直接对照；配合 `tilelang-pto-kernel-workflow` 使用 |
| **xLLM-AI/xllm-workflow**（main） | `xllm-npu-*` 15 件套（benchmark / profiler / incident-triage / capacity-planner / compute-simulation / pipeline-analysis / server-manager / sota-loop / code-review / build-gate / report-writer / accuracy-debug / xllm-ops-integration / batch-perf / experiment-lifecycle）+ `tilelang-pto-kernel-workflow` | 昇腾相关 | 绑 OpenAtom xLLM 引擎，用前确认领域；旧 3 个 `xllm-npu-{accuracy,perf,eval}-runner` 已删（T3），以现 15 件套为准 |
| **ascend-ai-coding/awesome-ascend-skills**（main，cannbot 镜像） | cannbot 镜像：`model-infer-*` 11（fusion / graph-mode / kvcache / migrator / multi-stream / parallel-analysis / parallel-impl / precision-debug / prefetch / runtime-debug / superkernel）、ops 25（AscendC 最佳实践 / PyPTO / npu-arch 等）、graph 6（npugraph_ex 图模式）；`ops-lab/tilelang/*` 已并入实际同步（`tilelang` 源 18 个的构成见上表行） | 昇腾相关 | **用 GitHub 镜像绕开 GitCode token**；镜像滞后风险——与 GitCode 权威源（cann/cannbot-skills）比对，`--only` 定向重同步；`plugins-*` 迁移中入口会变 |
| **fla-org/flash-linear-attention**（main） | `fla-ascend-performance`、`fla-optimization-loop`、`fla-correctness-coverage`（线性注意力昇腾性能闭环） | 昇腾相关 | 性能结论硬绑定 CANN / torch_npu 版本，换环境必须复测（维护计划 B 类） |
| **kali20gakki/msAgent**（master，GitCode `Ascend/msagent` 的 GitHub 镜像） | profiler 17（`ascend-prof-compare` / 快慢卡检测 / `ascend-msprof-analyze-cli` / npu-snapshot-analyzer 等）、operator 8（msdebug / mssanitizer / mstx / msot / ops 调优 5 + 整网精度 `compare-result-analyzer` / `deterministic-calculation-analysis` / `precision-debugger` 3） | 昇腾相关 | GitHub 镜像滞后风险（GitCode 权威）；个人维护仓，核心逻辑借鉴勿强依赖；`ascend-prof-compare` 为唯一 GPU↔NPU 双 Prof 对比 |
| **XiaoLuoLYG/GOD**（main） | `deepep-to-cam-converter`（DeepEP→CAM、NCCL→HCCL、CUDA→NPU）+ `ascend-moe-optimizer-{auto-trace,trace-analyzer}` | 昇腾相关 | **该仓 78 个技能里其余是社会仿真，勿全量同步**（allowlist 已收窄）；迁移后必跑 `hccl_test` + `msprof` 验证重叠度 |
| **Ascend/MindIE-Motor**（master） | `motor-*` 23（deploy / diagnosis / validation / reliability / scale / smoke 等），PD 分离服务全生命周期 | 昇腾相关 | 对标 Dynamo / vLLM-router；部署与诊断均需真机 + msprof 权限 |
| **vllm-project/vllm-ascend**（main） | `vllm-ascend-model-adapter`（双段门禁：dummy 快步 + 真权重强制）、`vllm-ascend-release`（含 950DT 镜像 tag） | 昇腾相关 | 官方插件仓，挂载点见 [03 §3.1](03-ascend-hardware-and-engines.md) |
| **LinyuanLi0046/Ascend-SGLang-Skills**（main） | `npu-api-adaptation-checker`、`sglang-npu-adapter`、`test-regression-pr-locator`（SGLang-NPU 适配检查 3） | 昇腾相关 | 社区小仓、NPU 专项几乎空白；方法论从 SGLang 主仓白名单技能（`kl-consistency-test` / `debug-distributed-hang`）取 |
| **Ascend/msmodelslim**（master，GitCode） | `quantization`、`tuning`、`sensitive-layer-analysis`（量化与 evaluate/tuning 门禁 3） | 昇腾相关 | 目标值 + 容差判定、禁止改评测口径、0 分自愈链；结论硬绑定环境，换 CANN / torch_npu / 芯片必须复测 |
| **Ascend/MindIE-SD**（dev） | `accuracy-gate`、`perf-gate`、`quantization-dev`、`profiling-collect`、`performance-optimization`（L1/L2/L3 与探索态/验收态 5） | 昇腾相关（方法论） | **扩散/多模态仓（非 LLM），领域错配**——只取门禁方法论，执行前确认领域 |

> **已删除 / 不再使用**（历史遗留，勿再引用）：原 vendored 2 个——`triton-kernel-writing`（纯 `@triton.jit`，本工程不用 Triton）、`kernel-microbenchmark`（CUPTI/CUDA-only，与 msprof 铁律冲突，方法论并入 [02 测量铁律](02-ascend-diagnosis-sop.md) 与本机基线）；T3 12 个——`ascendc-operator-code-review`、`ascendc-operator-doc-writer`、`tilelang-ascend-kernel`（xLLM 绑定过深、工程当前不做 xLLM TileLang 定制，用官方 `tilelang` 源 `tilelang-op-*` 全栈替代；**如需恢复须在源表新增 `xLLM-AI/xllm` 行**）、`xllm-npu-{accuracy,perf,eval}-runner` 3 个（如 `xllm-npu-perf-runner` → 现 `xllm-npu-batch-perf` / `xllm-npu-benchmark`）、`evaluation`、`installation`、`strategy`、`adaptation`、`docs-management`、`profiling-analyze`（旧 T3 版；现未同步，勿引用）。

---

## 3. 算子技能选型（强制）

优先级：**`AscendC` > `TileLang` > `PyPTO` / `CATLASS`**。

- **Triton / Triton-Ascend 不在本工程实现路线**：同步脚本对含 `triton` 的技能名一律 denylist 排除（见 `scripts/sync_ascend_skills.sh`）；[01 阶梯 4 实操](01-pipeline-and-ledger.md) 的 Triton 内容仅供了解 / 排错，不用于实现。

| 场景 | 选型 | 对应技能 |
| :--- | :--- | :--- |
| 自定义 Tile / 流水控制 | **TileLang** | `tilelang-op-{design,develop,test-design}` + `tilelang-perf-optimization` + `tilelang-pass-*`（唯一直达编译器 Pass 层） |
| 指令级控制 / 极致性能 | **AscendC** | `ascendc-operator-dev`（编排器）+ design / code-gen / compile-debug / precision-eval / mssanitizer |
| 矩阵乘模板 | **CATLASS** | `catlass-operator-*` |
| 既有工程用 PyPTO | **PyPTO** | `pypto-*` |

> 重复对的优先选用（同名 / 同家族技能来自多源时的取舍）：见 [`.agents/skills/README.md`](../.agents/skills/README.md) 筛选原则。

---

## 4. NVIDIA ↔ 昇腾工具对照表

### 4.1 官方工具链逐层对照（昇腾侧操作手段）

| NVIDIA | 昇腾对应 | 相似度 | 配套技能 |
| :--- | :--- | :--- | :--- |
| CUDA / AscendCL | **CANN**（+ ACL 运行时） | 等价 | 主机环境核对见场景台账 00-probe.md 机器档案段；[03 §主机环境核对](03-ascend-hardware-and-engines.md) |
| cuDNN | **ops-nn + aclnn 单算子接口** | 近似 | — |
| cuBLAS | **ops-blas / ops-blasLt** | 近似 | — |
| CUDA C | **AscendC** | 等价 | [01 阶梯 4 实操](01-pipeline-and-ledger.md)（写核/审查/UB 预算/mssanitizer） |
| CUTLASS | **CATLASS** | 近似（非移植：达芬奇 Cube/Vector 异构模型） | 同步技能 `catlass-operator-*` |
| Triton / cuTile | **Triton-Ascend / PyPTO / TileLang-Ascend** | 等价 | 同步技能 `tilelang-*`、`xllm-npu-*` |
| nvcc | **毕昇编译器（bisheng，AscendNPU IR）** | 近似 | — |
| NCCL / nccl-tests | **HCCL / hccl_test** | 等价 | [02 HCCL 实操](02-ascend-diagnosis-sop.md)（基线/快慢卡/RoCE/PD 分离） |
| NVSHMEM | **SHMEM**（对称内存 + RMA/AMO） | 近似 | — |
| CUPTI | **MSPTI**（Activity/Callback API + PM Sampling） | 等价 | — |
| NVTX | **MSTX**（`mstxMarkA` 打点） | 等价 | — |
| Compute Sanitizer | **mssanitizer**（memcheck/racecheck/initcheck/synccheck） | 等价 | 同步技能 `ascendc-operator-mssanitizer` |
| Nsight Systems | **msprof + MindStudio Insight + msprof-analyze** | 近似 | [02 msprof 实操](02-ascend-diagnosis-sop.md)（采集/五表/AICPU/GPU↔NPU 对比） |
| Nsight Compute | **msOpProf + MindStudio Insight**（指令流水/源码/Roofline） | 近似 | [02 msprof 实操](02-ascend-diagnosis-sop.md) |
| DCGM | **DCMI（对标 NVML）+ npu-exporter + msMonitor** | 近似 | 主机环境核对见场景台账 00-probe.md 机器档案段；[03 §主机环境核对](03-ascend-hardware-and-engines.md) |
| TensorRT | **MindIE-RT + ATC（→ .om）** | 近似 | 同步技能 `atc-model-converter` / `cann-operator-env-config` |
| TensorRT-LLM | **MindIE-LLM**（+ MindIE-Motor 服务化 / MindIE-Turbo 通用加速） | 近似 | 同步技能 `motor-*`（MindIE-Motor） |
| Triton Inference Server | **MindIE-Motor** 或直接适配（triton-inference-server-ge-backend） | 近似 | 同步技能 `motor-*` |
| NIM | **MIS（昇腾推理微服务）** | 近似 | — |
| Dynamo | **MindIE-Motor（PD 分离+调度） + MindCluster（K8s） + LLM-DataDist（KV）** | 近似（缺 KV-aware Router） | 同步技能 `motor-*` |
| NIXL | **LLM-DataDist / hixl / CANN KV 库** | 近似 | — |
| ModelOpt / llm-compressor | **msmodelslim** | 近似 | [01 J6 实操](01-pipeline-and-ledger.md)（量化与门禁） + 同步技能 `quantization` / `tuning` |
| Megatron-LM | **MindSpeed / ModelLink / MindSpeed-LLM** | 近似 | — |
| TransformerEngine | **TransformerEngineNPU / MindSpeed TE 模块** | 等价 | — |
| DALI / NVDEC | **MindData（数据管线）/ DVPP（硬件编解码）** | 近似 | — |
| lm-eval | **AISBench**（+ EvalScope 支持昇腾） | 近似 | 白名单技能 `evalscope` |
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

## 5. 维护计划

| 类型 | 涉及 | 动作 | 频率 |
| :--- | :--- | :--- | :--- |
| **A. 权威源与镜像** | GitCode 权威：`Ascend/agent-skills`（master）、`Ascend/msmodelslim`；GitHub 镜像：cannbot（`awesome-ascend-skills`，绕开 GitCode token）、`msagent`（`kali20gakki/msAgent`） | 同步脚本直连权威源或镜像；**GitHub 镜像有滞后风险**（`Ascend/agent-skills` GitHub 版 2026-05 后停更；cannbot `plugins-*` 迁移中入口会变）；`bash scripts/sync_ascend_skills.sh --category all`（或 `--only <origin>`）按 **13 仓 / 21 条 allowlist** 重同步；**季度更新流程** = `--dry-run` → 同步 → `--prune` → `--update-lock`；上游变更可在 `git diff scripts/skills.lock` 审阅 | 季度 |
| **B. 环境硬绑定复测（最高风险）** | 量化/性能类技能（`quantization-dev`、`fla-ascend-performance`、tilelang-perf 等均明示「换 CANN/torch_npu/芯片必须复测」） | **每次升级 CANN / torch_npu / 芯片后重跑验证 SOP**；把「已核验到 CANN x.y + torch_npu a.b.c」记入 `workspace/_shared/calibration.md` 台账 | 每次环境升级 |
| **C. 版本配套表** | CANN ↔ torch_npu ↔ PyTorch ↔ 驱动（HDK） | **严格对应、不可混装**；以 CANN 官方安装文档配套表为准；910B3 基准工具版本见场景台账 00-probe.md 机器档案段 | 每次建环境 |
| **D. 需自建并长期维护** | ① **950 代际约束**（SIMT / HiF8 / UB Bank 重写 / CCU / msprof 指标差异）；② **本机 msprof 基线**（P_eff / BW_eff 实测 + 锁频命令）；③ **docs/01~05 自研知识章节** | 950 约束与基线写入本工程 `docs/` + `workspace/<scenario-id>/ledger/`（不入库；规范见 [docs/05](05-case-library-and-ledger.md)）；自研知识章节随每次实验迭代 | 持续 |

---

## 6. 风险表

| 风险 | 涉及 | 缓解 |
| :--- | :--- | :--- |
| **GitHub 镜像滞后** | cannbot（走 `awesome-ascend-skills` 镜像）、`msagent`（走 `kali20gakki/msAgent` 镜像）；`Ascend/agent-skills` GitHub 版 2026-05 后停更 | 同步脚本直连 **GitCode 权威源**（agent-skills / msmodelslim）；cannbot / msagent 用 `--only` 定向重同步并核对 commit |
| **领域错配** | `MindIE-SD` 是**扩散/多模态**仓（非 LLM）；`xllm-workflow` 绑 OpenAtom xLLM 引擎；`GOD` 仓其余为社会仿真 | 只取其**方法论**（accuracy-gate / perf-gate / quantization-dev）；执行前确认领域 |
| **环境硬绑定** | 量化/性能类技能结论**不可跨版本移植** | 见维护计划 B 类；每次升级复测 |
| **中文为主 + 真机依赖** | 绝大多数技能中文、需 CANN + NPU 真机 | 训练/推理环境先按配套表装齐（主机事实见场景台账 00-probe.md 机器档案段；配套表见维护计划 C 类） |
| **个人 / 镜像仓** | `XiaoLuoLYG/GOD`、`kali20gakki/msAgent`（个人 / 镜像维护，质量与更新无保障） | 只同步 allowlist 白名单项，**勿全量同步**；自留快照，核心逻辑可借鉴但勿强依赖 |
| **license 缺失** | `awesome-ascend-skills`、部分 Ascend 仓技能未声明 license | 仅内部参考；分发前核实 |
| **未实测** | 全部同步技能 | 首次使用前按各技能自带的 env-check / 冒烟验证跑一遍（需真机 + msprof 权限） |
