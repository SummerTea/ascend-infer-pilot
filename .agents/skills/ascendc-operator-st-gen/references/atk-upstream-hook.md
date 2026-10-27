# ATK 上游仓库 HOOK

当本 skill 的 `SKILL.md`、`references/`、`templates/` 与检验脚本仍无法解释或解决问题时，可升级到 **ATK 官方仓库** 继续查证。

## 仓库信息

| 项 | 值 |
|----|-----|
| 远程 | https://gitcode.com/AscendTest/ATK |
| 建议克隆目录 | `~/git/ATK` 或 `<workspace>/git/ATK` |
| 本机已有副本（若存在） | `/data/hey/git/tmp/ATK` |

## 触发条件（满足任一即可考虑 HOOK）

- ATK 版本新行为：命令行参数、日志字段、backend 名称与 skill 描述不一致
- 框架级 API：`atk.tasks.*`、`AclnnBaseApi`、`InputDataset` 行为需读源码
- 非 ST 算子插件问题：安装、环境、`atk` CLI 本身报错
- 用例类型超出 ST：`performance`、`stability`、集群 task 等未收录流程
- 用户明确说「查 ATK 文档/源码/官方仓库」

**不触发**：仅算子 kernel/tiling、pytest golden 逻辑——仍留在算子仓与 `tests/pytest/`。

## 征询流程（必须执行）

**在访问上游仓库之前，必须先征得用户同意。** 使用类似话术：

> 当前 skill 无法覆盖 \<具体问题\>。是否允许我访问 ATK 官方仓库继续排查？
> - 仓库：https://gitcode.com/AscendTest/ATK  
> - 方式：\<读取本机已有路径 / git clone / 仅浏览在线文档\>  
> 请确认是否继续，以及本机 ATK 路径（若有）。

用户回复后再行动：

| 用户答复 | Agent 行为 |
|----------|------------|
| 同意 + 提供本地路径 | 只读该路径下文件，优先 `ATK使用指南/` |
| 同意 + 无本地路径 | 询问是否执行 `git clone`，克隆后再读 |
| 拒绝 | 停止上游访问；说明 skill 边界，请用户补充日志/版本或自行查仓 |
| 仅给部分权限 | 严格按用户限定范围（例如只读 `examples/用例执行`） |

## 上游查阅优先级

1. `ATK使用指南/` — 与用户问题最相关的章节（扩展开发、用例执行、用例生成等）
2. `ATK使用指南/examples/` — 可运行样例与 JSON/CSV 字段
3. `atk/` 或包内 `atk/tasks/` — 仅当文档不足以解释行为时再读源码
4. 变更记录 / README — 确认 ATK 版本与 skill 副本是否过期

查阅后若官方文档更新，可将关键段落**摘要**回写到本 skill 的 `references/`（需用户同意改动 hey-skill 仓）。

## NEVER（上游 HOOK）

- ❌ 未经用户明确同意就 `git clone`、改远程配置或推送 ATK 仓
- ❌ 把 ATK 仓里的示例直接覆盖用户算子 ST 而不说明差异
- ❌ 因查上游而跳过用户规定的验收命令（含 `-cp`）
- ❌ 假设本机一定有 `/data/hey/git/tmp/ATK`；路径以用户确认为准
