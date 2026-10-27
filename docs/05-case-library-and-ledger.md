# 05 · 案例库与台账规范（条目沉淀 + workspace 场景台账）

> **定位**：定义「场景 vs 条目」两层体系、案例库（`cases/`，入库**条目**）与过程台账（`workspace/<scenario-id>/ledger/`，不入库）的规范——条目 md 结构、台账 9 项逐文件职责、workspace 场景工作区规范。
> **配套**：[流水线与物理账本](01-pipeline-and-ledger.md)（J0→J6 决策流水线）｜ [门禁规则](../gates/README.md) ｜ [校准模板](../templates/calibration-template.md)
> **路径速记**：场景 = `workspace/<scenario-id>/`（`source/` `optimized/` `ledger/` 三层）；条目 = `cases/<entry-id>.md` + `cases/index.md`；校准台账 `workspace/_shared/calibration.md`（不入库）。

---

## 0. 场景 vs 条目：两层定义与关系

**工作现场的「场景」与案例库的「条目」不是一回事，两个词不可混用**：

| 层 | 术语 | 定义 | 例 | 位置 |
| :--- | :--- | :--- | :--- | :--- |
| 工作现场 | **场景（scenario）** | 一次优化战役：硬件 × 模型 × 变体 × 主攻方向 | `2x910B-dsv41-flash-rocm-net` | `workspace/<scenario-id>/` |
| 可复用知识 | **条目（entry）** | 一个可复用技术条目（优化手段 / 缺陷修复 / 方法论） | `op-fusion` / `net-transfer-fusion` | `cases/<entry-id>.md`（`cases/` = 案例库，收录条目） |

**关系**：

1. **一个场景的迭代产出 0..N 个条目**：无效果 / 未过验收态门禁则 0 个；有效果且过门禁才沉淀。
2. **一个条目可被多个场景引用**：可复用技术不绑定单一现场，条目是共享知识。
3. **条目元信息头必须记录来源场景**（`scenario-id`，可多个），便于从条目回溯到现场台账。
4. **过程 vs 沉淀分离**：场景是过程留痕（`workspace/`，不入库），条目是入库结论（`cases/`，入库）。workspace 语境一律称「场景」（`scenario-id`），知识库语境一律称「条目」（`entry-id`）。

---

## 1. 条目库定位与入库纪律

**定位**：`cases/` 是全工程**入库、共享**的条目知识库（案例库），随根仓库版本化，供后续 Agent 复现、对比与复用；`cases/index.md` 是全仓可检索的索引。

**入库纪律（Agent 自主沉淀）**：

1. **仅「优化有效果且过验收态门禁」的条目入库**：入库门槛 = 轨道 A（相应档位 L1/L2/L3）与轨道 B（收益 / Goodput / 长稳）双轨通过，且环境冻结可复现（见 [门禁规则](../gates/README.md)）。
2. **由 Agent 自主沉淀**：不做脚手架、不做模板文件；条目验收通过后由 Agent 按 §2 规范直接写 `cases/<entry-id>.md`，并同步更新 `cases/index.md`。
3. **失败 / 反向结果不入库**：以「反模式」写进条目 md 第 6 节（供他人规避），或就地记入 `workspace/<scenario-id>/ledger/summary.md` 的反模式清单；不占 `cases/index.md` 行位。
4. **交付物不入库**：patch、profiling、门禁产物一律留 `workspace/<scenario-id>/ledger/`（不入库）；条目 md 只写「关键 diff 摘录」与「证据路径引用」。
5. **一条目一个 md**：`cases/<entry-id>.md`，`entry-id` 全局唯一；**通用技术族条目可被多个 模型@硬件 引用**；若同一技术在不同 模型@硬件 下**结论不同**，则拆为多个**实例化** md。

---

## 2. 条目 md 规范（7 节）

### 2.1 总则

