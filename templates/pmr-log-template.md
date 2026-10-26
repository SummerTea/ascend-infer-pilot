# PMR 实验记录单（昇腾版）—— `<实验代号>` / `<日期>`

- 目标：`<在什么设备上什么模型，解决什么问题>`
- 当前基线：`<相对 P_eff / BW_eff 表述，如 BW_util = 42%，TPOT = 35ms>`
- 关联任务书：`<scenario-id / 任务书路径>`；校准依据：`<校准台账版本>`（见 [校准台账](../templates/calibration-template.md)）

## 1. 架构师事前预测（Predict）

| 填写项 | 内容 |
| :--- | :--- |
| 瓶颈定位假设 | 瓶颈是 X，理论依据（`AI` vs `B*` 判据 + msprof 归因）是 Y |
| 拟采取消除手段 | 干预阶梯 `<1~5>` |
| 预期收益预测 | `<相对 P_eff / BW_eff 表述，如 MFU_eff 0.45→0.65，TPOT 35→22ms>` |
| 预期风险与副作用 | `<如极短序列下 5% 启动开销>` |

## 2. 实验实测结果（Measure）

- **msprof 采集命令**：
  - 端到端：`<msprof --application="..." --output=/msprof_out/<scenario-id>/...>`
  - 算子微基准：`<msprof op --application="python3 benchmark_op.py">`（`msprof op` 选项以本机 `msprof op -h` 为准，须上机核实）
- **采集产物路径**：`<绝对路径 / workspace/<scenario-id>/ledger/profiling/...>`（不入库，随 PMR 一并归档）
- **实测最终数据**：`<相对 P_eff / BW_eff，如实测 TPOT = 26ms，BW_util = 63%>`
- **原瓶颈消除证据**：msprof 火焰图 / 五表（Kernel / 通信重叠 / 融合模式 / 下发效率 / 内存效率）摘录，说明原瓶颈 X 耗时下降比例。

## 3. 事后对齐复盘（Review）

- **预测偏差分析**：实测 vs 预测差多少，逐项归因（Kernel launch 间隙 / 非连续内存转换 / 未计入的 UB 冲突 / 动态 shape 回退…）。
- **经验沉淀**：此类特征在当前硬件（`910B3` / `950`）下**真实的缩放因子 = 多少**，写入 [校准台账](../templates/calibration-template.md)（落 `workspace/_shared/calibration.md`，不入库）供下次 J2 预测使用。

> 纪律：性能数据只信 `msprof` / `msprof op`，禁用 `time.time()`、`torch.npu.Event`、`do_bench`（见 [AGENTS.md](../AGENTS.md) §4）。
