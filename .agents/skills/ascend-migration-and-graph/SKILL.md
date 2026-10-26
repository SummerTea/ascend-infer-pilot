---
name: ascend-migration-and-graph
description: CUDA→torch_npu 迁移与图模式断图修复技能——迁移速查（.cuda()→.npu() 等）、CANN↔torch_npu↔PyTorch↔驱动严格配套核验、GE/npugraph_ex/TorchAir 图模式断图定位、msprobe 精度比对。Use when the user wants to migrate CUDA code to torch_npu, verify the CANN/torch_npu/PyTorch/driver compatibility matrix, fix graph-mode (GE / npugraph_ex / TorchAir) graph breaks, or compare precision with msprobe dump; 中文触发：CUDA 迁移、torch_npu、配套版本、图模式、断图、npugraph_ex、TorchAir、msprobe、精度比对。
---

# CUDA→torch_npu 迁移与图模式断图修复

对应昇腾接入的「J1 前置」：环境配套与迁移。**配套版本是本技能最高风险点**——CANN（本机 9.0.0-beta.1）↔ torch_npu ↔ PyTorch ↔ 驱动（HDK 25.5.1）严格对应，不可混装；换任一版本必须重跑校准与复测（[AGENTS.md](../../../AGENTS.md) 红线）。

## 触发

把 CUDA 代码迁到昇腾（`.cuda()` → `.npu()`、算子替换、stream/同步语义差异）、核验 CANN/torch_npu/PyTorch/驱动配套表、图模式（GE / `npugraph_ex` / TorchAir）断图定位、或做 `msprobe` 跨平台精度比对 → 用本技能。

## 前置契约

- 工具在容器内（宿主无 torch / torch_npu）；`msprobe`、`atc` 等不在默认 PATH，先 `source /usr/local/Ascend/ascend-toolkit/set_env.sh`。
- 配套表以 `migration-ascend-torchnpu-skills-environment-setup` 类配套表为准，**不可混装**；本机实测 CANN 9.0.0-beta.1 / 驱动 25.5.1 / Ubuntu 24.04。
- 图模式（GE / `npugraph_ex` / TorchAir）录制前提：**静态 shape、静态显存地址（预分配 buffer 用 `copy_()` 更新）、预热、捕获期无 GPU/NPU-CPU 同步、无动态分配、无动态控制流**。

## 主流程

### 1. 迁移速查（机械替换 + 语义核对）

```
.cuda()            → .npu()
device='cuda'      → device='npu'
torch.cuda.*       → torch.npu.* 对应项（如 torch.npu.init()）
cudaStream/Event   → 昇腾 stream/事件语义（API 名须上机核实，勿机械等价）
```

**完成标准**：源码无 `cuda` 残留；stream/同步语义差异逐处核对（昇腾异步发射语义与 CUDA 不同，热路径同步是五不准红线 1）。

### 2. 配套版本核验（防混装）

```
source /usr/local/Ascend/ascend-toolkit/set_env.sh
ls -l /usr/local/Ascend/cann                 # → cann-9.0.0-beta.1
cat /usr/local/Ascend/driver/version.info    # Version=25.5.1 / ascendhal_version=7.35.23
python3 -c "import torch, torch_npu; print(torch.__version__, torch_npu.__version__)"   # 在容器内
```

**完成标准**：CANN / torch_npu / PyTorch / 驱动四者落在配套表内；`import torch, torch_npu` 成功且版本可打印。**注意** `latest/version.cfg` 为空文件，勿靠它取版本。

### 3. 图模式接入与断图定位

- 触发图模式：`npugraph_ex`（昇腾图捕获）或 TorchAir / GE 路径（入口与配置项以引擎/框架文档为准，须上机核实）。
- 断图定位：`TORCH_LOGS=graph_breaks` 查 graph break 点（对应昇腾侧日志机制，等效手段须上机核实）；在 timeline 中找 NPU-CPU 同步点。

**常见断图原因**：

| 原因 | 定位 |
| :--- | :--- |
| GPU/NPU-CPU 同步 | `.item()` / `.cpu()` / `torch.nonzero()` / 基于张量结果的 Python `if`（红线 1） |
| 动态 shape | 输入/中间张量 shape 随 batch/seq 变化 → 分档静态最大网格捕获 |
| 动态控制流 | 捕获期出现数据相关分支 → 重构为静态分支/桶 |
| 未 support 算子 | 昇腾算子缺 graph 支持 → 替换为 torch_npu 融合算子或自研 kernel |

**完成标准**：定位到具体断图原因并给出修复动作；修复后图可稳定录制，replay 不触发重捕获。

### 4. msprobe 精度比对（dump → 比对 → 可视化）

```
msprobe dump --output=/tmp/probe_dump <运行命令>     # 子命令参数以 msprobe --help 为准，须上机核实
```

**完成标准**：dump 出中间张量，与 golden（transformers eager / CUDA 侧）比对，输出精度比对报告（可视化）；定位到首个偏差张量/算子，作为 J6 轨道 A 的输入证据。

## 关键命令与判定表

| 检查项 | 命令 | 判定 |
| :--- | :--- | :--- |
| 配套核验 | `ls -l /usr/local/Ascend/cann` + `cat /usr/local/Ascend/driver/version.info` + 容器内 import 版本 | 四者落在配套表内 |
| 图断点 | `TORCH_LOGS=graph_breaks`（昇腾等效手段须上机核实） | 定位断图行 |
| 精度比对 | `msprobe dump` → 与 golden 比对 | 首个偏差张量定位 |
| 迁移残留 | `rg -n 'cuda|CUDA' <迁移目录>` | 零命中 |

## 常见坑

1. **配套混装**：CANN / torch_npu / PyTorch / 驱动任一版本错配即出现诡异的 import 失败或 profiler 不可读；严格按配套表。
2. **拿 `latest/version.cfg` 取版本**：该文件为空；用 `cann/version.cfg` 或目录名（`cann-9.0.0-beta.1`）。
3. **机械平移 CUDA stream/Event 语义**：昇腾的异步发射与同步语义与 CUDA 不同，`torch.npu.Event` 计时在调度/图模式下失真且禁用（[测量铁律](../../../docs/02-ascend-diagnosis-sop.md)）。
4. **图捕获期有动态分配/同步**：热路径 `.item()`、`torch.nonzero()`、动态 shape 都导致断图；先分档静态化再捕获。
5. **把迁移等价性当正确性**：「改造前后对比」只证明没变；正确性必须锚定独立 golden（J1.5 纪律），并用 `msprobe`/L2 双指标核验。
6. **msprobe 参数照抄旧文档**：子命令与参数随 CANN 版本变动，以 `msprobe --help` 为准（须上机核实）。

## 关联

- 迁移配套纪律与 J1.5 黄金参考：[docs/01 流水线与物理账本](../../../docs/01-pipeline-and-ledger.md)；测量铁律：[docs/02 诊断 SOP](../../../docs/02-ascend-diagnosis-sop.md)
- 图/算子后端挂载（接引擎侧）：[vllm-ascend-adapter](../vllm-ascend-adapter/SKILL.md)；精度门禁：[门禁规则](../../../gates/README.md)
- 环境前置：[ascend-910b-server](../ascend-910b-server/SKILL.md)；红线见 [AGENTS.md](../../../AGENTS.md) §5
