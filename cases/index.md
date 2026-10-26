# cases/ —— 案例库索引

> **定位**：`cases/` 是**案例库**，收录**可复用技术条目**（entry），供全工程与后续 Agent 复现、对比与复用；`cases/<entry-id>.md` 一条目一个 md，本文件（`cases/index.md`）是全仓可检索的索引。
> **入库纪律**：仅「优化有效果且通过验收态门禁」的条目入库，由 **Agent 自主沉淀**（无脚手架、无模板文件）；失败 / 反向结果以「反模式」写进条目第 6 节或就地记入场景台账。规范见 [docs/05](../docs/05-case-library-and-ledger.md)。
> **形态**：一条目一个 md —— `cases/<entry-id>.md`（元信息头 + 6 节，**元信息头必填来源场景 `scenario-id`**）；交付物不入库（落 `workspace/<scenario-id>/ledger/`）。

| entry-id | 来源场景 | 模型@硬件 | 状态 | 干预阶梯 | 收益 | 日期 | 条目 |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `<entry-id>` | `<scenario-id>` | `<模型>@<硬件>` | `<成功 / 部分>` | `<1~5>` | `<相对 P_eff/BW_eff，如 BW_util 42%→75%>` | `<YYYY-MM-DD>` | `<cases/<entry-id>.md>` |

> **状态取值约定**：`成功`（达标且过双轨门禁）／`部分`（部分达标）。**未达标 / 已回退的失败条目不入库**，其教训以「反模式」写进条目第 6 节或记入 `workspace/<scenario-id>/ledger/summary.md`。
> **来源场景列**：从条目回溯现场——来源场景（`scenario-id`）对应的过程台账在 `workspace/<scenario-id>/ledger/`（不入库），一条目可有多个来源场景。
> **维护**：新增条目由沉淀 Agent 同步更新本表；本表是全仓可检索索引，检索不到即视为未入库。

## 入库流程（Agent 自主沉淀）

1. 条目双轨门禁（轨道 A：相应档位 L1/L2/L3；轨道 B：收益 / Goodput / 长稳）通过、环境冻结可复现后，按 [docs/05 §2](../docs/05-case-library-and-ledger.md) 写 `cases/<entry-id>.md`（元信息头 + 6 节）。
2. 在本表追加一行：`entry-id / 来源场景 / 模型@硬件 / 状态 / 干预阶梯 / 收益 / 日期 / 条目`。
3. 失败 / 反向结果**不占行位**——以「反模式」写进条目第 6 节，或就地记入 `workspace/<scenario-id>/ledger/summary.md`。

## 检索方式

- 按 `entry-id` / `来源场景` / `模型@硬件` / `状态` / `干预阶梯` 任一列过滤本表；条目全文可用 `rg -n '<关键词>' cases/`。
- 本目录只含 `index.md` 与平铺的 `cases/<entry-id>.md`（无子目录、无交付物）；交付物一律在 `workspace/<scenario-id>/ledger/`（不入库）。
