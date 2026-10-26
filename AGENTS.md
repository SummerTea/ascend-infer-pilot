# AGENTS.md —— 昇腾推理优化工程 · Agent 治理规则（Phase 6）

## 0. 定位与入口导航

本工程驱动 LLM Agent 对**昇腾（910B / 950）**生态推理框架（vllm-ascend / MindIE-LLM・Motor / xLLM / SGLang-Ascend）做性能优化、算子开发、网络排障与新模型适配。本文件是 Agent 在本工程内的**行为准绳**，优先级高于任何技能说明与模型输出。

| 入口 | 内容 | 用法 |
| :--- | :--- | :--- |
| [docs/](docs/) | 方法论主文：J1→J6 阶段、诊断 SOP、技能选型、硬件校准 | 动手前先读对应阶段锚点 |
| [repos/](repos/) | 只读参考底座 `refs/` + 清单 `manifest.yaml` | J1.5 盘点 / J3 归因 / J4 参考复用 |
| `workspace/` | **不入库**：`source/` 待优化源码 + `optimized/` 自研交付 + `ledger/` 台账 | J4/J5 落点 / J6 过程留痕 |
| [.agents/skills/](.agents/skills/) | 仅第三方技能：vendored（7）/ external（21） | 按 §7 技能路由表取用 |

## 1. J1→J6 阶段路由表

| 阶段 | 目标 | 产出物 | 交付落点 | 参考文档锚点 |
| :--- | :--- | :--- | :--- | :--- |
| J1 目标定义 | 冻结硬件代际 / 模型特征向量 / 负载分布 / SLO | 目标定义单（四输入） | `workspace/ledger/<case-id>/00-scope.md`（案例 md 仅在过验收态门禁后由 Agent 沉淀，见 §6.5） | [01](docs/01-pipeline-and-ledger.md) |
| J1.5 引擎能力盘点 | **先查 `repos/refs/` 参考实现 + `workspace/source/` 现有能力，再算 gap**；接入冒烟 + 独立黄金参考在 J2 后、J3 前 | 支持矩阵 + 接入 gap 清单 | `repos/refs/`（只读）+ `workspace/source/<engine>/`（盘点现有能力，只读阅读）；gap 清单落 `workspace/ledger/<case-id>/00-scope.md` | [01](docs/01-pipeline-and-ledger.md) |
| J2 物理上限核算 | 双约束下界 + 本机校准 `P_eff` / `BW_eff` | 双约束账本（`MFU_eff` / `BW_util` 分母） | `workspace/ledger/<case-id>/02-baseline-ledger.md` | [01](docs/01-pipeline-and-ledger.md) |
| J3 基线归因 | J3.0 配置粗扫 → 实测基线 → 多维归因 | 基线报告 + msprof 证据 | `workspace/ledger/<case-id>/iterations/` | [02](docs/02-ascend-diagnosis-sop.md) |
| J4 干预决策 | 五阶梯按 ROI 排序，**动手前声明源码落点** | 决策记录 + 落点声明 | `workspace/optimized/` 或 `workspace/source/<engine>/` | [01](docs/01-pipeline-and-ledger.md) |
| J5 任务书交付 | 两阶段：方案评审 → 实现自测 | 任务书 + `test_op.py` / `benchmark_op.py` | `workspace/optimized/plugins\|kernels\|tools/` 或 `workspace/source/<engine>/` | [任务书模板](templates/task-spec-template.md) |
| J6 双轨门禁 | 轨道 A 正确性 + 轨道 B 性能（探索态 / 验收态） | 门禁报告 | 过程 `workspace/ledger/<case-id>/`；入库 `cases/<case-id>.md` §5 | [门禁规则](gates/README.md) |

回边：J6 未达预期 → 回 J3 重新归因；J4 阶梯失败 → 回退上一阶梯；J2 证明物理不可达 → 回 J1 重谈 SLO。

干预五阶梯（J4 按 ROI 排序，失败回退上一阶梯）：`阶梯 1 配置与编排调优` / `阶梯 2 已有成熟后端切换` / `阶梯 3 Out-of-tree 插件扩展` / `阶梯 4 专用 Kernel 移植与开发` / `阶梯 5 底层引擎内核重写与 Fork`。

## 2. 源码目录边界军规

