# skills/ —— Agent Skills 规范平铺目录

本目录按 **Agent Skills 规范平铺**：每个技能一个顶层目录，形如
`<skill-name>/SKILL.md`（可选 `references/`、`scripts/`、`assets/`）。
**不得再建 `vendored/`、`external/` 等分类子目录**（P11a 已删除，历史见下）。

## 入库 vs 不入库

- **随仓库跟踪**（白名单见 `.gitignore`）：下方 5 个技能 + 本 README。
- **同步而来、不入库**：`scripts/sync_ascend_skills.sh` 拉取的第三方昇腾技能，
  **平铺**落到本目录（不再按域分子目录），被 `.gitignore` 忽略，每次同步重新生成。

## 入库技能清单（5 个）

| 技能 | 来源 | 为什么留 | 昇腾注意点 |
|---|---|---|---|
| `evalscope` | modelscope/evalscope | J6 双轨评测（可打 OpenAI 兼容端点） | 性能数值须换算为 msprof 设备侧口径 |
| `kl-consistency-test` | sgl-project/sglang | J6 轨道 A 的 prefill/decode 双路径 logprob KL 方法（通用） | 无 CUDA 依赖，直接可用 |
| `mooncake-api` | kvcache-ai/Mooncake | KV 传输 / PD 解耦 API（Mooncake 支持昇腾传输） | 传输层注意走昇腾后端 |
| `mooncake-troubleshoot` | 同上 | 部署排障（服务/RDMA/env/内存注册/日志） | RDMA 侧对应 HCCL/RoCE |
| `debug-distributed-hang` | sgl-project/sglang | 分布式卡死排查（py-spy / 二分定位 / rank 状态发散） | `cuda-gdb`/CUDA coredump/`NCCL_DEBUG` 需替换为 HCCL/`hccl_test`/`msprof` |

## 已删除的技能（不再使用）

- `triton-kernel-writing`（P11a 移除）—— 纯 `@triton.jit`，本工程不用 Triton。
- `kernel-microbenchmark`（P11a 移除）—— CUPTI/CUDA-only，直接跑会失败，且与 msprof 铁律冲突。
- P11c 去重后从同步 allowlist 删除 12 个（内容为留存技能的重复/子集，见下
  「重复对的优先选用表」）：`ascendc-operator-code-review`、`ascendc-operator-doc-writer`、
  `tilelang-ascend-kernel`、`xllm-npu-{accuracy,perf,eval}-runner`、`evaluation`、`installation`、
  `strategy`、`adaptation`、`docs-management`、`profiling-analyze`。

（原 `vendored/`、`external/` 两层目录与其 README 一并删除；上游原文逐字入库的
口径取消，筛选原则见下。）

## 同步方式

```bash
bash scripts/sync_ascend_skills.sh --list          # 离线看源清单与 allowlist（不访问网络）
bash scripts/sync_ascend_skills.sh --category all  # 全量同步
bash scripts/sync_ascend_skills.sh --only <origin> # 定向单源（如 --only vllm-ascend）
bash scripts/sync_ascend_skills.sh --dry-run       # 试跑不落盘
```

同步结果**平铺**到本目录、入 gitignore。当前源清单：**13 仓 / 21 条 allowlist**
（开发 10 / 运维 9 / 门禁 2；以 `--list` 实际输出为准，勿编造 commit）。

## 筛选原则

- 实现路线优先级：**AscendC > TileLang > PyPTO/CATLASS**。
- **Triton / Triton-Ascend 不在实现路线**——脚本对技能名含 `triton` 的**一律跳过**。
- 只收「昇腾开发（算子/模型接入/量化/图模式）」与「昇腾运维
  （性能诊断/通信/服务化/部署）」相关技能。

## 技能分层（T1 核心 / T2 支撑）—— Agent 路由表

按 **J0→J6 环节**给 Agent 的导航（该用哪些技能，具体到技能目录名）：

