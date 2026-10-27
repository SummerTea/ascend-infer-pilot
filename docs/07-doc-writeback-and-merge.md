# 07 · 文档回写与合入纪律（docs / AGENTS.md）

> **定位**：执行中暴露的流程短板如何回写进 `docs/` 与 `AGENTS.md`，以及合入前必须满足的鲁棒性硬约束。
> **配套**：[AGENTS.md §10](../AGENTS.md)（一句话入口）｜ [docs/05 §3](05-case-library-and-ledger.md)（台账与 `summary.md` 的「文档缺口」清单）｜ [gates/README.md](../gates/README.md)（门禁口径，属自指规则）

---

## 1. 为什么要回写

流程只有在真机上跑过才知道哪里断。首个真机 J0 闭环（`workspace/1x910B3-qwen3-8b-triage/ledger/01-triage.md §5`）一轮就暴露 6 条：V1 容器可运行性未入齐备性、V2 profiler「假活」无排障指引、V3 R1 阶段占比无法从 timeline 直接读、V4 定位卡缺「负载定义」、V5 证据须申报采集配置、V6 端到端 `msprof --application` 将被废弃。

**第二轮真机核验（容器 CANN 9.0.0）补三条**：V6 已实测确认——端到端 `msprof` 的 `--application` 在 help 里标注 will be discarded（改用位置参数 `msprof --output=<dir> <app>`，实测可解析），而 `msprof op` 的 `--application` 仍是官方选项、与位置参数均可 → 回写 [docs/02](02-ascend-diagnosis-sop.md)、[docs/06](06-bottleneck-triage.md)、[校准台账](../templates/calibration-template.md)、[PMR 模板](../templates/pmr-log-template.md)。V7 容器内无 `npu-smi`（`command -v npu-smi` 为空）→ 回写 [docs/03 §2](03-ascend-hardware-and-engines.md)。V8 宿主整包缺 `msprof`（`source set_env.sh` 后 `command -v` 仍为空）→ 回写 docs/03 §2 与 [docs/05 §3](05-case-library-and-ledger.md)。

**不回写的两种失败**：

1. **只在台账私存** → 下一个 Agent 重踩同一个坑，且没人知道这个坑存在。
2. **默默绕开流程自行变通** → 流程失真：绕行后的真实做法没有记录，后续无法复算、无法审计。

## 2. 回写路径

```
台账记编号（V1..Vn：现象 / 命令 / 产物路径 / 失败原文）
  → summary.md 的「文档缺口」清单（V1..Vn：现象 + 实证 + 回写位置 + 已回写 / 待回写）
  → 定权威位置（同一规则只落一处）
  → 改一处 → 校验（见 §4）
  → 改动说明指明回写了哪条 V 编号
```

**未附真机实证的「文档推测」式改写一律不合入**——文档里的每条命令、路径、阈值都应能追到一次真实执行。

## 3. 合入鲁棒性硬约束（缺一不得合入）

1. **单一权威源**：同一判据 / 阈值 / 字段 schema 只允许写死一处，其余位置必须**引用带章节锚点的链接**，不得复制数字（`AGENTS.md §1.0` 硬出口 → [docs/06 §6](06-bottleneck-triage.md) 即此模式）。**改阈值只改权威处**。
2. **引用完整性**：改标题 / 章节号 / 文件名会打断 `docs/xx §n` 与相对链接。改后必须 `rg -n '<被改标题|旧文件名>' .` 全仓核对并逐个修好；**悬空锚点视为不合入**。
3. **不得静默放宽**：只允许补充 / 收紧。放宽阈值、删除红线、新增例外，必须在改动说明写明理由与影响面，并**由人确认**。
4. **向后兼容**：台账 9 项与 `state.json` 字段**只增不改名、不删**；新增字段必须带默认值（如 `blocked_on: null`），保证旧场景台账仍可读。文档新增章节时，旧章节号尽量不动（新增放末尾），避免打断全仓引用。
5. **一次一处、可回滚**：一处逻辑改动一个提交，禁止把未验证的推测与已验证的修正混在同一次提交；提交信息指明回写的 `V` 编号。
6. **连带面核对**：改 `docs/` 后逐一核对是否仍需指向该节——`AGENTS.md` §0 入口表 / §1 阶段表 / §1.5 台账链 / §7 路由表、[README.md](../README.md) 目录地图与文档导航、[gates/README.md](../gates/README.md)、[templates/](../templates/)。

## 4. 自指规则：Agent 只有提议权

以下三类是**给自己定规矩/定门禁**的规则，改动会直接影响 Agent 自身的可交付判定，**Agent 不得自行合入**：

| 类别 | 位置 |
| :--- | :--- |
| 五不准红线 | [AGENTS.md §5](../AGENTS.md) |
| 测量铁律（只信 msprof / 分母唯一） | [AGENTS.md §4](../AGENTS.md)、[docs/02 §2.1](02-ascend-diagnosis-sop.md) |
| 门禁口径与所有权（L1/L2/L3、探索态/验收态） | [gates/README.md](../gates/README.md) |

正确做法：在台账与 `summary.md` 留证 → 提出改动建议（含理由 / 影响面 / 替代方案）→ **等人批准后**再改。

## 5. 合入前检查清单

- [ ] 每条改动都能指到一次真机执行（命令 + 产物路径 / 失败原文）
- [ ] 数字与阈值未在新位置重复写死；新位置只引用权威处
- [ ] `rg` 全仓核对过被改的标题 / 章节号 / 文件名，无悬空引用
- [ ] 未放宽任何阈值 / 红线；如放宽，已取得人确认并写明影响面
- [ ] 台账与 `state.json` 只增字段、未改名未删字段；新字段有默认值
- [ ] `summary.md` 的「文档缺口」清单已把对应 V 编号标记为「已回写」
- [ ] 连带面（§0 / §1 / §1.5 / §7 / README / gates / templates）已核对
