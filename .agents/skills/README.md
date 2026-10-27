# skills/ —— Agent Skills 规范平铺目录

本目录按 **Agent Skills 规范平铺**：每个技能一个顶层目录，形如
`<skill-name>/SKILL.md`（可选 `references/`、`scripts/`、`assets/`）。
**不得再建 `vendored/`、`external/` 等分类子目录**（P11a 已删除，历史见下）。

## 技能纳管与同步机制

- **全量随仓库入库**：共 **195 个技能目录** 已全部纳入 Git 版本控制跟踪，开箱即用（克隆本仓库即可直接使用全量技能，无需先执行网络同步）。
- **同步与日常更新**：可使用 `scripts/sync_ascend_skills.sh` 脚本从上游生态仓持续拉取最新版本或清理废弃技能，来源标记 `.origins/` 默认不入库。

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

## 日常更新流程

```bash
bash scripts/sync_ascend_skills.sh --dry-run        # 预演：新增/刷新/改名 + prune 候选
bash scripts/sync_ascend_skills.sh                  # 更新（新装 / 刷新 / 同名分流）
bash scripts/sync_ascend_skills.sh --prune          # 清理已失效的旧技能目录
bash scripts/sync_ascend_skills.sh --update-lock    # 记录本次上游 commit → scripts/skills.lock
bash scripts/sync_ascend_skills.sh --verify         # 自检（CI 可用；漂移 exit 1）
```

- `--prune` 仅与 `--category all` 一起用（与 `--only` 互斥报错）。
- `scripts/skills.lock` **入库**，升级时可 `git diff scripts/skills.lock` 审阅上游变更。

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
| J2 账本 | `op-mfu-calculator` | `xllm-npu-capacity-planner`、`xllm-npu-compute-simulation`（依赖仓级资产，须在源码目录内运行，见「已知边界」） |
| J3 归因 | `ascend-schedule-analysis`、`ascend-computation-analysis`、`ascend-communication-analysis`、`hccl-test`、`ascend-cluster-fast-slow-rank-detector`、`ascend-prof-compare` | `ascend-cluster-compare`、`msagent-profiler-breakdown` |
| J4/J5 算子（**AscendC 优先**） | `ascendc-operator-dev`（端到端编排）、`ascendc-operator-design`、`ascendc-operator-code-gen`、`ascendc-operator-compile-debug`、`ascendc-operator-precision-eval`、`ascendc-precision-debug`、`ascendc-tiling-design`、`ascendc-api-best-practices`、`ascendc-operator-mssanitizer`、`mssanitizer-basic-usage`、`msdebug-basic-usage`、`ascendc-operator-A5-migration`、`ascendc-env-check`、`ascendc-direct-invoke-template`、`torch-ascendc-op-extension`、`aiss-tiling-solver` | `ascendc-code-review`、`ascendc-{blaze,regbase}-best-practice`、`ascendc-{crash,runtime}-debug`、`ascendc-docs-search`、`ascendc-operator-{performance-eval,project-init,testcase-gen,st-gen,doc-gen}`、`ops-precision-standard`、`ops-performance-tuning`、`catlass-operator-*`、`pypto-*` |
| J4/J5 算子（**TileLang**） | `tilelang-op-design`、`tilelang-op-develop`、`tilelang-op-test-design`、`tilelang-perf-optimization`、`tilelang-pass-{analyzer,design,generate,workflow-analyzer}`、`tilelang-ascend-tile-api`、`tilelang-pto-kernel-workflow`、`tilelang-a5-sim-convert`、`testing-pto-kernels`、`tilelang-op-developer` | `tilelang-api-best-practices`、`tilelang-programming-model-guide`、`tilelang-env-check`、`tilelang-error-fixer`、`tilelang-debug-helper`、`tilelang-review`、`tilelang-github-operations`、`tilelang-submodule-pull`（`tilelang-*` 同名以官方 `tilelang` 仓为准） |
| J4/J5 模型级优化 | `model-infer-fusion`、`model-infer-kvcache`、`model-infer-graph-mode`、`model-infer-multi-stream`、`model-infer-prefetch`、`model-infer-superkernel`、`model-infer-runtime-debug`、`model-infer-precision-debug`、`tilelang-vector-ascend-ops-migration` | `ascend-fusion-op-replace` |
| J4/J5 图模式 | `torch-npugraph-ex-knowledge`、`torch-npugraph-ex-template`、`torch-npugraph-ex-compile-error-diagnosis`、`torch-npugraph-ex-runtime-error-diagnosis`、`torch-npugraph-ex-dfx-triage`、`torch-custom-ops-guide` | — |
| J6 门禁 | `accuracy-gate`、`perf-gate`、`evalscope`、`kl-consistency-test`、`quantization-dev`、`quantization`、`tuning`、`sensitive-layer-analysis`、`compare-result-analyzer`、`deterministic-calculation-analysis`、`precision-debugger`（整网精度 / 确定性 / 精度调试） | — |
| 通信 / 解耦 | `hccl-test`、`deepep-to-cam-converter`、`ascend-communication-analysis` | `ascend-moe-optimizer-trace-analyzer`、`ascend-moe-optimizer-auto-trace` |
| 服务化（MindIE-Motor） | `motor-deploy`、`motor-diagnosis`、`motor-validation` | `motor-{dev,reliability,scale,smoke-suite}` + 其 `motor-deploy-*`/`motor-diagnosis-*`/`motor-validation-*` 原子子技能 |
| 引擎接入 | `vllm-ascend-model-adapter`、`vllm-ascend-deploy`、`sglang-npu-adapter` | `vllm-ascend-release`、`xllm-npu-*`(15) |
| 主机 / 环境 | `npu-smi`、`ascend-docker`、`cann-operator-env-config`、`npu-arch`、`atc-model-converter` | — |