| 环节 | T1 核心技能（优先用） | T2 支撑（按需） |
|---|---|---|
| J0 定焦 / 性能定位 | `ascend-profiling-anomaly`、`ascend-msprof-analyze-cli`、`msot-msopprof-operator-profiler`、`ascend-schedule-analysis`、`ascend-computation-analysis`、`ascend-communication-analysis`、`memory-analysis`、`ascend-profiler-db-explorer`、`ops-profiling`、`op-mfu-profiler` | `ascend-profiler-data-validation`、`msagent-profiler-breakdown`、`mindstudio-cpu-binding`、`ascend-npu-snapshot-analyzer`、`ascend-profiler-collect-adaption` |
| J1/J1.5 模型接入 | `model-infer-migrator`、`model-infer-parallel-analysis`、`npu-adapter-reviewer`、`npu-api-adaptation-checker` | `model-infer-parallel-impl`、`atb-aclnn-operator-migration` |
| J2 账本 | `op-mfu-calculator`、`xllm-npu-capacity-planner`、`xllm-npu-compute-simulation` | — |
| J3 归因 | `ascend-schedule-analysis`、`ascend-computation-analysis`、`ascend-communication-analysis`、`hccl-test`、`ascend-cluster-fast-slow-rank-detector`、`ascend-prof-compare` | `ascend-cluster-compare`、`msagent-profiler-breakdown` |
| J4/J5 算子（**AscendC 优先**） | `ascendc-operator-dev`（端到端编排）、`ascendc-operator-design`、`ascendc-operator-code-gen`、`ascendc-operator-compile-debug`、`ascendc-operator-precision-eval`、`ascendc-precision-debug`、`ascendc-tiling-design`、`ascendc-api-best-practices`、`ascendc-operator-mssanitizer`、`mssanitizer-basic-usage`、`msdebug-basic-usage`、`ascendc-operator-A5-migration`、`ascendc-env-check`、`ascendc-direct-invoke-template`、`torch-ascendc-op-extension`、`aiss-tiling-solver` | `ascendc-code-review`、`ascendc-{blaze,regbase}-best-practice`、`ascendc-{crash,runtime}-debug`、`ascendc-docs-search`、`ascendc-operator-{performance-eval,project-init,testcase-gen,st-gen,doc-gen}`、`ops-precision-standard`、`ops-performance-tuning`、`catlass-operator-*`、`pypto-*` |
| J4/J5 算子（**TileLang**） | `tilelang-op-design`、`tilelang-op-develop`、`tilelang-op-test-design`、`tilelang-perf-optimization`、`tilelang-pass-{analyzer,design,generate,workflow-analyzer}`、`tilelang-ascend-tile-api`、`tilelang-pto-kernel-workflow`、`tilelang-a5-sim-convert`、`testing-pto-kernels` | `tilelang-custom-skill/*` |
| J4/J5 模型级优化 | `model-infer-fusion`、`model-infer-kvcache`、`model-infer-graph-mode`、`model-infer-multi-stream`、`model-infer-prefetch`、`model-infer-superkernel`、`model-infer-runtime-debug`、`model-infer-precision-debug` | `ascend-fusion-op-replace` |
| J4/J5 图模式 | `torch-npugraph-ex-knowledge`、`torch-npugraph-ex-template`、`torch-npugraph-ex-compile-error-diagnosis`、`torch-npugraph-ex-runtime-error-diagnosis`、`torch-npugraph-ex-dfx-triage`、`torch-custom-ops-guide` | — |
| J6 门禁 | `accuracy-gate`、`perf-gate`、`evalscope`、`kl-consistency-test`、`quantization-dev`、`quantization`、`tuning`、`sensitive-layer-analysis` | — |
| 通信 / 解耦 | `hccl-test`、`deepep-to-cam-converter`、`ascend-communication-analysis` | `ascend-moe-optimizer-trace-analyzer`、`ascend-moe-optimizer-auto-trace` |
| 服务化（MindIE-Motor） | `motor-deploy`、`motor-diagnosis`、`motor-validation` | `motor-{dev,reliability,scale,smoke-suite}` + 其 `motor-deploy-*`/`motor-diagnosis-*`/`motor-validation-*` 原子子技能 |
| 引擎接入 | `vllm-ascend-model-adapter`、`sglang-npu-adapter` | `vllm-ascend-release`、`xllm-npu-*`(14) |
| 主机 / 环境 | `npu-smi`、`ascend-docker`、`cann-operator-env-config`、`npu-arch`、`atc-model-converter` | — |

## 重复对的优先选用表

即使两份都在，也按下表先选：

| 职能 | 优先用 | 备用 / 说明 |
|---|---|---|
| 算子代码审查 | `ascendc-code-review` | `ascendc-operator-code-review` 已删（内容为前者子集） |
| 算子文档 | `ascendc-operator-doc-gen` | `ascendc-operator-doc-writer` 已删 |
| TileLang kernel 开发 | `tilelang-op-develop` | `tilelang-ascend-kernel` 已删（其唯一增量是 Triton→TileLang 映射，本工程不用 Triton） |
| 算子精度调试 | `ascendc-precision-debug`（前置纪律）+ `ascendc-operator-precision-debug`（误差分析→三层代码审查） | 两份是**两段**，按序使用 |
| sanitizer | `ascendc-operator-mssanitizer`（选检测模式） | `mssanitizer-basic-usage`（工具参数/产物位置） |
| 算子性能调优 | `ascendc-operator-performance-optim` | `ops-performance-tuning`（通用编排） |
| 融合算子替换 | `model-infer-fusion`（含参考实现匹配） | `ascend-fusion-op-replace`（全局替换规范） |
| profiling 采集 | `profiling-collect`（含三方框架补丁法/集合通信采集） | `ascend-profiler-collect-adaption` |
| profiling 分析 | `msagent-profiler-breakdown`（通用） | `profiling-analyze` 已删（DiT/VAE 扩散专用） |
| 评测执行 | vendored `evalscope` + `accuracy-gate`/`perf-gate` | `xllm-npu-*-runner` 已删（evalscope 薄封装） |
| MFU | `op-mfu-calculator`（手算）↔ `op-mfu-profiler`（msprof-analyze 实测） | 互补，估算 vs 实测 |
| Tiling 设计 | `ascendc-operator-design`（设计流程）↔ `ascendc-tiling-design`（多核/UB/Buffer 专项） | 互补 |

## 算子开发路线（强制）

- 优先级：**`AscendC` > `TileLang` > `PyPTO` / `CATLASS`**。
- **Triton / Triton-Ascend 不在本工程实现路线内**：同步脚本对技能名含 `triton` 的
  一律跳过；[docs/01 阶梯 4](../../docs/01-pipeline-and-ledger.md) 中现有的 Triton 内容
  仅供**了解/排错**，不作实现路线。
- 选型判据一句话：算法结构需要自定义 Tile/流水 → TileLang；需要 AscendC 指令级控制/
  极致性能 → AscendC；需要矩阵乘模板 → CATLASS；PyPTO 仅在既有工程已用 PyPTO 时。

## 相关链接

- [docs/04 技能目录与昇腾相关性](../../docs/04-skill-catalog-and-maintenance.md)
- [AGENTS.md §7 知识库与第三方技能路由](../../AGENTS.md)
