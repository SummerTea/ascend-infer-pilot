---
name: ascend-msprof-diagnosis
description: 昇腾唯一可信测量的采集与归因技能——msprof timeline/op 采集、五表拆解、AICPU 排查、msprof-analyze 与 GPU↔NPU 对比、气泡定位，以及禁用 Python 侧计时的测量铁律。Use when the user wants to collect NPU profiles with msprof, run operator-level micro-benchmarks with msprof op, decompose bottlenecks via the five tables, investigate AICPU overhead, compare nsys GPU traces against NPU profiles, or identify launch bubbles; 中文触发：msprof 采集、算子耗时、瓶颈归因、五表、AICPU、气泡、GPU 对比 NPU。
---

# msprof 采集与瓶颈归因

昇腾侧性能评价**只信 `msprof` / `msprof op`**（设备侧硬件时间戳 + 计数器）。本技能覆盖 J3 基线归因的采集与拆解全流程，与 [docs/02 诊断 SOP](../../../docs/02-ascend-diagnosis-sop.md) 的 L2/L3 层探针一一对应。

## 触发

需要采集端到端 trace（`msprof` timeline）、算子级微基准（`msprof op`）、五表拆解（Kernel/通信重叠/融合模式/下发效率/内存效率）、排查 AICPU 算子暴露、做 GPU↔NPU 双 prof 对比（`msprof-analyze` 的 `calibrate_npu_gpu`）、或量化下发气泡 → 用本技能。

## 前置契约

- 工具不在默认 PATH：须先 `source /usr/local/Ascend/ascend-toolkit/set_env.sh`（含 `msprof` / `msprof-analyze`）。
- **评测跑在 Docker 容器内**（宿主无 torch），采集命令在容器内执行；产物落共享挂载卷或拷回 `/data`。
- 环境冻结：记录 CANN（本机 9.0.0-beta.1）/ torch_npu / 驱动（25.5.1）/ 引擎 commit；锁频后多轮数据才可比（`npu-smi set -t clock`，具体选项须上机核实）。
- 先跑最小探针确认硬件计数器可读（防假活环境），见下。

## 主流程

### 1. 最小探针（确认 profiler 真活）

```
source /usr/local/Ascend/ascend-toolkit/set_env.sh
# msprof op 以位置参数指定应用（官方示例：msprof op python3 test_xxx.py）
msprof op python3 -c "import torch, torch_npu; torch.npu.init(); torch.empty(1, device='npu:0')"
# --output / --application 等选项以本机 msprof op -h 为准（CANN 9.0.0-beta.1），须上机核实
```

**完成标准**：`/tmp/probe` 下生成 profile 产物且无权限/驱动报错；若失败先修权限与配套，不进入采集。

### 2. 端到端采集（L2 时序）

```
msprof --output=/tmp/llm_trace --application="python3 run_serve_or_step.py"   # 参数以 msprof --help 为准，须上机核实
```

**完成标准**：产物目录结构完整（含 timeline 数据），可用 MindStudio Insight 打开；采集覆盖 steady-state（跳过 warmup/首轮）。

### 3. 算子级微基准（L3 微架构）

```
msprof op python3 benchmark_op.py   # 位置参数形式；--output 等选项以本机 msprof op -h 为准（CANN 9.0.0-beta.1），须上机核实
```

**完成标准**：得到 Top-N 算子耗时/占比/有效带宽；`benchmark_op.py` 必须预热到稳态、输出张量显式零初始化（防 RMW 掩盖）。

### 4. 五表拆解（占比过滤 ≥ 1%）

产出五表：**Kernel**（Top-N 主核）、**通信重叠**（HCCL kernel 与计算轨道重叠度）、**融合模式**（融合算子是否生效）、**下发效率**（Host 下发 vs NPU 执行间隙）、**内存效率**（有效带宽与 `实际字节/bytes_min` 比值）。

**完成标准**：五表齐备，**过滤阈值 = 占比 ≥ 1%**（低于 1% 的算子不进入归因）；Top-N 主核累计覆盖总耗时 ≥ 80% 才有归因基础。

### 5. AICPU 排查

在 timeline/op 产物中过滤 AICPU 算子（控制 CPU 上的搬数/调度/同步），统计其暴露耗时。

**完成标准**：识别出 AICPU 算子名单与各自耗时占比；若 AICPU 占比显著，说明瓶颈在控制面而非 AI Core，归因方向改为下发/同步。

