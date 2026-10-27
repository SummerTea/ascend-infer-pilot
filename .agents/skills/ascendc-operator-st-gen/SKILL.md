---
name: ascendc-operator-st-gen
description: 为昇腾 CANN 算子创建或修正 ATK ST 双标杆精度工程。当用户提到 ATK ST、aclnn ST、pyaclnn、双标杆、atk case、atk task、smoke_case.json、自定义执行方式、-cp 签名、cv_fused_double_benchmark 时使用；不足时可经用户同意查阅 AscendTest/ATK 官方仓；不修改算子 kernel/tiling。
---

# ATK 算子 ST（创建 / 修正）

**边界**：只改 `tests/st/aclnn<OpName>/`，不改算子实现。目标：cpu + pyaclnn 双标杆 `accuracy` 通过（含用户给出的 **`-cp`**）。

## ATK 上游 HOOK

skill 覆盖 ST 工程搭建与常见排错；**框架行为、版本差异、非 ST 任务** 超出范围时，启用上游 HOOK：

1. **先说明缺口**（skill/references 已尝试过什么、仍缺什么）。
2. **征询用户**是否访问官方仓 [AscendTest/ATK](https://gitcode.com/AscendTest/ATK)。
3. **用户同意后再访问**。

**MANDATORY**：未获用户明确同意前，**不要** clone、不要读用户未指定的 ATK 路径。

启用 HOOK 前，**必须完整阅读** [references/atk-upstream-hook.md](references/atk-upstream-hook.md) 并按其中征询流程执行。

## 模板决策树

| 判断 | 用 `templates/` | 参考工程 |
|------|-----------------|----------|
| 单 `api_type`，CPU/NPU 共用 `BaseApi` | `simple_baseapi/` | `RopeWithSinCosCache` |
| 需 `api_type` + `aclnn_api_type`、golden 覆盖、nullptr / 类型补丁 | `complex_aclnn/` | `MhcPreSinkhorn` |

占位符：`{{OP_NAME}}`（类名）、`{{OP_SNAKE}}`（snake_case）、`{{ACLNN_NAME}}`（yaml name）、`{{REGISTER_*}}`（@register 名）。拷贝到 `tests/st/aclnn<Op>/` 后替换并重命名 `template_*`。

## 交付物

`aclnn_<op>.yaml` · `generate_<op>.py` · `<Op>.py` · `run_atk.sh` · `smoke_case.json`（可选）

## 工作流检查点

- [ ] yaml `inputs` 顺序对齐 `op_host/*_def.cpp`
- [ ] `atk case -f aclnn_<op>.yaml -p . -s <seed>` 成功
- [ ] `smoke_case.json` 从生成 JSON 的 case0 抽取；**attrs 嵌套数组**，勿平铺（否则 `input_config expected list`）
- [ ] 执行器 `@register` 与 yaml 的 `api_type` / `aclnn_api_type` 一致
- [ ] 用**用户完整命令**验收（必须 `-cp`、`-p` 为插件目录）

```bash
cd tests/st/aclnn<OpName>
atk node --backend pyaclnn --devices <id> -o "$(pwd)" \
  node --backend cpu \
  task -c smoke_case.json --task accuracy -p "$(pwd)" -s 0 -e 1 -cp
```

## 参考文档（按需加载）

| 任务 | 必须完整阅读 | 不要加载 |
|------|--------------|----------|
| 自定义 `init_by_input_data` / `__call__`、PyAclnn 路径 | [references/自定义执行方式.md](references/自定义执行方式.md) | 用例执行 README |
| JSON/CSV 字段、`cv_fused_*` 精度标准 | [references/用例执行README.md](references/用例执行README.md) | 自定义执行方式 |
| 对照完整 ST 工程、复杂算子模式 | [references/samples.md](references/samples.md) | 上述两篇全文 |
| skill 不足、需查 ATK 框架/版本/CLI | [references/atk-upstream-hook.md](references/atk-upstream-hook.md) | 勿在未征询前加载全文 |

**MANDATORY**：实现或改执行器前，**必须完整阅读** [references/自定义执行方式.md](references/自定义执行方式.md)（不要设行数上限）。

## 检验脚本

```bash
SKILL_ROOT="${SKILL_ROOT:-$HOME/.cursor/skills/ascendc-operator-st-gen}"
python3 "${SKILL_ROOT}/scripts/compare_atk_outputs.py" ./atk_output/<ts>/output --pytest-dir ../../pytest
bash "${SKILL_ROOT}/scripts/check_atk_log.sh" .
```

日志通过标志：`精度是否达标 | Pass`、`acc_pass_result:Pass`、`success 1, failed 0`。

## 常见陷阱

| 现象 | 处理 |
|------|------|
| `-cp` float/double 不匹配 | `_patch_aclnn_input_args` → `ctypes.c_double` |
| tiling 要 nullptr | `_ACLNN_NULLPTR_INPUT_IDX`，对照 `test_aclnn_*.cpp` |
| 双后端输入不一致 | golden/`init` 同步 `input_data.kwargs`（固定 seed 或 `init_by_input_data` 覆盖） |
| pyaclnn 与标杆数值差大 | 核对是否用 ATK 随机 tensor 未同步；必要时 `after_call` 走与 pytest 一致的 custom |

## NEVER

- ❌ 未跑用户完整命令（尤其 **`-cp`**）就声称已通过
- ❌ 把 `ListInt` 等复合入参在 JSON 里拆成多个平铺 input（应嵌套数组）
- ❌ 改算子 kernel/tiling 来"修" ST 精度
- ❌ `api_type` 与 `@register` 名不一致仍跑 task
- ❌ 用与验收不同的 `-p` 路径或省略 `-o` 导致落盘/路径错乱
- ❌ 未经用户同意访问 [AscendTest/ATK](https://gitcode.com/AscendTest/ATK) 或 `git clone` 该仓