- 一个条目一个 md：`cases/<entry-id>.md`（平铺，无子目录）。
- 7 节 = **元信息头 + 6 节**（背景 / 目标 / 诊断与归因 / 修改方案 / 验证方案与结果 / 复盘与可复用经验）。
- 必填项以「★必填」标注；其余允许「—」占位，但**禁止删除节**。
- **元信息头必填「来源场景」**（`scenario-id`，可多个）：记录条目产出的现场，台账见对应 `workspace/<scenario-id>/ledger/`。

### 2.2 完整模板

```markdown
# 条目：<entry-id>

## 元信息头（★必填）

| 字段 | 值 |
| :--- | :--- |
| entry-id | `<唯一标识>`：优先**通用技术族**（如 `op-fusion`、`net-transfer-fusion`，跨模型/硬件可复用）；结论强绑定特定 模型@硬件 时用**实例化式** `<硬件>-<模型>-<技术族>`（如 `910b3-qwen2.5-7b-fused-rope`）。**命名规则**：优先通用技术族；仅当结论强绑定某 模型@硬件 时才实例化 |
| 来源场景 | `<scenario-id>`（可多个，如 `2x910B-dsv41-flash-rocm-net`；过程台账在 `workspace/<scenario-id>/ledger/`，不入库） |
| 模型@硬件 | `<模型名>@<910B3 / 950PR / 950DT>` |
| 状态 | `<成功 / 部分>`（未达标 / 已回退条目不入库） |
| 日期 | `<YYYY-MM-DD>` |
| 引擎 + commit | `<引擎名 @ commit>`（改造前基线 commit 与改造后 commit 都要） |
| 配套版本 | `<CANN ↔ torch_npu ↔ PyTorch ↔ 驱动>`（与台账冻结指纹一致） |
| 硬件代际 | `<910B3（A2/A3）/ 950PR / 950DT（A5/arch35）>` |
| 干预阶梯 | `<1~5>`（可多个，按主次排序） |
| 关联台账路径 | `workspace/<scenario-id>/ledger/`（**按「来源场景」各列一条**；首个来源标记为**主场景**，不入库） |

## 1. 背景（★必填）
<设备与并行形态、模型结构特征向量（注意力族 / 前馈形态 / 数值格式）、负载与 SLO、
  现象描述与相对 P_eff / BW_eff 的量化差距（如 BW_util = 42%）。>

## 2. 目标（★必填）
<可量化指标（相对 P_eff / BW_eff 表述）+ 可门禁判据（轨道 A/B 阈值）+ 约束边界
  （不动的模块、可接受副作用）。>

## 3. 诊断与归因（★必填）
<瓶颈类别：算 / 读 / 发 / 传；AI vs B* 判定；msprof 证据摘要（五表关键行：
  Kernel / 通信重叠 / 融合模式 / 下发效率 / 内存效率）。>

## 4. 修改方案（★必填；纯方法论类条目可注明“不适用”）
<所落阶梯与理由；被排除的更优 ROI 选项；关键 diff 摘录（完整 patch 在台账）；
  落点文件与接口（workspace/<scenario-id>/optimized/ 或 workspace/<scenario-id>/source/<engine>/）。>

## 5. 验证方案与结果（★必填）
<轨道 A：相应档位 L1/L2/L3 + 阈值 + 实测；轨道 B：相对基线收益 / 开环 Goodput / 边界 /
  长稳 / 回归抽检；前后对照表；可复现命令。>

## 6. 复盘与可复用经验
<预测 vs 实测偏差归因；可复用模式与反模式清单；缩放因子（回写
  workspace/_shared/calibration.md）；遗留问题。>
```

### 2.3 最小示例（占位符）

