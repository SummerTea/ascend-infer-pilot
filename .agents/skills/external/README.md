# external/ —— 远端同步的第三方 NPU 技能

本目录由 `scripts/sync_ascend_skills.sh` **按域同步**的第三方 NPU 技能落点，
供 AGENTS.md 技能路由与人工查阅使用。**内容被 `.gitignore` 忽略**
（`/.agents/skills/external/*` + `!/.agents/skills/external/README.md`），
本目录内除本 README 外均不受版本控制 —— 每次同步都是脚本从远端
重新拉取生成，无需入库。

## 目录约定

```
.agents/skills/external/<域>/<源仓名>/<技能目录名>/
```

- `<域>` 对应 `sync_ascend_skills.sh` 的四大域，与源清单一一对应：
  - `operators/` —— NPU 算子 / kernel 类技能（cannbot、tilelang-ascend、xllm 等）
  - `network/` —— 分布式组网 / 集合通信类技能（GOD、msagent、MindIE-Motor 等）
  - `tooling/` —— 评测、量化、模型转换等工具链技能（msmodelslim、evalscope 等）
  - `engines/` —— 推理引擎部署 / 调优类技能（vllm-ascend、MindIE-LLM、sglang 等）
- `<源仓名>` 即源清单中的组名（同 `<name>`）。
- `<技能目录名>` 为源仓内发现 `SKILL.md` 的目录相对路径（保留仓内结构）。

## 用法

脚本离线查看内置源清单（不访问网络）：

```bash
bash scripts/sync_ascend_skills.sh --list
```

全量同步四大域：

```bash
bash scripts/sync_ascend_skills.sh --category all
```

定向同步单个域 / 单仓（示例：只同步 operators 域下的 tilelang-ascend）：

```bash
bash scripts/sync_ascend_skills.sh --category operators --only tilelang-ascend
```

行为说明：

- 每个源仓**浅克隆**到 `.cache/skills/<name>`（已存在则 `fetch --depth 1`
  更新到该分支最新提交），再从仓内 **自动 find 所有含 `SKILL.md` 的目录**。
  不同源仓技能位置异构（`skills/`、`.agents/skills/`、`.claude/skills/`…），
  脚本统一发现、保留相对路径并**按前缀去重**（嵌套技能目录不重复拷贝）。
- 单仓失败**不中断**整体，该仓计入 FAIL，末尾输出 `OK n / FAIL m` 汇总。
- 重复同步会更新缓存；目标落点按前缀去重，可安全重跑。

## 源清单（21 组）

operators | cannbot-skills        | https://gitcode.com/cann/cannbot-skills.git                   | master
operators | tilelang-ascend       | https://github.com/tile-ai/tilelang-ascend.git                | ascendc_pto
operators | xllm                  | https://github.com/xLLM-AI/xllm.git                           | main
operators | pto-kernels           | https://github.com/huawei-csl/pto-kernels.git                 | main
operators | catlass               | https://gitcode.com/cann/catlass.git                          | master
operators | ascend-agent-skills   | https://gitcode.com/Ascend/agent-skills.git                   | master
operators | xllm-workflow         | https://github.com/xLLM-AI/xllm-workflow.git                  | main
network   | god                   | https://github.com/XiaoLuoLYG/GOD.git                         | main
network   | msagent               | https://gitcode.com/Ascend/msagent.git                        | master
network   | msagent-mirror        | https://github.com/kali20gakki/msAgent.git                    | master
network   | mindie-motor          | https://github.com/Ascend/MindIE-Motor.git                    | master
tooling   | msmodelslim           | https://gitcode.com/Ascend/msmodelslim.git                    | master
tooling   | mindie-sd             | https://github.com/Ascend/MindIE-SD.git                       | dev
tooling   | evalscope             | https://github.com/modelscope/evalscope.git                   | main
tooling   | model-agent           | https://gitcode.com/Ascend/model-agent.git                    | master
tooling   | awesome-ascend-skills | https://github.com/ascend-ai-coding/awesome-ascend-skills.git | main
engines   | vllm-ascend           | https://github.com/vllm-project/vllm-ascend.git               | main
engines   | ascend-sglang-skills  | https://github.com/LinyuanLi0046/Ascend-SGLang-Skills.git     | main
engines   | cann-recipes-infer    | https://gitcode.com/cann/cann-recipes-infer.git               | master
engines   | mindie-llm            | https://gitcode.com/Ascend/MindIE-LLM.git                     | master
engines   | sglang                | https://github.com/sgl-project/sglang.git                     | main

（域分布：operators=7 / network=4 / tooling=5 / engines=5，共 21 组）

## 提示

- GitCode 源首次访问会重定向到 `*.git/` 路径（正常现象，脚本已处理）。
- 镜像仓（如 msagent-mirror）存在停更风险，取源优先级与维护口径见
  [docs/04 技能目录](../../../docs/04-skill-catalog-and-maintenance.md)。

## 相关链接

- [源仓清单](../../../repos/manifest.yaml)
- [同步脚本](../../../scripts/sync_ascend_skills.sh)
- [AGENTS.md 技能路由](../../../AGENTS.md)