## 重复对的优先选用表

即使两份都在，也按下表先选：

| 职能 | 优先用 | 备用 / 说明 |
|---|---|---|
| 算子代码审查 | `ascendc-code-review` | `ascendc-operator-code-review` 已删（内容为前者子集） |
| 算子文档 | `ascendc-operator-doc-gen` | `ascendc-operator-doc-writer` 已删 |
| TileLang kernel 开发 | `tilelang-op-develop` | `tilelang-ascend-kernel` 已删（xLLM 绑定过深、工程当前不做 xLLM TileLang 定制；如需恢复须在源表新增 `xLLM-AI/xllm` 行） |
| 算子精度调试 | `ascendc-precision-debug`（前置纪律）+ `ascendc-operator-precision-debug`（误差分析→三层代码审查） | 两份是**两段**，按序使用 |
| sanitizer | `ascendc-operator-mssanitizer`（选检测模式） | `mssanitizer-basic-usage`（工具参数/产物位置） |
| 算子性能调优 | `ascendc-operator-performance-optim` | `ops-performance-tuning`（通用编排） |
| 融合算子替换 | `model-infer-fusion`（含参考实现匹配） | `ascend-fusion-op-replace`（全局替换规范） |
| profiling 采集 | `profiling-collect`（含三方框架补丁法/集合通信采集） | `ascend-profiler-collect-adaption` |
| profiling 分析 | `msagent-profiler-breakdown`（通用） | `profiling-analyze` 已删（DiT/VAE 扩散专用） |
| 评测执行 | vendored `evalscope` + `accuracy-gate`/`perf-gate` | `xllm-npu-*-runner` 已删（与 `evalscope` + `accuracy-gate`/`perf-gate` 方法重叠，且强绑 xLLM 运行栈；本工程不做 xLLM 定制） |
| MFU | `op-mfu-calculator`（手算）↔ `op-mfu-profiler`（msprof-analyze 实测） | 互补，估算 vs 实测 |
| Tiling 设计 | `ascendc-operator-design`（设计流程）↔ `ascendc-tiling-design`（多核/UB/Buffer 专项） | 互补 |

## 同名分流（<origin>--<name>）

跨源同名技能（如 cannbot 镜像版 vs 官方 `tilelang` 仓版）按实况分流，**仍是单层目录**：

- **近似相同**（体积差 ≤10% 且改动行 ≤5%）→ **去重**，保留权威源（先到先得）。实例：`tilelang-review`（cannbot 版与官方版体积差 1.1%、改动行占比 2.8%）→ 只留官方 `tilelang` 版。
- **实质不同** → **改名并存** `<origin>--<name>`（frontmatter `name` 同步改写，仍是单层目录）。
- **判定边界**：近似判定**只比较 `SKILL.md`**（体积差 ≤10% 且改动行 ≤5%）；`references/`、`scripts/`、`templates/` 的差异**不计入**——因此近似相同被去重时，异源版本的非正文附件会一并丢弃。

当前改名并存 3 个（都是 cannbot 镜像版与官方 `tilelang` 仓版本**实质不同**时并存的结果；优先用官方版）：

- `cannbot-ops--tilelang-api-best-practices`
- `cannbot-ops--tilelang-op-design`
- `cannbot-ops--tilelang-programming-model-guide`

对应原名目录（`tilelang-api-best-practices` / `tilelang-op-design` / `tilelang-review` / `tilelang-programming-model-guide`）保留官方 `tilelang` 仓版本。

**不得用多级目录做命名空间**：Agent Skills 要求 `name` == 目录名且唯一，改名仅在单层平铺内以 `<origin>--<name>` 表达。

## 算子开发路线（强制）

- 优先级：**`AscendC` > `TileLang` > `PyPTO` / `CATLASS`**。
- **Triton / Triton-Ascend 不在本工程实现路线内**：同步脚本对技能名含 `triton` 的
  一律跳过；[docs/01 阶梯 4](../../docs/01-pipeline-and-ledger.md) 中现有的 Triton 内容
  仅供**了解/排错**，不作实现路线。
- 选型判据一句话：算法结构需要自定义 Tile/流水 → TileLang；需要 AscendC 指令级控制/
  极致性能 → AscendC；需要矩阵乘模板 → CATLASS；PyPTO 仅在既有工程已用 PyPTO 时。

## 已知边界

- **跨目录共享资产（`reference/`、`scripts/`、`rules/`）不随技能平铺**：`xllm-ops` 共 15 个
  （14 个 `xllm-npu-*` + `xllm-experiment-lifecycle`）、多数 `atb-*` 技能引用仓级资产
  （如 `../../reference/io_specs/*`、`../../scripts/*.py`、`../../rules/*`），平铺后 `../../`
  指向 `.agents/`、目标不存在。需要这些资产的技能应在该仓的源码目录内运行（先
  `bash scripts/manage_repos.sh clone <repo> --scenario <id>`）。

## 相关链接

- [docs/04 技能目录与昇腾相关性](../../docs/04-skill-catalog-and-maintenance.md)
- [AGENTS.md §7 知识库与第三方技能路由](../../AGENTS.md)
