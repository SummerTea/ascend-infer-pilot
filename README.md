# ascend-infer-pilot —— 昇腾推理优化工程

## 工程是什么

本工程驱动 LLM Agent 对**昇腾（910B / 950）**生态推理框架（vllm-ascend / MindIE-LLM・Motor / xLLM / SGLang-Ascend）做性能优化、算子开发、网络排障与新模型适配，按 J1→J6 阶段链闭环交付：目标定义 → 引擎能力盘点 → 物理上限核算 → 基线归因 → 干预决策 → 任务书交付 → 双轨门禁。

## 为什么需要这个工程

昇腾 NPU 与 NVIDIA 在测量工具（msprof vs ncu/nsys）、硬件代际（910B3 vs 950）、算子范式（AscendC / Triton-Ascend / TileLang）上差异巨大，通用 GPU 优化经验不可直接迁移。工程通过硬性治理（[AGENTS.md](AGENTS.md)）把方法论固化：`P_eff` / `BW_eff` 只认本机校准、性能只信 `msprof`、五不准红线打回劣质代码、门禁所有权与 Agent 分离，保证「可复现、过门禁、有实测提升」。

方法论源头是 `inference` 工作区 `notes/01-overview/` 的三份主文档（推理定制方法论 / 性能诊断 / 昇腾技能选型），本工程将其精裁为 [docs/](docs/) 五篇并配齐模板、脚本与门禁，落地为可执行流程。

## 共享契约速览

| 术语 | 约定 |
| :--- | :--- |
| 阶段链 | `J1 目标定义` → `J1.5 引擎能力盘点` → `J2 物理上限核算` → `J3 基线归因` → `J4 干预决策` → `J5 任务书交付` → `J6 双轨门禁` |
| 干预五阶梯 | `阶梯 1 配置与编排调优` / `阶梯 2 已有成熟后端切换` / `阶梯 3 Out-of-tree 插件扩展` / `阶梯 4 专用 Kernel 移植与开发` / `阶梯 5 底层引擎内核重写与 Fork` |
| 双约束 | `P_eff`（算力可达上限）/ `BW_eff`（带宽可达上限）/ `B* = P_eff / BW_eff` / `MFU_eff` / `BW_util` |
| 测量铁律 | 只信 `msprof` / `msprof op`；禁用 `time.time()`、`torch.npu.Event`、`do_bench` |
| 门禁 | 轨道 A：`L1 逐位一致` / `L2 数值门`（余弦+误差双指标）/ `L3 有损门`（下游任务误差预算）；轨道 B：收益 ≥ 预估 80%、开环 Goodput、边界与回归抽检、长稳、灰度回滚；`探索态` vs `验收态` |

## 快速启动工作流（6 步）

> 前置：核对 [AGENTS.md.local](AGENTS.md.local)（主机环境说明，**不入库**）；缺失或换机/换版本时按 [AGENTS.md §9](AGENTS.md) 探针命令重跑并更新。

1. **同步技能**：`scripts/sync_ascend_skills.sh --category all`（拉取 21 个外部源仓的 SKILL.md 到 `.agents/skills/external/`）。
2. **克隆目标源码**：`scripts/manage_repos.sh clone --targets && scripts/manage_repos.sh clone --refs`（按 [repos/manifest.yaml](repos/manifest.yaml) 浅克隆：targets 落到 `workspace/source/`，refs 落到 `repos/refs/`）。
3. **读方法论**：先读 [docs/01-pipeline-and-ledger.md](docs/01-pipeline-and-ledger.md)（J1→J6 主线），诊断类任务加读 [docs/02-ascend-diagnosis-sop.md](docs/02-ascend-diagnosis-sop.md)。
4. **用模板派发**：用 [任务书模板](templates/task-spec-template.md) 写任务书（必填源码落点与参考路径）；实验记录与校准台账用 [PMR](templates/pmr-log-template.md)、[校准台账](templates/calibration-template.md) 两个模板。
5. **归档补丁**：改 `workspace/source/` 后 `scripts/manage_repos.sh export-patch <repo> <case>` 导出 patch 到 `workspace/ledger/<case>/patches/`。
6. **有效果 → 沉淀案例**：过验收态门禁后写 `cases/<case-id>.md`（7 节规范见 [docs/05](docs/05-case-library-and-ledger.md)）并更新 `cases/index.md`。

## 任务类型速查

| 任务类型 | 走哪条链 | 用哪个模板 / 门禁 |
| :--- | :--- | :--- |
| 性能调优（延迟 / 吞吐不达标） | J3 归因 → J6 | [任务书](templates/task-spec-template.md) + [PMR](templates/pmr-log-template.md) |
| 新模型适配 | J1.5 盘点 → J5 | [任务书](templates/task-spec-template.md)（先查 `repos/refs/` + `workspace/source/`） |
| 量化改造 | J2 账本 → J6 | [任务书](templates/task-spec-template.md) + L3 有损门（evalscope） |
| 算子开发（阶梯 4） | J4 决策 → J5 | [任务书](templates/task-spec-template.md) + `test_op.py` / `benchmark_op.py` |
| 网络 / HCCL 排障 | J3 直接定位 | [诊断 SOP](docs/02-ascend-diagnosis-sop.md) |

## 目录地图

