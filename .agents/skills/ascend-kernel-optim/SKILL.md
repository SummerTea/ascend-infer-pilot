---
name: ascend-kernel-optim
description: 昇腾算子开发与审查技能——UB 预算核算、AscendC/Triton-Ascend/TileLang-Ascend/CATLASS 选型与陷阱、P0-P2 代码审查、mssanitizer 检查、test_op.py + benchmark_op.py 交付。Use when the user wants to write or port an Ascend operator (AscendC, Triton-Ascend, TileLang-Ascend, CATLASS), budget the 910B UB capacity, review an operator for correctness/performance defects, run mssanitizer checks, or deliver a kernel with correctness and msprof op benchmarks; 中文触发：写昇腾算子、AscendC、UB 预算、Triton 昇腾、TileLang、CATLASS、算子审查、mssanitizer。
---

# 昇腾算子开发与审查（阶梯 4）

针对 J4 阶梯 4「专用 Kernel 移植与开发」的算子实现、审查与交付。**动手前必读** [AGENTS.md](../../../AGENTS.md) §5 五不准红线与 [任务书模板](../../../templates/task-spec-template.md)（两阶段交付、方案评审先行）。参考实现一律读 `repos/refs/<repo>/`（只读），交付落 `src/kernels/`。

## 触发

生态确无现成实现、需要写/移植算子（非标头维 MLA、垂直融合、访存重排）→ 用本技能；评审 Agent 交来的算子代码（P0/P2 分级）、跑 `mssanitizer`、或出 `test_op.py` + `benchmark_op.py` 交付物，同样用本技能。

## 前置契约

- 环境：容器内有 CANN（本机 **9.0.0-beta.1**）+ torch_npu + 编译器工具链（`bisheng` / AscendC 相关工具，具体包名须上机核实）；测量用 `msprof op`（先 `source set_env.sh`）。
- 参考底座：`repos/refs/pto-kernels/`（A2A3 910B / A5 950 双代参考）、`repos/refs/catlass/`（Cube/Vector 矩阵乘模板库）、`repos/refs/cann-recipes-infer/`（推理优化典型样例）——先 `bash scripts/manage_repos.sh clone <name>`。
- **910B 硬件边界**：UB = **16 group × 3 × 4KB = 192KB/核**（950 为 8 group × 2 × 16KB，Bank 规则重写，**不得沿用 910B 规划**）。

## 主流程

### 1. 读参考实现（J4 前先读再算）

在 `repos/refs/` 找同结构参考（数据布局、向量化载入、Tiling 逻辑）。

**完成标准**：能说出参考实现的 UB/Tile 划分与边界处理，并明确本次定制的差异点（否则不应启动阶梯 4）。

### 2. UB 预算核算

按 910B 的 `16 group × 3 × 4KB = 192KB/核` 规划 Tile：主算 Buffer + 双缓冲 + 标量/搬数 buffer 合计**不得超过 192KB/核**；非整除 Tile 必须预留边界处理（mask/拷贝）。

**完成标准**：写出 `输入 Buffer + 输出 Buffer + 双缓冲副本 + 临时` 的字节账目，总占用 ≤ 192KB/核且有安全边际。

### 3. 选型 DSL

| 候选 | 适用 | 要点 |
| :--- | :--- | :--- |
| **AscendC** | 底层算子、达芬奇 Cube/Vector 异构模型 | 双缓冲流水、`__ubuf__` 组织、精度与边界显式控制 |
| **Triton-Ascend** | 从 Triton 迁移/快速原型 | **`num_warps`/`num_stages` 在昇腾不可用**；核类型须匹配（详见陷阱表） |
| **TileLang-Ascend** | 高级 Tile 编程、编译器 Pass 直达 | 仓库分支 `ascendc_pto`（`repos/targets/tilelang-ascend/`）；`tilelang-perf-optimization` 强制 `msprof op` 度量 |
| **CATLASS** | 矩阵乘模板库 | **非 CUTLASS 移植**（达芬奇 Cube/Vector 异构模型不同） |

**完成标准**：选定一种并给出理由（结构匹配/生态成熟度/维护成本），在任务书中声明落点。

### 4. 编码与 P0-P2 自查

对照审查分级逐条自查（下表），修正后再提交。

