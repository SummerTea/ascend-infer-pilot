# AGENTS.md —— 昇腾推理优化工程 · Agent 治理规则（Phase 11）

## 0. 定位与入口导航

本工程驱动 LLM Agent 对**昇腾（910B / 950）**生态推理框架（vllm-ascend / MindIE-LLM・Motor / xLLM / SGLang-Ascend）做性能优化、算子开发、网络排障与新模型适配。本文件是 Agent 在本工程内的**行为准绳**，优先级高于任何技能说明与模型输出。

| 入口 | 内容 | 用法 |
| :--- | :--- | :--- |
| [README.md](README.md) | 总览：6 步快速启动 + 任务类型速查 | 首次接手先读 |
| [docs/](docs/) | 方法论主文：J0→J6 阶段、诊断 SOP、技能选型、硬件校准 | 动手前先读对应阶段锚点 |
| [repos/](repos/) | 只读参考底座 `refs/` + 清单 `manifest.yaml` | J1.5 盘点 / J3 归因 / J4 参考复用 |
| `workspace/` | **不入库**：`<scenario-id>/`（`source/` + `optimized/` + `ledger/`）+ `_shared/calibration.md` | J4/J5 落点 / J6 过程留痕 |
| [.agents/skills/](.agents/skills/) | 第三方技能（平铺）：5 个入库 + 约 172 个同步而来（不入库） | 按 §7 技能路由表取用 |

## 1.0 J0 定焦：先收窄再冻结

**为什么**：J1 的四输入在**无焦点**时无法填——SLO 需依据可达上限，而可达上限取决于瓶颈在哪一段；经验表明直接进 J1→J2 会变成「全局普查」而**空转**。先收窄再冻结：用三环漏斗把「优化某模型」收窄成**一个**瓶颈或约束点，产出**定位卡**。

**三环（一行）**：`R1 定阶段（prefill/decode/通信/调度 占比排序；加载属冷启动、不计入稳态窗口）→ R2 定类别（算/读/发/传）→ R3 定落点与手段（哪个器件 + 候选阶梯 + 收益上限）`。

**粗/精账本**：J0 用**粗口径** `P_eff≈α·P_peak` / `BW_eff≈β·BW_peak`（α≈0.65 / β≈0.70，**只判「算还是读」，不得用于 J6 门禁**）；定焦后 J2 只对焦点维度做**精校准**。

**硬出口（四条）**：占比 ≥20% / `msprof` 证据 / 明确候选阶梯 / 收益上限 ≥ 目标 gap 50%；**全满足才可进 J1/J4/J5**，否则回 R1/R2 换手段。**无定位卡不得进入 J1 / J4 / J5**（硬约束）。

**熔断**：R1~R3 **≤3 轮**（每轮记「学到什么 + 下轮换什么手段」），超限**升级给人**；「各段均衡且接近上限」**或 top-1 占比 <20% 的分布型** → 转**约束点分支**（容量/并行/精度/调度）。
细则唯一权威：[docs/06 §2/§3/§4/§6/§7/§8](docs/06-bottleneck-triage.md)。

## 1. J0→J6 阶段路由表

**Step 0 起手**：

1. **定 `scenario-id`**：命名式 `<卡数>x<硬件>-<模型>-<主攻>`，例 `2x910B-dsv41-flash-rocm-net`（与 `cases/<entry-id>.md` 的"来源场景"字段同名引用）。
2. **备料**：`bash scripts/sync_ascend_skills.sh --category all`（第三方技能）+ `bash scripts/manage_repos.sh clone --targets --scenario <scenario-id>`（目标源码进 `workspace/<scenario-id>/source/`；参考底座 `bash scripts/manage_repos.sh clone --refs` 进 `repos/refs/`）。
3. **建台账并从 `00-probe.md` 起**（先补机器档案与齐备性 → 再做 J0 定焦 `01-triage.md`）：`workspace/<scenario-id>/ledger/` 按 §1.5 顺序推进。