| 落点 | 权限 | 何时用 |
| :--- | :--- | :--- |
| `workspace/optimized/plugins/` | 可写（**不入库**） | 阶梯 3：引擎支持插件化（register_model / QuantizationConfig / AttentionBackend），无需改引擎源码 |
| `workspace/optimized/kernels/` | 可写（**不入库**） | 阶梯 4：生态确无现成实现；**每算子强制含 `test_op.py` + `benchmark_op.py`** |
| `workspace/optimized/tools/` | 可写（**不入库**） | 辅助工具（golden 采集 / ND↔NZ 重排 / msprof 解析） |
| `workspace/source/<engine>/` | 可写（**不入库**，独立 `.git`） | 仅阶梯 2/4/5 必须改引擎源码时；建优化分支，改动用 `scripts/manage_repos.sh export-patch` 归档到 `workspace/ledger/<case>/patches/` |
| `repos/refs/<repo>/` | **只读** | 参考实现（复用思路需落到 `workspace/optimized/`） |

- **强制**：J4/J5 动手前必须在任务书中显式声明「目标源码落点」（`workspace/optimized/{kernels,plugins,tools}/` \| `workspace/source/<repo>`）与「参考源码路径」（`repos/refs/<repo>`），未经声明不得编码。
- `repos/refs/` 只读：需要复用其思路时在 `workspace/optimized/` 自研实现；`workspace/source/` 的改动必须 `export-patch` 到 `workspace/ledger/<case>/patches/`，交付以 patch 为准（脚本见 [manage_repos.sh](scripts/manage_repos.sh)）。

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

## 6.5 J6 后的沉淀：案例入库引导

- 优化**有效果且过验收态门禁**后，由 Agent **自主沉淀为案例**：写 `cases/<case-id>.md`（7 节规范见 [docs/05](docs/05-case-library-and-ledger.md)）并更新 [cases/index.md](cases/index.md)。
- 过程台账保留在 `workspace/ledger/<case-id>/`；**案例库入库纪律：仅验收态有效果案例**。

## 7. 知识库与第三方技能路由

**自研 / 个性化知识 → `docs/`**（方法论主文 + 实操章节）：

| 场景 | 入口 |
| :--- | :--- |
| 算子开发与审查 | [docs/01](docs/01-pipeline-and-ledger.md) §`阶梯 4 实操：算子开发与审查（AscendC / Triton-Ascend / TileLang / CATLASS）` |
| 量化与门禁 | [docs/01](docs/01-pipeline-and-ledger.md) §`J6 实操：量化与门禁（msmodelslim + L1/L2/L3 + 探索态/验收态）` |
| msprof 采集与归因 | [docs/02](docs/02-ascend-diagnosis-sop.md) §`msprof 采集与归因实操（五表 / AICPU / GPU↔NPU 对比）` |
| HCCL 与通信排障 | [docs/02](docs/02-ascend-diagnosis-sop.md) §`HCCL 与通信排障实操（基线 / 快慢卡 / RoCE / PD 分离）` |
| 迁移与图模式 | [docs/03](docs/03-ascend-hardware-and-engines.md) §`CUDA→torch_npu 迁移与图模式修复` |
| vllm-ascend 接入 | [docs/03](docs/03-ascend-hardware-and-engines.md) §`vllm-ascend 接入与融合算子替换` |
| 主机环境（本机事实） | [AGENTS.md.local](AGENTS.md.local)（**不入版本控制**，缺失时按 §9 探针命令生成或更新） |

**第三方技能 → `.agents/skills/`**：`vendored/`（7，随仓库跟踪）+ `external/`（21，按域同步、内容被 gitignore，见 [sync_ascend_skills.sh](scripts/sync_ascend_skills.sh)）。第三方技能为上游原文（含 NVIDIA/CUDA 口径），**昇腾相关性评估见 [docs/04](docs/04-skill-catalog-and-maintenance.md) §第三方技能昇腾相关性评估**；执行一律以 msprof 铁律与 `docs/` 为准。

## 8. 脚本速用

| 脚本 | 关键子命令 | 用途 |
| :--- | :--- | :--- |
| [manage_repos.sh](scripts/manage_repos.sh) | `--list` / `clone [--targets\|--refs\|<name>]` / `status` / `export-patch <repo> <case>` | 目标源码（`workspace/source/`）与参考底座（`repos/refs/`）的克隆、巡检与补丁归档 |
| [sync_ascend_skills.sh](scripts/sync_ascend_skills.sh) | `--list` / `--category {operators,network,tooling,engines,all} [--only <name>]` | 从 21 个外部源仓同步 SKILL.md 到 `.agents/skills/external/` |

## 9. 主机环境取证

本机实测值（服务器地址与端口 / CANN 与驱动版本 / 容器与镜像 / 磁盘与模型落点）见 **`AGENTS.md.local`**（**不入版本控制**，缺失时按下列命令生成或更新）。

通用探针命令（换机 / 换版本后重跑，把结果更新进 `AGENTS.md.local`）：

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