**完成标准**：P0 项零残留；P1/P2 项全部说明处置；五不准红线未命中。

### 5. mssanitizer 检查

```
mssanitizer --check=memcheck,racecheck,initcheck,synccheck --output=/tmp/san <运行命令>   # 子命令参数以 --help 为准，须上机核实
```

**完成标准**：memcheck（越界/未初始化）/ racecheck（数据竞争）/ initcheck（初始化顺序）/ synccheck（同步语义）四项通过或问题清单清零。

### 6. 交付物：test_op.py + benchmark_op.py

- `test_op.py`：覆盖规整 shape + 非对齐边界 shape（非 128 对齐、Batch=1、极端短/长序列）；余弦 + 最大/相对误差**双指标**，阈值按 [门禁规则](../../../gates/README.md) L2 档。
- `benchmark_op.py`：用 `msprof op` 出微基准与 UB/带宽利用率，对比基线加速比。

**完成标准**：L2 双指标在噪声底内；`msprof op` 报告有效带宽/加速比；J6 轨道 B 按 [门禁规则](../../../gates/README.md) 验收。

## 关键命令与判定表

| 主题 | 命令/工具 | 判定 |
| :--- | :--- | :--- |
| 算子微基准 | `msprof op --output=<dir> --application="python3 benchmark_op.py"` | 报耗时/有效带宽/加速比 |
| 审查分级 | — | P0 零容错；P1 必须修；P2 建议修（下表） |
| 精度门禁 | `torch.testing.assert_close(actual, expect, rtol=..., atol=...)` | 余弦 + 最大/相对误差双指标 |
| 越界/竞争 | `mssanitizer --check=memcheck,racecheck,initcheck,synccheck` | 四项通过 |

**P0/P1/P2 审查分级**：

| 级 | 内容 | 处置 |
| :--- | :--- | :--- |
| **P0** | 非整除 Tile 下 `mask=` 缺失/错位导致越界或静默错值；访存偏移越界 | 零容错，直接打回 |
| **P1** | 低精度累加（`tl.sum(x_fp16)` 默认保持输入精度，必须 `tl.sum(x.to(tl.float32))`）；核类型错配；热路径隐式同步 | 必须修 |
| **P2** | 双 pass 反模式（可慢 5×）、Tile/wave 量化、UB 流水编排、`num_warps`/`num_stages` 误用 | 建议修（性能向） |

## 常见坑

以下为 Triton-Ascend 陷阱要点（详见审查分级 P1/P2 栏）：

1. **`num_warps` / `num_stages` 在昇腾不可用**：这两个 Triton 参数在 Ascend 路径无对应语义，误设不生效或报错；改用 AscendC 双缓冲/Tile 参数表达流水。
2. **核类型错配**：算子被分派到错误的核（Cube vs Vector），性能断崖式下降——审查 kernel 声明与调用处的核类型匹配。
3. **归约升精度缺失**：`tl.sum`/`tl.reduce` 对 fp16/bf16 输入默认保持输入精度累加（红线 4），必须显式 `tl.sum(x.to(tl.float32), axis=...)`；`tl.dot` 默认 fp32 累加无此问题。
4. **双 pass 反模式**：同一数据流拆成两个 kernel 反复读写 HBM，实测可慢 5×——优先垂直融合为单次 launch。
5. **把 910B 的 UB/Bank 规划平移给 950**：950 是 `8 group × 2 × 16KB`，Bank 冲突规则重写；950 场景先仿真（cannsim 仅支持 950）再上真机。
6. **访存边界只测规整 shape**：红线 5（测试弱化）；必须覆盖非 128 对齐、Batch=1、极端短/长序列。

## 关联

- 落点与红线：[AGENTS.md](../../../AGENTS.md) §2/§5；任务书两阶段交付：[task-spec-template.md](../../../templates/task-spec-template.md)
- 参考实现：`repos/refs/pto-kernels/`、`repos/refs/catlass/`、`repos/refs/cann-recipes-infer/`（只读，[manifest.yaml](../../../repos/manifest.yaml)）
- 测量与门禁：[ascend-msprof-diagnosis](../ascend-msprof-diagnosis/SKILL.md)、[门禁规则](../../../gates/README.md)；代际差异见 [docs/03 硬件与引擎](../../../docs/03-ascend-hardware-and-engines.md)