首次接手先读 [README.md](README.md) 的快速启动与**任务类型速查**（据任务选定入口阶段）；本文件给出完整阶段链 J0→J6，**各阶段的出口条件不可跳**——入口可依任务速查选，出口条件一律从严。

| 阶段 | 目标 | 产出物 | 交付落点 | 判据 / 锚点 |
| :--- | :--- | :--- | :--- | :--- |
| J0 定焦 | 收窄到**一个**瓶颈或约束点 | 定位卡（阶段/类别/证据/占比/候选阶梯/收益上限） | `workspace/<scenario-id>/ledger/01-triage.md` | 硬出口四条件全满足 ｜ [06 §6](docs/06-bottleneck-triage.md) |
| J1 目标定义 | **围绕已定焦瓶颈**冻结硬件代际 / 模型特征向量 / 负载分布 / SLO | 目标定义单（四输入） | `workspace/<scenario-id>/ledger/02-scope.md`（条目 md 仅在过验收态门禁后沉淀，见 §6.5） | 四维度齐全且与定位卡一致 ｜ [01 §2](docs/01-pipeline-and-ledger.md) |
| J1.5 引擎能力盘点 | **先查 `repos/refs/` 参考实现 + `workspace/<scenario-id>/source/` 现有能力，再算 gap**；接入冒烟 + 独立黄金参考在 J2 后、J3 前；golden（独立黄金参考）落 `04-freeze-and-gate.md` | 支持矩阵 + 接入 gap 清单 | `repos/refs/`（只读）+ `workspace/<scenario-id>/source/<engine>/`（只读阅读）；gap 清单落 `workspace/<scenario-id>/ledger/02-scope.md` | gap 逐项落到五阶梯某一级 ｜ [01 §3](docs/01-pipeline-and-ledger.md) |
| J2 物理上限核算 | 双约束下界 + 本机校准 `P_eff` / `BW_eff` | 双约束账本（`MFU_eff` / `BW_util` 分母） | `workspace/<scenario-id>/ledger/03-baseline-ledger.md` | 结果可复算、口径唯一 ｜ [01 §4](docs/01-pipeline-and-ledger.md) |
| J3 基线归因 | J3.0 配置粗扫 → 实测基线 → 多维归因 | 基线报告 + msprof 证据 | `workspace/<scenario-id>/ledger/iterations/` | 总耗时可映射明确归因 ｜ [02 §1](docs/02-ascend-diagnosis-sop.md) |
| J4 干预决策 | 五阶梯按 ROI 排序，**动手前声明源码落点** | 决策记录 + 落点声明 | `workspace/<scenario-id>/optimized/` 或 `workspace/<scenario-id>/source/<engine>/` | 收益/成本可量化、可回退 ｜ [01 §5](docs/01-pipeline-and-ledger.md) |
| J5 任务书交付 | 两阶段：方案评审 → 实现自测 | 任务书 + `test_op.py` / `benchmark_op.py` | `workspace/<scenario-id>/optimized/{plugins,kernels,tools}/` 或 `workspace/<scenario-id>/source/<engine>/` | 架构师评审通过、门禁所有权分离 ｜ [任务书模板](templates/task-spec-template.md)（docs 无 J5 专节） |
| J6 双轨门禁 | 轨道 A 正确性 + 轨道 B 性能（探索态 / 验收态） | 门禁报告 | 过程 `workspace/<scenario-id>/ledger/04-freeze-and-gate.md` + `summary.md`；入库 `cases/<entry-id>.md` §5 | 双轨全过、探索态→验收态 ｜ [01 §J6 实操](docs/01-pipeline-and-ledger.md) |

回边：J6 未达预期 → 回 J3 重新归因；J4 阶梯失败 → 回退上一阶梯；J2 证明物理不可达 → 回 J1 重谈 SLO；**J4/J5 无定位卡 → 回 J0**。

