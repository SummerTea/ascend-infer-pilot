# 05 · 案例库与台账规范（案例沉淀 + workspace 过程台账）

> **定位**：定义案例库（`cases/`，入库）与过程台账（`workspace/ledger/`，不入库）的规范——案例 md 结构、台账 8 项逐文件职责、workspace 落点与串行化约定。
> **配套**：[流水线与物理账本](01-pipeline-and-ledger.md)（J1→J6 决策流水线）｜ [门禁规则](../gates/README.md) ｜ [校准模板](../templates/calibration-template.md)
> **路径速记**：`workspace/optimized/`（plugins/kernels/tools）取代原 `src/` 落点；`workspace/source/<repo>/` 取代原引擎克隆目录；案例落点改为平铺 `cases/<case-id>.md` + `cases/index.md`；过程产物一律 `workspace/ledger/<case-id>/`（不入库）。

---

## 1. 案例库定位与入库纪律

**定位**：`cases/` 是全工程**入库、共享**的案例知识库，随根仓库版本化，供后续 Agent 复现、对比与复用；`cases/index.md` 是全仓可检索的索引。

**入库纪律（Agent 自主沉淀）**：

1. **仅「优化有效果且过验收态门禁」的案例入库**：入库门槛 = 轨道 A（相应档位 L1/L2/L3）与轨道 B（收益 / Goodput / 长稳）双轨通过，且环境冻结可复现（见 [门禁规则](../gates/README.md)）。
2. **由 Agent 自主沉淀**：不做脚手架、不做模板文件；案例验收通过后由 Agent 按 §2 规范直接写 `cases/<case-id>.md`，并同步更新 `cases/index.md`。
3. **失败 / 反向结果不入库**：以「反模式」写进案例 md 第 6 节（供他人规避），或就地记入 `workspace/ledger/<case-id>/summary.md` 的反模式清单；不占 `cases/index.md` 行位。
4. **交付物不入库**：patch、profiling、门禁产物一律留 `workspace/ledger/<case-id>/`（不入库）；案例 md 只写「关键 diff 摘录」与「证据路径引用」。
5. **一案例一个 md**：`cases/<case-id>.md`，`case-id` 全局唯一、与 `workspace/ledger/<case-id>/` 同名；一个案例跨多个模型 / 硬件时拆为多个 md。

---

## 2. 案例 md 规范（7 节）

### 2.1 总则

- 一个案例一个 md：`cases/<case-id>.md`（平铺，无子目录）。
- 7 节 = **元信息头 + 6 节**（背景 / 目标 / 诊断与归因 / 修改方案 / 验证方案与结果 / 复盘与可复用经验）。
- 必填项以「★必填」标注；其余允许「—」占位，但**禁止删除节**。

### 2.2 完整模板

```markdown
# 案例：<case-id>

## 元信息头（★必填）

| 字段 | 值 |
| :--- | :--- |
| case-id | `<唯一标识，如 910b3-<模型>-<瓶颈>-<方法>>` |
| 模型@硬件 | `<模型名>@<910B3 / 950PR / 950DT>` |
| 状态 | `<成功 / 部分>`（未达标 / 已回退案例不入库） |
| 日期 | `<YYYY-MM-DD>` |
| 引擎 + commit | `<引擎名 @ commit>`（改造前基线 commit 与改造后 commit 都要） |
| 配套版本 | `<CANN ↔ torch_npu ↔ PyTorch ↔ 驱动>`（与台账冻结指纹一致） |
| 硬件代际 | `<910B3（A2/A3）/ 950PR / 950DT（A5/arch35）>` |
| 干预阶梯 | `<1~5>`（可多个，按主次排序） |
| 关联台账路径 | `workspace/ledger/<case-id>/`（不入库） |

## 1. 背景（★必填）
<设备与并行形态、模型结构特征向量（注意力族 / 前馈形态 / 数值格式）、负载与 SLO、
  现象描述与相对 P_eff / BW_eff 的量化差距（如 BW_util = 42%）。>

## 2. 目标（★必填）
<可量化指标（相对 P_eff / BW_eff 表述）+ 可门禁判据（轨道 A/B 阈值）+ 约束边界
  （不动的模块、可接受副作用）。>

## 3. 诊断与归因（★必填）
<瓶颈类别：算 / 读 / 发 / 传；AI vs B* 判定；msprof 证据摘要（五表关键行：
  Kernel / 通信重叠 / 融合模式 / 下发效率 / 内存效率）。>

## 4. 修改方案
<所落阶梯与理由；被排除的更优 ROI 选项；关键 diff 摘录（完整 patch 在台账）；
  落点文件与接口（workspace/optimized/ 或 workspace/source/<engine>/）。>

## 5. 验证方案与结果（★必填）
<轨道 A：相应档位 L1/L2/L3 + 阈值 + 实测；轨道 B：相对基线收益 / 开环 Goodput / 边界 /
  长稳 / 回归抽检；前后对照表；可复现命令。>

## 6. 复盘与可复用经验
<预测 vs 实测偏差归因；可复用模式与反模式清单；缩放因子（回写
  workspace/ledger/_shared/calibration.md）；遗留问题。>
```

