# ascend-infer-pilot —— 昇腾推理优化工程

## 工程是什么

本工程驱动 LLM Agent 对**昇腾（910B / 950）**生态推理框架（vllm-ascend / MindIE-LLM・Motor / xLLM / SGLang-Ascend）做性能优化、算子开发、网络排障与新模型适配，按 **J0→J6** 阶段链闭环交付：**定焦（先收窄）** → 目标定义 → 引擎能力盘点 → 物理上限核算 → 基线归因 → 干预决策 → 任务书交付 → 双轨门禁。

## 为什么需要这个工程

昇腾 NPU 与 NVIDIA 在测量工具（msprof vs ncu/nsys）、硬件代际（910B3 vs 950）、算子范式（AscendC / Triton-Ascend / TileLang）上差异巨大，通用 GPU 优化经验不可直接迁移。工程通过硬性治理（[AGENTS.md](AGENTS.md)）把方法论固化：`P_eff` / `BW_eff` 只认本机校准、性能只信 `msprof`、五不准红线打回劣质代码、门禁所有权与 Agent 分离，保证「可复现、过门禁、有实测提升」。

方法论源头是 `inference` 工作区 `notes/01-overview/` 的三份主文档（推理定制方法论 / 性能诊断 / 昇腾技能选型），本工程将其精裁为 [docs/](docs/) 六篇并配齐模板、脚本与门禁，落地为可执行流程。

## 共享契约速览

| 术语 | 约定 |
| :--- | :--- |
| 阶段链 | `J0 定焦` → `J1 目标定义` → `J1.5 引擎能力盘点` → `J2 物理上限核算` → `J3 基线归因` → `J4 干预决策` → `J5 任务书交付` → `J6 双轨门禁` |
| 干预五阶梯 | `阶梯 1 配置与编排调优` / `阶梯 2 已有成熟后端切换` / `阶梯 3 Out-of-tree 插件扩展` / `阶梯 4 专用 Kernel 移植与开发` / `阶梯 5 底层引擎内核重写与 Fork` |
| 双约束 | `P_eff`（算力可达上限）/ `BW_eff`（带宽可达上限）/ `B* = P_eff / BW_eff` / `MFU_eff` / `BW_util` |
| 测量铁律 | 只信 `msprof` / `msprof op`；禁用 `time.time()`、`torch.npu.Event`、`do_bench` |
| 门禁 | 轨道 A：`L1 逐位一致` / `L2 数值门`（余弦+误差双指标）/ `L3 有损门`（下游任务误差预算）；轨道 B：收益 ≥ 预估 80%、开环 Goodput、边界与回归抽检、长稳、灰度回滚；`探索态` vs `验收态` |

## 快速启动工作流（6 步）

> 前置：核对**当前场景台账** `workspace/<scenario-id>/ledger/00-probe.md` 的机器档案段（不入库）；缺失或换机/换版本时按 [AGENTS.md §9](AGENTS.md) 探针命令重跑并写入台账。

1. **同步技能**：`scripts/sync_ascend_skills.sh --category all`（按 **13 仓 / 21 条 allowlist** 拉取 SKILL.md，**平铺**到 `.agents/skills/`，不入库）。升级/清理用 `--prune` + `--update-lock`（见 [.agents/skills/README.md](.agents/skills/README.md) 日常更新流程）。
2. **克隆目标源码 + 建台账**：`scripts/manage_repos.sh clone --targets --scenario <id> && scripts/manage_repos.sh clone --refs`（按 [repos/manifest.yaml](repos/manifest.yaml) 浅克隆：targets 落到 `workspace/<scenario-id>/source/`，refs 落到 `repos/refs/`）；随后按 [docs/05 §3](docs/05-case-library-and-ledger.md) 建场景台账 9 项（`workspace/<scenario-id>/ledger/`，起点 `00-probe.md`；随后 **J0 定焦** `01-triage.md`）。
3. **读方法论**：先读 [docs/06-bottleneck-triage.md](docs/06-bottleneck-triage.md)（**J0 定焦**：三环漏斗先收窄成一个瓶颈/约束点，冻结目标前必过）再读 [docs/01-pipeline-and-ledger.md](docs/01-pipeline-and-ledger.md)（J0→J6 主线），诊断类任务加读 [docs/02-ascend-diagnosis-sop.md](docs/02-ascend-diagnosis-sop.md)。
4. **用模板派发**：用 [任务书模板](templates/task-spec-template.md) 写任务书（必填源码落点与参考路径）；实验记录与校准台账用 [PMR](templates/pmr-log-template.md)、[校准台账](templates/calibration-template.md) 两个模板。
5. **归档补丁**：改 `workspace/<scenario-id>/source/` 后 `scripts/manage_repos.sh export-patch <repo> --scenario <id>` 导出 patch 到 `workspace/<scenario-id>/ledger/patches/`。
6. **有效果 → 沉淀条目**：过验收态门禁后写 `cases/<entry-id>.md`（7 节规范见 [docs/05](docs/05-case-library-and-ledger.md)）并更新 `cases/index.md`。