```markdown
# 条目：910b3-qwen2.5-7b-fused-rope（实例化式示例：结论强绑定该 模型@硬件）

## 元信息头

| 字段 | 值 |
| :--- | :--- |
| entry-id | `910b3-qwen2.5-7b-fused-rope`（实例化式） |
| 来源场景 | `910b3-qwen2.5-7b-bwutil` |
| 模型@硬件 | `Qwen2.5-7B@910B3` |
| 状态 | `成功` |
| 日期 | `<YYYY-MM-DD>` |
| 引擎 + commit | `vllm-ascend @ <commit>` |
| 配套版本 | `<CANN x.y ↔ torch_npu a.b.c ↔ PyTorch p.q ↔ 驱动 d.e.f>` |
| 硬件代际 | `910B3（A2/A3）` |
| 干预阶梯 | `4` |
| 关联台账路径 | `workspace/910b3-qwen2.5-7b-bwutil/ledger/` |

## 1. 背景
<8 卡 TP8，GQA 结构；离线预填负载 P50/P95 = <...>；实测 Decode BW_util = 42%（相对 P_eff/BW_eff 口径）。>

## 2. 目标
<Decode 单步 TPOT ≤ <X> ms；BW_util ≥ 75%；不触碰 KV 布局。>

## 3. 诊断与归因
<读受限（AI < B*）；五表「内存效率」行显示 KV write 与 RoPE 分离两次读 HBM；msprof 证据：<...>。>

## 4. 修改方案
<阶梯 4，AscendC 融合 RoPE + KV write 单 kernel；排除阶梯 2（无现成后端）；
  diff 摘录：<...>；落 workspace/910b3-qwen2.5-7b-bwutil/optimized/kernels/fused_rope_kvwrite/。>

## 5. 验证方案与结果
<轨道 A：L2 余弦 + 最大误差在噪声底内；轨道 B：BW_util 42%→78%，TPOT <...>；
  对照表 + 复现命令。>

## 6. 复盘与可复用经验
<偏差归因：<...>；反模式：<...>；缩放因子 α = <...> 已回写 workspace/_shared/calibration.md；遗留：950 需重标。>
```

---

## 3. 场景台账规范（9 项）

> **位置**：`workspace/<scenario-id>/ledger/`（不入库、**每场景一份**、自包含、场景间并发安全）；`workspace/_shared/` 跨场景共享。
> **职责**：台账是**过程留痕**（决策依据与证据链），条目 md 是**沉淀结论**——两者互为引用，不重复。
> **工作流顺序**：`00-probe → 01-triage → 02-scope → 03-baseline-ledger → 04-freeze-and-gate → 05-bootstrap → loop: iterations/it-000-baseline（J3 基线归因）→ it-001..N（J4→J5→J6 微循环）→ summary.md`（**8 个顺序步不变**：`it-000-baseline` 只是 `iterations/it-NNN.md` 的首个实例，台账仍 9 项；`state.json` 随 loop 逐轮同步维护，不入顺序链）；**停止判据：达标即停 / 预算耗尽即停 / 物理不可达即停**；回边：J6 未达预期→回 J3；阶梯失败→回退上一阶梯；J2 物理不可达→回 J1 重谈 SLO；**J4/J5 无定位卡 → 回 J0**（细则以本文件为唯一权威）。