### 2.3 最小示例（占位符）

```markdown
# 案例：910b3-qwen2.5-7b-bwutil-fusedrope

## 元信息头

| 字段 | 值 |
| :--- | :--- |
| case-id | `910b3-qwen2.5-7b-bwutil-fusedrope` |
| 模型@硬件 | `Qwen2.5-7B@910B3` |
| 状态 | `成功` |
| 日期 | `<YYYY-MM-DD>` |
| 引擎 + commit | `vllm-ascend @ <commit>` |
| 配套版本 | `<CANN x.y ↔ torch_npu a.b.c ↔ PyTorch p.q ↔ 驱动 d.e.f>` |
| 硬件代际 | `910B3（A2/A3）` |
| 干预阶梯 | `4` |
| 关联台账路径 | `workspace/ledger/910b3-qwen2.5-7b-bwutil-fusedrope/` |

## 1. 背景
<8 卡 TP8，GQA 结构；离线预填负载 P50/P95 = <...>；实测 Decode BW_util = 42%（相对 P_eff/BW_eff 口径）。>

## 2. 目标
<Decode 单步 TPOT ≤ <X> ms；BW_util ≥ 75%；不触碰 KV 布局。>

## 3. 诊断与归因
<读受限（AI < B*）；五表「内存效率」行显示 KV write 与 RoPE 分离两次读 HBM；msprof 证据：<...>。>

## 4. 修改方案
<阶梯 4，AscendC 融合 RoPE + KV write 单 kernel；排除阶梯 2（无现成后端）；
  diff 摘录：<...>；落 workspace/optimized/kernels/fused_rope_kvwrite/。>

## 5. 验证方案与结果
<轨道 A：L2 余弦 + 最大误差在噪声底内；轨道 B：BW_util 42%→78%，TPOT <...>；
  对照表 + 复现命令。>

## 6. 复盘与可复用经验
<偏差归因：<...>；反模式：<...>；缩放因子 α = <...> 已回写 _shared/calibration.md；遗留：950 需重标。>
```

---

## 3. 台账规范（8 项）

> **位置**：`workspace/ledger/<case-id>/`（不入库、单份共享、按案例隔离）；`_shared/` 跨案例共享。
> **职责**：台账是**过程留痕**（决策依据与证据链），案例 md 是**沉淀结论**——两者互为引用，不重复。

| 文件 | 职责 | 关键字段 |
| :--- | :--- | :--- |
| `00-scope.md` | ① J1 目标四输入 + J1.5 gap + 停止判据 | 硬件上下文 / 模型结构特征向量 / 负载分布 / SLO 与目标指标；gap 清单（组件、引擎现状、需改动、源码落点、对应阶梯）；停止判据（达标即停 / 预算耗尽即停 / 物理不可达即停） |
| `01-probe.md` | ② 主机探测 + 模型源码探测 | **排除权重介质**（不下载 / 不搬运权重）；`npu-smi info` / 拓扑 / 工具版本；模型结构特征向量核对 |
| `02-baseline-ledger.md` | ③ J2 双约束账本 | `P_eff` / `BW_eff` / `B*`；Decode·Prefill 时间下界；显存容量账本（权重 / KV / 系统余量）；`MFU_eff` / `BW_util` 实测口径 |
| `03-freeze-and-gate.md` | ④ 环境冻结指纹 + 黄金参考 + 门禁口径 | CANN↔torch_npu↔PyTorch↔驱动版本快照 / 引擎 commit / 锁频；golden（transformers eager）；轨道 A（相应档位 L1/L2/L3）与轨道 B 的阈值与判据 |
| `04-bootstrap.md` | ⑤ 初始建议启动 | 首个假设与对应阶梯、预期收益、首轮实验命令 |
| `iterations/it-NNN.md` | ⑥ 每轮迭代记录 | 字段顺序见下 |
| `state.json` | ⑦ 轻量机器可读状态 | 字段清单见下 |
| `summary.md` | ⑧ 收尾结论 | best 结果 / ROI 成本收益 / 反模式清单 / 有效·无效·失败方法 / 是否沉淀 case |