干预五阶梯（J4 按 ROI 排序，失败回退上一阶梯）：`阶梯 1 配置与编排调优` / `阶梯 2 已有成熟后端切换` / `阶梯 3 Out-of-tree 插件扩展` / `阶梯 4 专用 Kernel 移植与开发` / `阶梯 5 底层引擎内核重写与 Fork`。

## 1.5 场景台账工作流

每场景一份台账，落 `workspace/<scenario-id>/ledger/`（**不入库**），是**过程留痕**（决策依据与证据链）；沉淀结论走条目 md（`cases/`）。

**顺序（每场景按序执行，可复制）**：

```
00-probe → 01-triage → 02-scope → 03-baseline-ledger → 04-freeze-and-gate → 05-bootstrap → loop: iterations/it-NNN → summary.md
```

> 上述为 **8 个顺序步**；**台账 9 项中的 `state.json`** 随 loop **逐轮同步维护**，故不入顺序链。

**与 §1 阶段对应**：J0→`01-triage`；J1→`02-scope`（四输入）；J1.5→`02-scope` 的 gap 段；J2→`03-baseline-ledger`；J3→`iterations/`；J4→`optimized/` 或 `source/`；J5→任务书 + `optimized/`；J6→`04-freeze-and-gate` + `summary.md` + 条目。

**loop 每轮（`iterations/it-NNN.md`）按序记录**（下列 5 条是 [docs/05 §3](docs/05-case-library-and-ledger.md) **10 个字段的无损归并**，逐项以该处为准）：

1. 假设 → 对应阶梯/方法 → 改动（文件 + 关键 diff）
2. **环境指纹**（本轮实际版本 / 锁频 / commit）
3. `msprof` / `msprof op` 命令 + 产物路径 + 五表摘录
4. 门禁 A/B 结果 → **结论方向（正向 / 反向 / 无变化）** → 决策（保留 / 回退 / 继续）
5. 成本估计 → 下轮建议

**停止判据**：达标即停 / 预算耗尽即停 / 物理不可达即停。**回边**：J6 未达预期 → 回 J3；阶梯失败 → 回退上一阶梯；J2 物理不可达 → 回 J1 重谈 SLO。

字段清单与 `state.json` schema 见 [docs/05 §3](docs/05-case-library-and-ledger.md)。

## 2. 源码目录边界军规

| 落点 | 权限 | 何时用 |
| :--- | :--- | :--- |
| `workspace/<scenario-id>/optimized/plugins/` | 可写（**不入库**） | 阶梯 3：引擎支持插件化（register_model / QuantizationConfig / AttentionBackend），无需改引擎源码 |
| `workspace/<scenario-id>/optimized/kernels/` | 可写（**不入库**） | 阶梯 4：生态确无现成实现；**每算子强制含 `test_op.py` + `benchmark_op.py`** |
| `workspace/<scenario-id>/optimized/tools/` | 可写（**不入库**） | 辅助工具（golden 采集 / ND↔NZ 重排 / msprof 解析） |
| `workspace/<scenario-id>/source/<engine>/` | 可写（**不入库**，独立 `.git`） | 仅阶梯 2/4/5 必须改引擎源码时；建优化分支，改动用 `scripts/manage_repos.sh export-patch` 归档到 `workspace/<scenario-id>/ledger/patches/` |
| `repos/refs/<repo>/` | **只读** | 参考实现（复用思路需落到 `workspace/<scenario-id>/optimized/`） |