## 任务类型速查

| 任务类型 | 走哪条链 | 用哪个模板 / 门禁 |
| :--- | :--- | :--- |
| 性能调优（延迟 / 吞吐不达标） | J3 归因 → J6 | [任务书](templates/task-spec-template.md) + [PMR](templates/pmr-log-template.md) |
| 新模型适配 | J1.5 盘点 → J5 | [任务书](templates/task-spec-template.md)（先查 `repos/refs/` + `workspace/<scenario-id>/source/`） |
| 量化改造 | J2 账本 → J6 | [任务书](templates/task-spec-template.md) + L3 有损门（evalscope） |
| 算子开发（阶梯 4） | J4 决策 → J5 | [任务书](templates/task-spec-template.md) + `test_op.py` / `benchmark_op.py` |
| 网络 / HCCL 排障 | J3 直接定位 | [诊断 SOP](docs/02-ascend-diagnosis-sop.md) |

> **上表列的是「主攻阶段」，不是「可跳过 J0」**：任一入口都须先有 J0 定位卡（`workspace/<scenario-id>/ledger/01-triage.md`），否则不得进入 J1/J4/J5。

## 目录地图

| 目录 | 内容 | 说明 |
| :--- | :--- | :--- |
| [docs/](docs/) | 方法论 01~07 + 自研知识实操章节 | **自研 / 个性化知识一律在 `docs/`**（01 流水线与账本 / 02 诊断 SOP / 03 硬件与引擎 / 04 技能目录 / 05 案例库与台账 / 06 定焦 SOP / **07 文档回写与合入纪律**；实操章节路由见 [AGENTS.md §7](AGENTS.md)） |
| [gates/](gates/README.md) | 双轨门禁规则与所有权 | 门禁由架构师持有，Agent 只读 |
| [templates/](templates/) | 任务书 / PMR / 校准台账 | 派发与记录模板 |
| [repos/](repos/README.md) | 只读参考底座 `refs/` + 清单 `manifest.yaml` | refs 严禁修改；待优化工程源码在 `workspace/<scenario-id>/source/`（每场景一份） |
| `workspace/` | **工作区（不入库）**：`<scenario-id>/`（一个优化场景一份：`source/` / `optimized/` / `ledger/`）+ `_shared/calibration.md` | 每场景一份、自包含、并发安全 |
| [scripts/](scripts/) | `manage_repos.sh` / `sync_ascend_skills.sh` | 源码与技能管理 |
| [cases/](cases/) | **案例库（入库）**：条目 `cases/<entry-id>.md` + 索引 `cases/index.md` | 条目可被多场景引用；过程台账在 `workspace/<scenario-id>/ledger/` |
| [.agents/skills/](.agents/skills/) | **第三方技能（平铺）**：5 个随仓库跟踪（白名单见 [.gitignore](.gitignore)）+ 190 个同步而来（共 195 个技能目录）、不入库 | 路由与昇腾相关性评估见 [AGENTS.md §7](AGENTS.md) |

## 源码仓挂载（manage_repos.sh）

`repos/` 现仅承载**只读参考底座** `refs/`（cann-recipes-infer / msmodelslim / catlass / pto-kernels / Mooncake）+ 清单 `manifest.yaml`；**待优化目标工程的源码不在 `repos/`，而在 `workspace/<scenario-id>/source/`**（manifest 的 `targets:` 段列出 7 个工程：vllm-ascend / vllm / MindIE-LLM / MindIE-Motor / xllm / sglang / tilelang-ascend，clone 落 `workspace/<scenario-id>/source/<name>`，每场景一份、不入库）。`scripts/manage_repos.sh` 按 `manifest.yaml` 管理：