### 6. GPU↔NPU 双 prof 对比（迁移期专用）

```
msprof-analyze calibrate_npu_gpu --gpu-profile <nsys SQLite> --npu-profile <NPU profile>   # 子命令参数须上机核实
```

**完成标准**：自动比对 nsys SQLite 与 NPU profile 并产出对照报告（Excel/HTML），定位同一负载在 GPU 与 NPU 上的算子耗时差。

### 7. 气泡 / wait-anchor 定位

在 timeline 中按「NPU busy 区间并集」计算 `Bubble Ratio = NPU 完全空闲时长 / 窗口总时长`，并锚定空闲段的 wait 原因（等待同步 / 等待下发 / 等待通信）。

**完成标准**：Bubble Ratio 量化（负载打满前提），空闲原因归类；`> 20%` 为严重下发瓶颈。

## 关键命令与判定表

| 场景 | 命令 | 判定 |
| :--- | :--- | :--- |
| 端到端 trace | `msprof --output=<dir> --application="<cmd>"` | 产物可打开、覆盖稳态 |
| 算子微基准 | `msprof op python3 benchmark_op.py`（`--output`/`--application` 等选项以 `msprof op -h` 为准，须上机核实） | Top-N 主核占比、有效带宽 |
| 五表过滤 | — | **占比 ≥ 1%** 才进入归因；Top-N 覆盖 ≥ 80% |
| 下发气泡 | timeline 计算 Bubble | **> 20% 严重**（优秀 < 5%）；前提是负载打满 |
| 内存墙 | `msprof op` 有效带宽 | 带宽利用率 ≥ 75%~90% 且 `实际字节/bytes_min ≈ 1.0` 才是真带宽极限；比值 > 1 是未融合 |
| GPU↔NPU | `msprof-analyze calibrate_npu_gpu` | 出对照报告（参数须上机核实） |

## 测量铁律（为什么禁用 Python 侧计时）

| 计时方式 | 测得内容 | 为什么不可用于性能评价 |
| :--- | :--- | :--- |
| `time.time()` | Host 墙钟 | 含 Python 解释器开销、算子**下发（launch）延迟**、同步等待；毫秒级噪声淹没微秒级算子耗时 |
| `torch.npu.Event` | Host 侧事件时间戳差 | 事件在 Host 排队，测的是「端到端含发射间隙」而非设备侧纯执行时间；调度/图模式（npugraph_ex）下测值虚高或失真 |
| `do_bench` | Triton 系循环计时 | 面向 CUDA 生态（内部用 CUDA event），昇腾上无对应语义且同样含 Host 开销 |
| **`msprof` / `msprof op`** | **设备侧硬件时间戳 + 计数器** | AI Core/Cube/Vector 实际执行时间、有效带宽、占用率，**唯一可信口径** |

> Python 侧计时最多用于「量级粗判」，**不得**进入任何阈值判定与 J6 门禁（[门禁规则](../../../gates/README.md) §五 同样以 msprof 为唯一口径）。

## 常见坑

1. **忘了 `source set_env.sh`**：`msprof` / `msprof-analyze` 不在默认 PATH，直接调用报 `command not found`。
2. **用 `time.time()` / `torch.npu.Event` / `do_bench` 报性能**：全部含 Host 开销，口径不可信，J6 门禁直接打回。
3. **在宿主跑采集**：宿主无 torch / torch_npu，探针与评测必须进容器。
4. **五表不做 ≥1% 过滤**：把大量 <1% 的长尾算子纳入归因会稀释主核结论；先按占比排序取 Top-N。
5. **不锁频、不预热就采集**：多轮数据不可比；首次采集含 JIT/图捕获开销，必须预热到稳态再统计。
6. **把 ncu/nsys 的 CUDA 名词硬套 NPU**：昇腾无 CUDA event 语义，采集档位基线与优化版必须一致（同档位对比）。

## 关联

- 阈值与 SOP：[docs/02 诊断 SOP](../../../docs/02-ascend-diagnosis-sop.md)；环境前置：[ascend-910b-server](../ascend-910b-server/SKILL.md)
- 归因后写核：[ascend-kernel-optim](../ascend-kernel-optim/SKILL.md)；通信归因：[ascend-network-hccl](../ascend-network-hccl/SKILL.md)
- 门禁口径：[门禁规则](../../../gates/README.md)；`P_eff`/`BW_eff` 分母见 [calibration-template.md](../../../templates/calibration-template.md)