- **强制**：J4/J5 动手前必须在任务书中显式声明「目标源码落点」（`workspace/<scenario-id>/optimized/{kernels,plugins,tools}/` \| `workspace/<scenario-id>/source/<repo>`）与「参考源码路径」（`repos/refs/<repo>`），未经声明不得编码。
- `repos/refs/` 只读：需要复用其思路时在 `workspace/<scenario-id>/optimized/` 自研实现；`workspace/<scenario-id>/source/` 的改动必须 `export-patch` 到 `workspace/<scenario-id>/ledger/patches/`，交付以 patch 为准（脚本见 [manage_repos.sh](scripts/manage_repos.sh)）。
- **构建 / 加载前提**：宿主通常无 torch / torch_npu，构建与运行一律在容器内，且须先 `source /usr/local/Ascend/ascend-toolkit/set_env.sh` 才能用 `msprof` / `atc` / `hccl_test`；具体版本与镜像见本场景 `00-probe.md` 机器档案段；插件/kernel 的集成方式见 [docs/03 §3](docs/03-ascend-hardware-and-engines.md) 与 [docs/01](docs/01-pipeline-and-ledger.md) 阶梯 4 实操。

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
3. **访存边界错误**：非整除 Tile 下 `mask=` 缺失、偏移越界或静默错值（AscendC 实现 / Triton 排错均适用）。
4. **低精度累加**：累加器必须显式 fp32（如 `tl.sum(x.to(tl.float32))`；`tl.dot` 默认 fp32 除外）。
5. **测试套件人为弱化**：放宽容差（如 atol=1.0）或只测规整 shape。

## 6. J5 两阶段交付与门禁所有权

1. **阶段一（方案评审）**：先交数学推导、Tiling 规划、边界保护、接口契约与参考代码位置；**未经方案评审严禁编码**。
2. **阶段二（实现自测）**：方案确认后编码，强制附带独立正确性自测 + `msprof op` 微基准。
3. **门禁所有权**：门禁脚本 / 阈值 / 基线由架构师持有并对 Agent **只读**（Agent 无写权限的独立仓或受保护分支），Agent 只交实现与自测，不得改门禁——见 [gates/README.md](gates/README.md)。
4. 交付必须附从零复现命令与版本信息；「换台机器跑不出同样结果」即视为未通过。

## 6.5 J6 后的沉淀：条目入库引导

> **场景 vs 条目**：场景 = `workspace/<scenario-id>/` 的工作现场（硬件×模型×变体×主攻方向的迭代，产出 0..N 个条目）；条目 = `cases/<entry-id>.md` 的可复用技术条目（如 `op-fusion`、`net-transfer-fusion`），可被多场景引用、元信息头记录来源场景。**场景是过程，条目是沉淀**，两词不得混用。

- 优化**有效果且过验收态门禁**后，由 Agent **自主沉淀为条目**：写 `cases/<entry-id>.md`（7 节规范见 [docs/05](docs/05-case-library-and-ledger.md)）并更新 [cases/index.md](cases/index.md)。
- **条目 = 可复用技术条目**（如 `op-fusion`、`net-transfer-fusion`）：一个场景可产出多个条目，条目元信息头记录来源场景。
- 过程台账保留在 `workspace/<scenario-id>/ledger/`；**入库纪律：仅验收态有效果条目**。

## 7. 知识库与第三方技能路由

**自研 / 个性化知识 → `docs/`**（方法论主文 + 实操章节）：

| 主题 | 入口 |
| :--- | :--- |
| 算子开发与审查 | [docs/01](docs/01-pipeline-and-ledger.md) §`阶梯 4 实操：算子开发与审查（AscendC / Triton-Ascend / TileLang / CATLASS）` |
| 量化与门禁 | [docs/01](docs/01-pipeline-and-ledger.md) §`J6 实操：量化与门禁（msmodelslim + L1/L2/L3 + 探索态/验收态）` |
| msprof 采集与归因 | [docs/02](docs/02-ascend-diagnosis-sop.md) §`msprof 采集与归因实操（五表 / AICPU / GPU↔NPU 对比）` |
| HCCL 与通信排障 | [docs/02](docs/02-ascend-diagnosis-sop.md) §`HCCL 与通信排障实操（基线 / 快慢卡 / RoCE / PD 分离）` |
| 迁移与图模式 | [docs/03](docs/03-ascend-hardware-and-engines.md) §`CUDA→torch_npu 迁移与图模式修复` |
| vllm-ascend 接入 | [docs/03](docs/03-ascend-hardware-and-engines.md) §`vllm-ascend 接入与融合算子替换` |
| 主机环境（本机事实） | 当前场景台账 `workspace/<scenario-id>/ledger/00-probe.md` 机器档案段（**不入库**；缺失或换机/换版本时按 §9 探针命令重跑写入） |

