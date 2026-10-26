# AGENTS.md —— 昇腾推理优化工程 · Agent 治理规则（Phase 2）

## 0. 定位与入口导航

本工程驱动 LLM Agent 对**昇腾（910B / 950）**生态推理框架（vllm-ascend / MindIE-LLM・Motor / xLLM / SGLang-Ascend）做性能优化、算子开发、网络排障与新模型适配。本文件是 Agent 在本工程内的**行为准绳**，优先级高于任何技能说明与模型输出。

| 入口 | 内容 | 用法 |
| :--- | :--- | :--- |
| [docs/](docs/) | 方法论主文：J1→J6 阶段、诊断 SOP、技能选型、硬件校准 | 动手前先读对应阶段锚点 |
| [repos/](repos/) | `targets/` 待优化目标源码（可改、导出 patch）+ `refs/` 只读参考底座 | J1.5 盘点 / J3 归因 / J4 参考复用 |
| [src/](src/) | 自研交付：`plugins/`、`kernels/`、`tools/` | 阶梯 3/4 默认落点 |
| [.agents/skills/](.agents/skills/) | 三层技能：内化核心（7）/ vendored（7）/ external（21） | 按 §7 技能路由表取用 |

## 1. J1→J6 阶段路由表

| 阶段 | 目标 | 产出物 | 交付落点 | 参考文档锚点 |
| :--- | :--- | :--- | :--- | :--- |
| J1 目标定义 | 冻结硬件代际 / 模型特征向量 / 负载分布 / SLO | 目标定义单（四输入） | `cases/<case>/` | [01](docs/01-pipeline-and-ledger.md) |
| J1.5 引擎能力盘点 | **先查 `repos/refs/` 参考实现 + `repos/targets/` 现有能力，再算 gap**；接入冒烟 + 独立黄金参考在 J2 后、J3 前 | 支持矩阵 + 接入 gap 清单 | `repos/`（只读阅读） | [01](docs/01-pipeline-and-ledger.md) |
| J2 物理上限核算 | 双约束下界 + 本机校准 `P_eff` / `BW_eff` | 双约束账本（`MFU_eff` / `BW_util` 分母） | `cases/<case>/` | [01](docs/01-pipeline-and-ledger.md) |
| J3 基线归因 | J3.0 配置粗扫 → 实测基线 → 多维归因 | 基线报告 + msprof 证据 | `cases/<case>/` | [02](docs/02-ascend-diagnosis-sop.md) |
| J4 干预决策 | 五阶梯按 ROI 排序，**动手前声明源码落点** | 决策记录 + 落点声明 | — | [01](docs/01-pipeline-and-ledger.md) |
| J5 任务书交付 | 两阶段：方案评审 → 实现自测 | 任务书 + `test_op.py` / `benchmark_op.py` | `src/` 或 `repos/targets/` | [任务书模板](templates/task-spec-template.md) |
| J6 双轨门禁 | 轨道 A 正确性 + 轨道 B 性能（探索态 / 验收态） | 门禁报告 | `cases/<case>/` | [门禁规则](gates/README.md) |

回边：J6 未达预期 → 回 J3 重新归因；J4 阶梯失败 → 回退上一阶梯；J2 证明物理不可达 → 回 J1 重谈 SLO。

干预五阶梯（J4 按 ROI 排序，失败回退上一阶梯）：`阶梯 1 配置与编排调优` / `阶梯 2 已有成熟后端切换` / `阶梯 3 Out-of-tree 插件扩展` / `阶梯 4 专用 Kernel 移植与开发` / `阶梯 5 底层引擎内核重写与 Fork`。

## 2. 源码目录边界军规

| 目录 | 权限 | 何时选它 |
| :--- | :--- | :--- |
| `src/plugins/` | 可写（根仓跟踪） | 阶梯 3：引擎支持插件化（register_model / QuantizationConfig / AttentionBackend），无需改引擎源码 |
| `src/kernels/` | 可写（根仓跟踪） | 阶梯 4：生态确无现成实现；每算子强制含 `test_op.py` + `benchmark_op.py` |
| `src/tools/` | 可写（根仓跟踪） | 辅助工具（golden 采集 / ND↔NZ 重排 / msprof 解析） |
| `repos/targets/<engine>/` | 可写（独立 git） | 仅阶梯 2/4/5 必须改引擎源码时；须建优化分支，交付以 `export-patch` 为准 |
| `repos/refs/<repo>/` | **只读** | 参考实现底座：只阅读 / 对比 / 借鉴思路，任何改动一律禁止 |

- **强制**：J4/J5 动手前必须在任务书中显式声明「目标源码落点」（`src/kernels/` \| `src/plugins/` \| `repos/targets/<repo>`）与「参考源码路径」（`repos/refs/<repo>`），未经声明不得编码。
- `repos/refs/` 只读：需要复用其思路时在 `src/` 自研实现；`repos/targets/` 的改动必须 `export-patch` 到 `cases/<case>/patches/`，交付以 patch 为准（脚本见 [manage_repos.sh](scripts/manage_repos.sh)）。

## 3. J2 双约束账本铁律

- 任何「利用率低于 X%」的判定，**分母必须是本机校准的 `P_eff` / `BW_eff`**（理想大 GEMM 微基准得 `P_eff = α·P_peak`；STREAM / 大 copy 得 `BW_eff = β·BW_peak`），**禁止用理论峰值**——以理论峰值为分母会把编译器/库的正常效率损耗误判为引擎缺陷，诱发错误干预阶梯。
- 平衡点 `B* = P_eff / BW_eff`（FLOP/Byte）：`AI > B*` → 算力受限；`AI < B*` → 访存受限；判据与下界必须与当前精度一致。
- `MFU_eff = 理论最少 FLOPs / (T_actual × P_eff)`；`BW_util = Data Per Step / (T_actual × BW_eff)`；`P_*` / `BW_*` 用 SI 基单位（FLOP/s、B/s），TFLOPS/TB/s 须 ×10¹² 代入。
- 校准台账见 [calibration-template.md](templates/calibration-template.md)；公式细节（`N_active` vs `N_card`、MoE 分片、Decode/Prefill 下界）见 [01](docs/01-pipeline-and-ledger.md)。