| 文件 | 职责 | 关键字段 |
| :--- | :--- | :--- |
| `00-probe.md` | ① **机器档案**（登录方式 / 卡型与数量 / HBM / 驱动 / CANN / 工具与 PATH 前提 / 容器与镜像 / 磁盘 / 模型·数据集落点）+ **服务器侧契约**（根路径 / 容器名 / 镜像 tag+image ID / 挂载映射 / 分配卡 / 同步方式）+ **本场景前置齐备性检查**（依赖 / 工具（远端 / 本机 Mac 两维）/ 环境 / 模型介质 → 具备 / 缺失 / 待确认）+ **模型源码探测**（`config.json` / `*.py` / 并行与量化配置 / 算子清单 / commit；**排除权重介质**）+ 与上次探测的**差异**（换机 / 换版本留痕） | 机器档案字段：登录方式（SSH 密钥 / 端口 / 账号 / 主机名）/ 卡型与数量、HBM 容量每卡、卡间拓扑 / 驱动、CANN 版本（取法：`cann/version.cfg` 或目录名）/ 工具与 PATH 前提（`source set_env.sh` 后 msprof / atc / hccl_test 才可用；宿主无 torch / torch_npu → 评测与采集一律进容器）/ 容器与镜像（镜像名与源）/ 磁盘（容量 / 已用 / 大文件落点）/ 模型·数据集落点（路径）；齐备性：依赖 / **工具（远端主机+容器 / 本机 Mac 两维）** / 环境（**容器内 NPU 可运行性**：最小 `msprof op` 探针通过）/ 模型介质（具备 / 缺失 / 待确认）；源码探测：**快照来源（仓库@revision / 抓取 glob / 落点 `model/`）** + `config.json` / `*.py` / 并行与量化配置 / 算子清单 / commit（**排除权重介质**）；**服务器侧契约**：服务器根路径 `/home/pilot/<scenario-id>/`（子目录镜像 Mac 侧：`source/` `optimized/` `ledger/`；宿主机临时 cwd 不入契约，profiling 证据落 `ledger/profiling/<triage-NN | it-NNN>/`）/ 容器名 `pilot-<scenario>` / 镜像 tag（人看）+ image ID（指纹用：`docker image inspect <tag> --format '{{.Id}}'`；本地构建镜像无 RepoDigests，故指纹取 image ID；实验前核对运行容器 `.Image` 与该值一致，不一致视为未按契约运行）/ 挂载映射（host → container，契约定后不可改）/ 模型·数据集（共享只读目录挂 `:ro`，场景内不复制）/ 分配卡列表（`ASCEND_RT_VISIBLE_DEVICES`，初始化时确认未被他人占用）/ 同步方式（rsync push|pull，时间戳记入 it-NNN 环境指纹）；差异：换机 / 换版本留痕 |
| `01-triage.md` | ② **J0 定焦**：三环记录（R1 阶段占比 / R2 类别与证据 / R3 落点与候选阶梯）+ **定位卡** | 关键字段：`负载定义 / 阶段 / 类别 / 证据（msprof 命令+指标值+采集配置）/ 占端到端比 / 候选阶梯 / 收益上限 / 置信度 / 未定项 / 熔断轮次记录 / 结论（四条件逐条 ✅❌）`；**硬出口四条件与 3 轮熔断见 `docs/06 §6/§7`** |
| `02-scope.md` | ③ J1 目标四输入（**围绕定位卡的焦点**）+ J1.5 gap + 停止判据 | 硬件上下文 / 模型结构特征向量 / 负载分布 / SLO 与目标指标；gap 清单（组件、引擎现状、需改动、源码落点、对应阶梯）；停止判据（达标即停 / 预算耗尽即停 / 物理不可达即停） |
| `03-baseline-ledger.md` | ④ J2 双约束账本 | `P_eff` / `BW_eff` / `B*`；Decode·Prefill 时间下界；显存容量账本（权重 / KV / 系统余量）；`MFU_eff` / `BW_util` 实测口径 |
| `04-freeze-and-gate.md` | ⑤ **本次实验的冻结指纹**（实际运行所用 CANN↔torch_npu↔PyTorch↔驱动 / 引擎 commit / 锁频 / 权重 hash / **`image_id`**（容器镜像 image ID——容器内 CANN 可能与宿主不同，指纹必须锚容器））+ 黄金参考 + 轨道 A/B 门禁口径阈值 | 每次实验核对并记录**实际**指纹，须与 `00-probe.md` 的机器档案 + 服务器侧契约一致，不一致要记原因；golden（transformers eager）；轨道 A（相应档位 L1/L2/L3）与轨道 B 的阈值与判据（**loop 前冻结创建、J6 验收时回填验收结论**） |
| `05-bootstrap.md` | ⑥ 初始建议启动 | 首个假设与对应阶梯、预期收益、首轮实验命令（首轮即基线轮 `it-000-baseline`） |
| `iterations/it-NNN.md` | ⑦ 每轮迭代记录（`it-000-baseline` = J3 基线归因，字段 3 / 6 / 8 填「—（基线）」；其余轮承载 J4→J5→J6 微循环） | 字段顺序见下 |
| `state.json` | ⑧ 轻量机器可读状态 | 字段清单见下 |
| `summary.md` | ⑨ 收尾结论 | best 结果 / ROI 成本收益 / 反模式清单 / 有效·无效·失败方法 / 是否沉淀条目（entry-id）/**文档缺口清单**（`V1..Vn`：现象 + 实证 + 回写位置 + 已回写/待回写；纪律见 [docs/07](07-doc-writeback-and-merge.md)） |

> **分工原则**：`00-probe.md` 的机器档案 = **机器「有什么」**（相对稳定，换机 / 换版本才变）；`04-freeze-and-gate.md` = **本次实验「冻结在什么」**（每次实验核对并记录**实际**指纹，须与机器档案一致，不一致要记原因）；`01-triage.md` 是 **J1 的前置闸门**（无定位卡不进 J1 / J4 / J5）。

> **J5 任务书落点**：`workspace/<scenario-id>/ledger/specs/spec-it-NNN.md`（按 [任务书模板](../templates/task-spec-template.md) 填写；**附属交付**，不占 9 项名额，随对应 `it-NNN` 归档）。[PMR 模板](../templates/pmr-log-template.md) 是 `iterations/it-NNN.md` 的**内容骨架**（Predict / Measure / Review 对应字段 1~2 / 5~6 / 10），**不另建文件**。

**`iterations/it-NNN.md` 字段顺序（逐轮，按序记录）**：

1. 假设（本轮要验证的假设）
2. 对应阶梯 / 方法
3. 改动（文件 + 关键 diff）
4. **环境指纹**（本轮实际运行的配套版本 / 锁频 / commit / **镜像 image ID** / **sync 时间戳**）
5. `msprof` 命令 + 产物路径 + 五表摘录（Kernel / 通信重叠 / 融合模式 / 下发效率 / 内存效率）
6. 门禁 A/B 结果（轨道 A：相应档位 L1/L2/L3 实测；轨道 B：相对基线收益 / Goodput）
7. 结论方向：**正向 / 反向 / 无变化**
8. 决策：保留 / 回退 / 继续
9. 成本估计（人时 / 机时）
10. 下轮建议

**`state.json` 字段清单**：

```json
{
  "scenario": "<scenario-id>",
  "freeze": { "cann": "", "torch_npu": "", "pytorch": "", "driver": "", "engine_commit": "", "image_id": "", "lock_freq_mhz": 0 },
  "best_metric": { "metric": "", "value": 0.0, "iteration": "it-NNN" },
  "iterations": [{ "id": "it-NNN", "hypothesis": "", "direction": "positive|negative|flat", "decision": "keep|revert|continue" }],
  "methods": { "effective": [], "ineffective": [], "failed": [] },
  "frontier": "<下一轮待探索假设>",
  "hypotheses": ["<待验证假设>"],
  "stop_reason": "achieved|budget_exhausted|physically_infeasible",
  "resume_from": "<阶段@台账文件，如 J5@04-freeze-and-gate.md>",
  "blocked_on": null
}
```

| 字段 | 说明 |
| :--- | :--- |
| `resume_from` | **断点续跑入口**：下一动作（阶段 + 台账文件）；每轮 loop 结束与每阶段切换后同步更新，接手者据此恢复现场，不重跑已过门禁的阶段 |
| `blocked_on` | **人机等待**：非阻塞为 `null`；阻塞时为 `{"reason": "review|permission|input|slo", "what": "<缺什么，要谁给>", "asked_at": "<YYYY-MM-DD>"}`。非 `null` 期间不得重复重试同一动作（`permission` / `input` / `slo` 见 [docs/06 §7](../docs/06-bottleneck-triage.md) 升级四类原因；`review` 指 [AGENTS.md §6](../AGENTS.md) 的方案评审与门禁闸门） |

---

## 4. 场景工作区规范（workspace）

> **结构**：`workspace/<scenario-id>/optimized/`（自研产物）｜ `workspace/<scenario-id>/source/<repo>/`（引擎克隆）｜ `workspace/<scenario-id>/ledger/`（过程台账）。`repos/refs/` 只读参考不变。

### 4.1 落点规范（由原 `src/README.md` 迁入）

- **`workspace/<scenario-id>/model/`** —— **模型配置快照（只读）**：仅 `config.json` / `generation_config.json` / `modeling_*.py` / `configuration_*.py` / `quantize_config.json` / `tokenizer*`；**禁止权重实例**（`*.safetensors` / `*.bin` / `*.pt` / `*.gguf`）。来源须 pin `--revision <commit>` 并登记到 `00-probe.md` 源码探测段（见 §3）；供 J1 特征向量、J1.5 盘点与 golden 脚本编写；**不 push 到主机**（容器用 `<共享模型目录>:/model:ro`），也不作为交付物。
- **`workspace/<scenario-id>/optimized/plugins/<engine>/<plugin_name>/`** —— 阶梯 3：out-of-tree 插件。基于 `vllm_ascend` / `vllm` 的 entry_points 机制外挂（新模型注册、自定义 QuantizationConfig、自定义 AttentionBackend）；插件须可独立安装 / 导入，**不得要求修改引擎源码**。
- **`workspace/<scenario-id>/optimized/kernels/<op_name>/`** —— 阶梯 4：独立算子工程（AscendC / TileLang / PyPTO；Triton-Ascend 仅了解/排错，不作实现路线）。**每算子子目录强制包含**：实现文件（kernel 源码）+ `test_op.py`（单测，正确性校验）+ `benchmark_op.py`（`msprof op` 微基准）。
- **`workspace/<scenario-id>/optimized/tools/<tool_name>/`** —— 辅助工具：Golden logits 采集脚本、权重 `ND ↔ NZ` 离线重排（Repack）脚本、msprof 解析辅助工具。

**交付物落点军规**：

1. 阶梯 3/4 的产出**优先落 `workspace/<scenario-id>/optimized/`**：可独立构建、测试；**交付以条目 md（`cases/`）沉淀**（`workspace/` 整体不入库）。
2. 只有必须修改引擎源码才能实现的目标，才落 `workspace/<scenario-id>/source/<engine>/`，且必须用 `bash scripts/manage_repos.sh export-patch <engine> --scenario <scenario-id>` 导出 patch 到 `workspace/<scenario-id>/ledger/patches/`（不入库），交付以 patch 为准。
3. `repos/refs/` 只读，任何改动都禁止。

### 4.2 场景隔离与并发

1. **每场景独立一套 `workspace/<scenario-id>/{source,optimized,ledger}`**：`source/` 与 `optimized/` 按场景隔离，台账按 `scenario-id` 隔离；**场景之间可并发，互不污染**。
2. **严禁跨场景写对方目录**：只读自己的 `workspace/<scenario-id>/`，避免并发写同一份 `source/` / `optimized/` / `ledger/`。
3. **唯一共享是 `workspace/_shared/calibration.md`**：`P_eff` / `BW_eff` / α / β / 锁频命令 / 配套版本按 `<模型>@<硬件>` 分节，所有场景只读复用；**只追加新分节，避免并发写同一段**；**同一 `<模型>@<硬件>` 分节由持卡人独占更新，场景不得并行写同 key**；复测由持卡人更新。

### 4.3 workspace 不入库说明

`workspace/` 整体**不入库、暂不建 git**（与 `repos/` 的克隆仓策略相同，仅保留占位）；需要落库的内容以**条目 md**（`cases/<entry-id>.md`）形态沉淀；补丁与 profiling 留 `workspace/<scenario-id>/ledger/patches/` 与 `workspace/<scenario-id>/ledger/profiling/`（均不入库）。
