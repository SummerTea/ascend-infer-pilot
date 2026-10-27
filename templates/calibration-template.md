# NPU 硬件基线校准台账（P_eff / BW_eff）

> 任何「利用率低于 X%」的判定，分母必须来自本台账的**本机实测** `P_eff` / `BW_eff`，禁止用理论峰值（见 [AGENTS.md](../AGENTS.md) §3）。台账更新即触发引用方（任务书 / 门禁阈值 / 本轮 `it-NNN`）同步复算。
> **落点**：本台账实际存放于 `workspace/_shared/calibration.md`（跨场景共享、**不入库**，按 `<硬件>@<CANN+驱动+image_id>@<精度>` 分节——`P_eff` / `BW_eff` 是大 GEMM / 大 copy 的**硬件属性，与模型无关**，故主键不含模型）。**分节名取 `image_id` 前 12 位**（全量 ID 记在分节体内）；同硬件 / 版本 / 精度的多个旧分节**合并为一个新键**，冲突以复测值为准。**旧分节**若仍按 `<模型>@<硬件>` 命名：复测后按新键重命名；未复测的旧值只作参考，**不得用于 J6 门禁**。

## 一、环境冻结（每次复测必须完整记录）

| 项 | 值 |
| :--- | :--- |
| 芯片型号 | `<910B3（A2/A3） \| 950PR / 950DT（A5 / arch35）>` |
| CANN 版本 | `<上机核对，如 9.x.x>` |
| torch_npu 版本 | `<pip show torch-npu>` |
| PyTorch 版本 | `<pip show torch>` |
| 驱动 HDK 版本 | `<npu-smi / dmesg 核对>` |
| 容器镜像 image_id | `<docker image inspect <tag> --format '{{.Id}}'>`（分节键的一部分，容器内 CANN 可能与宿主不同） |
| npu-smi 版本 | `<npu-smi 版本>`（见当前场景台账 00-probe.md 的机器档案段） |
| 服务器 / 拓扑 | 卡间拓扑 `<HCCL 或 RoCE>`；服务器 IP / SSH 端口 / 卡型与数量 / HBM 以当前场景台账 `00-probe.md` 的**机器档案段为权威**，本表不重复落笔 |

## 二、P_eff 标定（理想大 GEMM 微基准）

- 方法：大矩阵 BF16 / FP8 GEMM，多组 M/N/K 取最优，`P_eff = α · P_peak`。
- 记录：`α = <值>`、GEMM shape `<M/N/K>`、精度 `<bf16/fp8>`、msprof 产物路径 `<...>`。

## 三、BW_eff 标定（STREAM / 大 copy）

- 方法：STREAM 类 / 大块连续 copy，`BW_eff = β · BW_peak`。
- 记录：`β = <值>`、拷贝方式 `<SM kernel / DMA>`、产物路径 `<...>`。

## 四、平衡点

- `B* = P_eff / BW_eff`（FLOP/Byte）= `<值>`
- 用途：`AI > B*` → 算力受限；`AI < B*` → 访存受限（判据与当前精度一致）。

## 五、910B vs 950 代际差异对照

| 维度 | 910B3（A2/A3） | 950PR / 950DT（A5 / arch35） |
| :--- | :--- | :--- |
| UB 组织 | 16 group × 3 × 4KB | 8 group × 2 × 16KB（Bank 冲突规则重写） |
| 执行模型 | 仅 SIMD（MemBase） | SIMD + SIMT 双模型（DCache / Warp Scheduler / 128KB RF） |
| 新增数据类型 | 无 | HiF8（hifloat8_t）、MXFP4 / MXFP8 |
| 通信引擎 | — | CCU（IO-Die 内，msprof 可采 CCU 带宽） |
| msprof 指标 | PipelineExecuteUtilization / MemoryAccess | 不支持上述两项，新增 CCU / UB 带宽采集 |
| 数据通路 | — | L0C→UB、UB→L1、SSBuffer CV 消息通路 |

## 六、msprof 采集命令与产物路径

- 端到端：`msprof --output=<路径> <命令>` → 产物 `<性能剖析文件路径>`（`--application` 在 CANN 9.0.0 已废弃，用位置参数）。
- 算子微基准：`msprof op --output=<dir> --application="python3 benchmark_op.py"` → 产物 `<msprof op 报告路径>`（`--application` 与位置参数两种形式均可，见 [docs/02](../docs/02-ascend-diagnosis-sop.md)）。
- 产物统一归档到 `workspace/<scenario-id>/ledger/profiling/<triage-NN | it-NNN>/`（不入库），随本轮 `it-NNN`（骨架见 [PMR 模板](../templates/pmr-log-template.md)）一并留存。

## 七、复测触发条件

- **换 CANN / torch_npu / PyTorch / 驱动 HDK 版本 / 容器 `image_id`（重建镜像）** → 必须复测并更新本台账。
- **例外（沿用原分节值）**：`image_id` 变更但属 [docs/03 §2](../docs/03-ascend-hardware-and-engines.md) 的跳过路径（**仅新增诊断工具**且三项版本 diff 全同）→ **不触发**全量复测：新分节注明「版本串相同，继承自 `<旧分节>`」并引用原值。比较 `pip freeze` 时**排除本次新增的诊断工具包本身**，并在跳过记录列出包名 / 版本 / 来源；诊断包之外的任何新增或升级一律复测。
- **换芯片版本（910B3 ↔ 950）** → 必须复测（UB 组织、SIMT、HiF8、CCU、msprof 指标均不同，见 §五）。
- 台账更新后，引用 `P_eff` / `BW_eff` 的任务书与门禁阈值须同步复算；复测需先跑通本台账的 §一 环境冻结记录。