## 4. msprof 测量铁律

- **只信 `msprof` / `msprof op`**：性能评价一律以 msprof 采集产物为准（端到端用 `msprof`，算子微基准用 `msprof op`）。
- **禁用** `time.time()`、`torch.npu.Event`、`do_bench` 做性能评价（均含 Host 开销、口径不可信）。
- 环境冻结、开环负载、预热到稳态、报中位数与 P95/P99、避免观测者污染——完整协议见 [02](docs/02-ascend-diagnosis-sop.md)。
- `benchmark_op.py` 必须用 `msprof op` 出微基准与 UB/带宽利用率、对比基线加速比。

## 5. 五不准红线（昇腾版，命中直接打回）

1. **热路径隐式同步**：`.item()` / `.cpu()` / `torch.nonzero()` / 基于张量结果的 Python `if`（摧毁异步发射与图录制）。
2. **前向动态转换权重**：推理循环内 `dequantize()` / `.contiguous()`（重排与反量化必须在加载期一次完成）。
3. **访存边界错误**：AscendC / Triton 非整除 Tile 下 `mask=` 缺失、偏移越界或静默错值。
4. **低精度累加**：累加器必须显式 fp32（如 `tl.sum(x.to(tl.float32))`；`tl.dot` 默认 fp32 除外）。
5. **测试套件人为弱化**：放宽容差（如 atol=1.0）或只测规整 shape。

## 6. J5 两阶段交付与门禁所有权

1. **阶段一（方案评审）**：先交数学推导、Tiling 规划、边界保护、接口契约与参考代码位置；**未经方案评审严禁编码**。
2. **阶段二（实现自测）**：方案确认后编码，强制附带独立正确性自测 + `msprof op` 微基准。
3. **门禁所有权**：门禁脚本 / 阈值 / 基线由架构师持有并对 Agent **只读**（Agent 无写权限的独立仓或受保护分支），Agent 只交实现与自测，不得改门禁——见 [gates/README.md](gates/README.md)。
4. 交付必须附从零复现命令与版本信息；「换台机器跑不出同样结果」即视为未通过。

## 7. 技能路由表

| 触发场景 | 技能层 | 取用 |
| :--- | :--- | :--- |
| 910B 服务器操作 / 环境核查 / 部署 | 内化核心 | `ascend-910b-server` |
| msprof 采集与瓶颈归因 | 内化核心 | `ascend-msprof-diagnosis` |
| 算子优化（Tiling / UB / 流水 / 边界） | 内化核心 | `ascend-kernel-optim` |
| HCCL / 卡间通信排障 | 内化核心 | `ascend-network-hccl` |
| GPU→NPU 迁移与图模式（TorchAir / npugraph_ex） | 内化核心 | `ascend-migration-and-graph` |
| vllm-ascend 模型适配与部署 | 内化核心 | `vllm-ascend-adapter` |
| 量化与精度 / 性能门禁 | 内化核心 | `ascend-quant-and-gate` |
| 评测（MMLU / GSM8K 误差预算） | vendored | `evalscope` |
| KV 远端缓存 / PD 解耦（Mooncake） | vendored | `mooncake-api`、`mooncake-troubleshoot` |
| 微基准 / Triton 写核 / 精度一致性 / 分布式卡死 | vendored | `kernel-microbenchmark`、`triton-kernel-writing`、`kl-consistency-test`、`debug-distributed-hang` |
| 专项深挖（算子 / 网络 / 工具 / 引擎） | external | `.agents/skills/external/{operators,network,tooling,engines}/`（21 源，见 [sync_ascend_skills.sh](scripts/sync_ascend_skills.sh)） |

## 8. 脚本速用

| 脚本 | 关键子命令 | 用途 |
| :--- | :--- | :--- |
| [manage_repos.sh](scripts/manage_repos.sh) | `--list` / `clone [--targets\|--refs\|<name>]` / `status` / `export-patch <repo> <case>` | 双轨源码仓的克隆、巡检与补丁归档 |
| [sync_ascend_skills.sh](scripts/sync_ascend_skills.sh) | `--list` / `--category {operators,network,tooling,engines,all} [--only <name>]` | 从 21 个外部源仓同步 SKILL.md 到 `.agents/skills/external/` |

## 9. 环境事实与红线

| 项 | 事实 |
| :--- | :--- |
| 评测服务器 | `10.19.93.115`（SSH 端口 `22022`，密钥 `~/.ssh/910b_ed25519`），8×910B3，HBM 64GB/卡，`npu-smi 25.5.1` |
| 硬件代际 | `910B3`（A2/A3）与 `950PR/950DT`（A5 / arch35）；UB 组织、SIMD/SIMT、HiF8/MXFP、CCU 等差异见 [calibration-template.md](templates/calibration-template.md) 代际对照栏 |
| CANN 版本 | **须上机核对**（CANN / torch_npu / PyTorch / 驱动 HDK 配套不可混装）；换版本必须重跑校准与复测 |
| 红线 | 禁止引用未核验的硬件数值；`P_eff` / `BW_eff` 一律本机实测后使用；`repos/refs/` 与门禁路径禁写 |