**`iterations/it-NNN.md` 字段顺序（逐轮，按序记录）**：

1. 假设（本轮要验证的假设）
2. 对应阶梯 / 方法
3. 改动（文件 + 关键 diff）
4. **环境指纹**（本轮实际运行的配套版本 / 锁频 / commit）
5. `msprof` 命令 + 产物路径 + 五表摘录（Kernel / 通信重叠 / 融合模式 / 下发效率 / 内存效率）
6. 门禁 A/B 结果（轨道 A：相应档位 L1/L2/L3 实测；轨道 B：相对基线收益 / Goodput）
7. 结论方向：**正向 / 反向 / 无变化**
8. 决策：保留 / 回退 / 继续
9. 成本估计（人时 / 机时）
10. 下轮建议

**`state.json` 字段清单**：

```json
{
  "case": "<case-id>",
  "freeze": { "cann": "", "torch_npu": "", "pytorch": "", "driver": "", "engine_commit": "", "lock_freq_mhz": 0 },
  "best_metric": { "metric": "", "value": 0.0, "iteration": "it-NNN" },
  "iterations": [{ "id": "it-NNN", "hypothesis": "", "direction": "positive|negative|flat", "decision": "keep|revert|continue" }],
  "methods": { "effective": [], "ineffective": [], "failed": [] },
  "frontier": "<下一轮待探索假设>",
  "hypotheses": ["<待验证假设>"],
  "stop_reason": "achieved|budget_exhausted|physically_infeasible"
}
```

---

## 4. workspace 落点规范与串行化约定

> **结构**：`workspace/optimized/`（自研产物）｜ `workspace/source/<repo>/`（引擎克隆）｜ `workspace/ledger/<case-id>/`（过程台账）。`repos/refs/` 只读参考不变。

### 4.1 落点规范（由原 `src/README.md` 迁入）

- **`workspace/optimized/plugins/<engine>/<plugin_name>/`** —— 阶梯 3：out-of-tree 插件。基于 `vllm_ascend` / `vllm` 的 entry_points 机制外挂（新模型注册、自定义 QuantizationConfig、自定义 AttentionBackend）；插件须可独立安装 / 导入，**不得要求修改引擎源码**。
- **`workspace/optimized/kernels/<op_name>/`** —— 阶梯 4：独立算子工程（Triton-Ascend / AscendC / TileLang / PyPTO）。**每算子子目录强制包含**：实现文件（kernel 源码）+ `test_op.py`（单测，正确性校验）+ `benchmark_op.py`（`msprof op` 微基准）。
- **`workspace/optimized/tools/<tool_name>/`** —— 辅助工具：Golden logits 采集脚本、权重 `ND ↔ NZ` 离线重排（Repack）脚本、msprof 解析辅助工具。

**交付物落点军规**：

1. 阶梯 3/4 的产出**优先落 `workspace/optimized/`**：可独立构建、测试、随根仓库版本化。
2. 只有必须修改引擎源码才能实现的目标，才落 `workspace/source/<engine>/`，且必须用 `bash scripts/manage_repos.sh export-patch` 导出 patch 到 `workspace/ledger/<case>/patches/`（不入库），交付以 patch 为准。
3. `repos/refs/` 只读，任何改动都禁止。

### 4.2 串行化约定（单份共享 workspace）

1. **同一时刻只跑一个案例**：workspace 是单份共享目录，不建 git、不入库；并发实验会互相污染台账与 `optimized/` 产物。
2. **台账按 `case-id` 隔离**：每个案例独占 `workspace/ledger/<case-id>/`；严禁跨案例写对方台账。
3. **`_shared/calibration.md` 跨案例共享**：`P_eff` / `BW_eff` / α / β / 锁频命令 / 配套版本按 `<模型>@<硬件>` 分节，所有案例只读复用；复测由持卡人更新。

### 4.3 workspace 不入库说明

`workspace/` 整体**不入库、单份共享、暂不建 git**（与 `repos/` 的克隆仓策略相同，仅保留占位）；需要落库的内容以**案例 md**（`cases/<case-id>.md`）形态沉淀；补丁与 profiling 留 `workspace/ledger/<case>/patches/` 与 `workspace/ledger/<case>/profiling/`（均不入库）。