- `clone --targets --scenario <id>` / `clone --refs`：批量浅克隆某段（targets → `workspace/<scenario-id>/source/`，refs → `repos/refs/`）；`clone <name> --scenario <id>` 单仓；`clone <git-url> --scenario <id>` 任意 URL 进 `workspace/<scenario-id>/source/`。
- `status [--scenario <id>]`：巡检 `workspace/<scenario-id>/source/`（可修改；给 `--scenario` 限定单场景，否则按场景分组巡检全部）与 `repos/refs/`（只读）已克隆仓的分支 / hash / 未提交改动（供 J3 环境冻结记录）。
- `export-patch <repo> --scenario <id>`：把 `workspace/<scenario-id>/source/` 仓改动导出为 `.patch` + `.meta.txt`（url / branch / base_commit）到 `workspace/<scenario-id>/ledger/patches/`，交付以 patch 为准。
- 军规：`repos/refs/` 严禁修改；`workspace/<scenario-id>/source/` 各仓须建优化分支再改，不直接动主线；`manifest.yaml` 中 12 条 url/branch 已联网核验，勿随意改写。

## 技能同步（sync_ascend_skills.sh）

`scripts/sync_ascend_skills.sh --category all` 按 **13 仓 / 21 条 allowlist**（开发 10 / 运维 9 / 门禁 2）发现并同步 SKILL.md 技能，**平铺**到 `.agents/skills/<skill-name>/`（不入库）。

- `.agents/skills/` 平铺落点不入库（白名单见 [.gitignore](.gitignore)）：**5 个技能随仓库跟踪**，其余 190 个同步而来、每次同步重新生成（共 195 个技能目录）。
- `--list` 离线查看源表（url/branch 已联网核验，勿改分支）；`--only <origin>` 定向重同步。

## 文档导航

| 文档 | 一句话 |
| :--- | :--- |
| [docs/01-pipeline-and-ledger.md](docs/01-pipeline-and-ledger.md) | J0→J6 方法论主文：阶段路由、双约束账本、五阶梯决策、五不准红线、双轨门禁 |
| [docs/02-ascend-diagnosis-sop.md](docs/02-ascend-diagnosis-sop.md) | 昇腾四瓶颈诊断 SOP：msprof 采集、归因阈值、火焰图 / 五表证据 |
| [docs/03-ascend-hardware-and-engines.md](docs/03-ascend-hardware-and-engines.md) | 昇腾硬件代际物理规格（910B vs 950）、引擎扩展挂载点、**Mac 驱动远程开发拓扑与主机契约** |
| [docs/04-skill-catalog-and-maintenance.md](docs/04-skill-catalog-and-maintenance.md) | 技能全景、NVIDIA↔昇腾工具对照、来源仓昇腾相关性评估与维护计划（换版本复测触发） |
| [docs/05-case-library-and-ledger.md](docs/05-case-library-and-ledger.md) | 场景/条目两层定义 + 台账与工作区规范 |
| [docs/06-bottleneck-triage.md](docs/06-bottleneck-triage.md) | J0 定焦 SOP：三环漏斗、硬出口四条件、熔断升级 |
| [docs/07-doc-writeback-and-merge.md](docs/07-doc-writeback-and-merge.md) | 流程短板的回写路径、合入六条硬约束、自指规则只有提议权 |
| [gates/README.md](gates/README.md) | 门禁所有权 + 数值语义容差表（L1 / L2 / L3 / 探索态-验收态） |
| [templates/task-spec-template.md](templates/task-spec-template.md) | 昇腾化性能实验任务书（必填源码落点与参考路径） |
| [templates/pmr-log-template.md](templates/pmr-log-template.md) | Predict / Measure / Review 三段式实验日志（msprof 证据） |
| [templates/calibration-template.md](templates/calibration-template.md) | NPU 硬件基线校准台账（环境冻结 / 代际对照 / 复测触发） |

> docs 新增实操章节：docs/01 §阶梯 4 实操：算子开发与审查、§J6 实操：量化与门禁；docs/02 §msprof 采集与归因实操、§HCCL 与通信排障实操；docs/03 §CUDA→torch_npu 迁移与图模式修复、§vllm-ascend 接入与融合算子替换、§Mac 驱动远程开发拓扑与主机契约；docs/04 §2 来源仓昇腾相关性评估。取用路由见 [AGENTS.md §7](AGENTS.md)。
