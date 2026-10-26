# src/ —— 本工程自有源码（根仓库直接跟踪）

`src/` 是昇腾推理优化工程的自研 out-of-tree 代码落点：插件、算子、工具。
与 `repos/`（外部仓库，各子目录独立 .git）不同，`src/` 下所有文件直接受根仓库
跟踪，可随工程版本化、独立构建与测试。

## 目录组织

### src/plugins/ —— 阶梯 3：out-of-tree 插件

遵循"不侵入引擎主干"原则，基于 `vllm_ascend` / `vllm` 的 entry_points 机制外挂：

- 新模型注册（Model Registry）
- 自定义 QuantizationConfig
- 自定义 AttentionBackend

落点规范：`src/plugins/<engine>/<plugin_name>/`，插件须可独立安装 / 导入，
不得要求修改引擎源码。

### src/kernels/ —— 阶梯 4：独立算子工程

技术栈：Triton-Ascend / AscendC / TileLang / PyPTO。
**每个算子子目录强制包含**：

- 实现文件（kernel 源码）
- `test_op.py`：单测（正确性校验）
- `benchmark_op.py`：`msprof op` 微基准

落点规范：`src/kernels/<op_name>/`。

### src/tools/ —— 辅助工具

- Golden logits 采集脚本（离线比对算子 / 引擎输出）
- 权重 `ND ↔ NZ` 离线重排（Repack）脚本
- msprof 解析辅助工具

落点规范：`src/tools/<tool_name>/`。

## 交付物落点军规

1. 阶梯 3/4 的产出**优先落在 `src/`**：可独立构建、测试、随根仓库版本化。
2. 只有必须修改引擎源码才能实现的目标，才落 `repos/targets/<engine>/`，
   且必须用 `scripts/manage_repos.sh export-patch` 导出 patch 到
   `cases/<case>/patches/`，交付以 patch 为准。
3. `repos/refs/` 只读，任何改动都禁止。

## 与任务模板的呼应

本文件与 `templates/task-spec-template.md` 的"目标源码落点"字段一一对应：
任务规划时应显式指明产出落在 `src/plugins|kernels|tools` 的哪个子目录，
还是 `repos/targets/<engine>/`（并附 patch 导出计划）。

## 目录占位说明

`plugins/`、`kernels/`、`tools/` 各放一个 `.gitkeep` 占位，保证空目录也能被
git 跟踪；首个文件落地后可按需删除对应 `.gitkeep`。
