# NPU 硬件基线校准台账（P_eff / BW_eff）

> 任何「利用率低于 X%」的判定，分母必须来自本台账的**本机实测** `P_eff` / `BW_eff`，禁止用理论峰值（见 [AGENTS.md](../AGENTS.md) §3）。台账更新即触发引用方（任务书 / 门禁阈值 / PMR）同步复算。

## 一、环境冻结（每次复测必须完整记录）

| 项 | 值 |
| :--- | :--- |
| 芯片型号 | `<910B3（A2/A3） \| 950PR / 950DT（A5 / arch35）>` |
| CANN 版本 | `<上机核对，如 9.x.x>` |
| torch_npu 版本 | `<pip show torch-npu>` |
| PyTorch 版本 | `<pip show torch>` |
| 驱动 HDK 版本 | `<npu-smi / dmesg 核对>` |
| npu-smi 版本 | `25.5.1`（评测服务器 10.19.93.115） |
| 服务器 / 拓扑 | `10.19.93.115`（SSH 端口 22022），8×910B3，HBM 64GB/卡；HCCL 卡间拓扑 |

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

- 端到端：`msprof --application="<命令>" --output=<路径>` → 产物 `<性能剖析文件路径>`。
- 算子微基准：`msprof op --application="python3 benchmark_op.py"` → 产物 `<msprof op 报告路径>`（`msprof op` 选项以本机 `msprof op -h` 为准，须上机核实）。
- 产物统一归档到 `cases/<case>/profiling/`，随 [PMR](../templates/pmr-log-template.md) 一并留存。

## 七、复测触发条件

- **换 CANN / torch_npu / PyTorch / 驱动 HDK 版本** → 必须复测并更新本台账。
- **换芯片版本（910B3 ↔ 950）** → 必须复测（UB 组织、SIMT、HiF8、CCU、msprof 指标均不同，见 §五）。
- 台账更新后，引用 `P_eff` / `BW_eff` 的任务书与门禁阈值须同步复算；复测需先跑通本台账的 §一 环境冻结记录。