**第三方技能 → `.agents/skills/`**：平铺目录（Agent Skills 规范），由 [sync_ascend_skills.sh](scripts/sync_ascend_skills.sh) 同步、不入库。第三方技能为上游原文（含 NVIDIA/CUDA 口径），**昇腾相关性评估见 [docs/04](docs/04-skill-catalog-and-maintenance.md) §第三方技能昇腾相关性评估**；执行一律以 msprof 铁律与 `docs/` 为准。

- **结构**：Agent Skills 规范**平铺**（`<skill-name>/SKILL.md`），**无分类子目录**；入库仅 5 个 + README（白名单见 `.gitignore`），其余约 172 个同步而来、不入库。
- **算子开发路线强制**：`AscendC` > `TileLang` > `PyPTO`/`CATLASS`；**Triton / Triton-Ascend 不在实现路线**（脚本 denylist 排除）。
- **路由细则**（J0→J6 各环节该用哪些技能 + 重复对优先选用）：见 `.agents/skills/README.md`。

## 8. 脚本速用

| 脚本 | 关键子命令 | 用途 |
| :--- | :--- | :--- |
| [manage_repos.sh](scripts/manage_repos.sh) | `--list [--scenario <id>]` / `clone [--targets\|--refs\|<name>\|URL] [--scenario <id>]` / `status [--scenario <id>]` / `export-patch <repo> --scenario <id>` | 目标源码（`workspace/<scenario-id>/source/`）与参考底座（`repos/refs/`）的克隆、巡检与补丁归档 |
| [sync_ascend_skills.sh](scripts/sync_ascend_skills.sh) | `--list` / `--category {dev,ops,gate,all}` / `--only <origin>` / `--dry-run` | 按 **13 仓 / 21 条 allowlist** 同步 SKILL.md，**平铺**到 `.agents/skills/`（不入库；Triton 一律排除） |

> 单轮实验记录用 [PMR 模板](templates/pmr-log-template.md)（Predict / Measure / Review），与台账 `iterations/it-NNN.md` 互为素材。

## 9. 主机环境取证

**新场景尚无 `00-probe.md` 机器档案段时**：先向持卡人索取接入信息（主机 / SSH 端口 / 密钥路径 / 账号）并写入本场景 `workspace/<scenario-id>/ledger/00-probe.md` 的机器档案段，再执行下列探针。**本仓库不承载任何机器专属值**（不写 IP / 端口 / 密钥 / 版本号）。

本机事实（登录方式 / 卡型 / HBM / 驱动、CANN 与工具版本 / 容器与镜像 / 磁盘与模型·数据集落点）记录在该场景台账 `workspace/<scenario-id>/ledger/00-probe.md` 的「机器档案」段（**不入库**；字段规范见 [docs/05 §3](docs/05-case-library-and-ledger.md)）。机器专属值不得写入本文件。

通用探针命令（换机 / 换版本后重跑，把结果写入当前场景台账 `00-probe.md` 的机器档案段）：

```
ssh -i ~/.ssh/<密钥> -o IdentitiesOnly=yes -p <端口> root@<服务器IP>
npu-smi info
npu-smi info -t topo
source /usr/local/Ascend/ascend-toolkit/set_env.sh
cat /usr/local/Ascend/driver/version.info
ls -l /usr/local/Ascend/cann
docker ps -a
df -h /data /
nproc
free -g
```
> 完整探针（含 `msprof` / `hccl_test` / 校准前置）见 [docs/03 §2 主机环境核对](docs/03-ascend-hardware-and-engines.md)。