| 目录 | 内容 | 说明 |
| :--- | :--- | :--- |
| [docs/](docs/) | 方法论 01~05 + 自研知识实操章节 | **自研 / 个性化知识一律在 `docs/`**（01 流水线与账本 / 02 诊断 SOP / 03 硬件与引擎 / 04 技能目录 / 05 案例库与台账；实操章节路由见 [AGENTS.md §7](AGENTS.md)） |
| [gates/](gates/README.md) | 双轨门禁规则与所有权 | 门禁由架构师持有，Agent 只读 |
| [templates/](templates/) | 任务书 / PMR / 校准台账 | 派发与记录模板 |
| [AGENTS.md.local](AGENTS.md.local) | 主机环境说明（**不入库** / 本机事实） | 服务器地址与端口、CANN/驱动版本、容器与镜像、磁盘与模型落点；缺失时按 [AGENTS.md §9](AGENTS.md) 探针命令生成 |
| [repos/](repos/README.md) | 只读参考底座 `refs/` + 清单 `manifest.yaml` | refs 严禁修改；待优化工程源码在 `workspace/source/` |
| `workspace/` | `source/` 待优化源码 + `optimized/` 自研交付 + `ledger/` 台账 | **不入库**、单份共享、暂不建 git |
| [scripts/](scripts/) | `manage_repos.sh` / `sync_ascend_skills.sh` | 源码与技能管理 |
| [cases/](cases/) | 案例库（入库）：一案例一 `cases/<case-id>.md` + `cases/index.md` | 交付物不入库；过程台账在 `workspace/ledger/` |
| [.agents/skills/](.agents/skills/) | **仅第三方技能**：`vendored/`（7，随仓库跟踪）+ `external/`（21，按域同步、内容被 gitignore） | 路由与昇腾相关性评估见 [AGENTS.md §7](AGENTS.md) |

## 源码仓挂载（manage_repos.sh）

`repos/` 现仅承载**只读参考底座** `refs/`（cann-recipes-infer / msmodelslim / catlass / pto-kernels / Mooncake）+ 清单 `manifest.yaml`；**待优化目标工程的源码不在 `repos/`，而在 `workspace/source/`**（manifest 的 `targets:` 段列出 7 个工程：vllm-ascend / vllm / MindIE-LLM / MindIE-Motor / xllm / sglang / tilelang-ascend，clone 落到 `workspace/source/<name>`，不入库）。`scripts/manage_repos.sh` 按 `manifest.yaml` 管理：

- `clone --targets` / `clone --refs`：批量浅克隆某段（targets → `workspace/source/`，refs → `repos/refs/`）；`clone <name>` 单仓；`clone <git-url>` 任意 URL 进 `workspace/source/`。
- `status`：巡检 `workspace/source/`（可修改）与 `repos/refs/`（只读）已克隆仓的分支 / hash / 未提交改动（供 J3 环境冻结记录）。
- `export-patch <repo> <case>`：把 `workspace/source/` 仓改动导出为 `.patch` + `.meta.txt`（url / branch / base_commit）到 `workspace/ledger/<case>/patches/`，交付以 patch 为准。
- 军规：`repos/refs/` 严禁修改；`workspace/source/` 各仓须建优化分支再改，不直接动主线；`manifest.yaml` 中 12 条 url/branch 已联网核验，勿随意改写。

## 技能同步（sync_ascend_skills.sh）

`scripts/sync_ascend_skills.sh --category all` 从 21 个外部源仓（operators / network / tooling / engines 四类）自动发现并同步 SKILL.md 技能到 `.agents/skills/external/<category>/<name>/`。

- `.agents/skills/external/` 被 [.gitignore](.gitignore) 忽略（仅保留 README.md），不会污染根仓库；**vendored/（7）受根仓库跟踪**，随工程版本化。
- `--list` 离线查看源表（url/branch 已联网核验，勿改分支）；`--only <name>` 定向重同步。

## 文档导航

| 文档 | 一句话 |
| :--- | :--- |
| [docs/01-pipeline-and-ledger.md](docs/01-pipeline-and-ledger.md) | J1→J6 方法论主文：阶段路由、双约束账本、五阶梯决策、五不准红线、双轨门禁 |
| [docs/02-ascend-diagnosis-sop.md](docs/02-ascend-diagnosis-sop.md) | 昇腾四瓶颈诊断 SOP：msprof 采集、归因阈值、火焰图 / 五表证据 |
| [docs/03-ascend-hardware-and-engines.md](docs/03-ascend-hardware-and-engines.md) | 昇腾硬件代际物理规格（910B vs 950）与引擎扩展挂载点 |
| [docs/04-skill-catalog-and-maintenance.md](docs/04-skill-catalog-and-maintenance.md) | 技能全景、NVIDIA↔昇腾工具对照、第三方技能昇腾相关性评估与维护计划（换版本复测触发） |
| [docs/05-case-library-and-ledger.md](docs/05-case-library-and-ledger.md) | 案例库与台账规范：`cases/<case-id>.md` 七节结构、`workspace/ledger/` 台账、入库纪律 |
| [gates/README.md](gates/README.md) | 门禁所有权 + 数值语义容差表（L1 / L2 / L3 / 探索态-验收态） |
| [templates/task-spec-template.md](templates/task-spec-template.md) | 昇腾化性能实验任务书（必填源码落点与参考路径） |
| [templates/pmr-log-template.md](templates/pmr-log-template.md) | Predict / Measure / Review 三段式实验日志（msprof 证据） |
| [templates/calibration-template.md](templates/calibration-template.md) | NPU 硬件基线校准台账（环境冻结 / 代际对照 / 复测触发） |

> docs 新增实操章节：docs/01 §阶梯 4 实操：算子开发与审查、§J6 实操：量化与门禁；docs/02 §msprof 采集与归因实操、§HCCL 与通信排障实操；docs/03 §CUDA→torch_npu 迁移与图模式修复、§vllm-ascend 接入与融合算子替换；docs/04 §第三方技能昇腾相关性评估。取用路由见 [AGENTS.md §7](AGENTS.md)。
