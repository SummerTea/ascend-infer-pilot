# repos/ —— 只读参考底座与源码清单

本目录仅承载**只读参考底座** `refs/` 与清单 `manifest.yaml`（受根仓库跟踪）。
日常操作脚本见 `scripts/manage_repos.sh`。

> **待优化目标工程的源码不在 `repos/`，而在 `workspace/<scenario-id>/source/`**（不入库、
> 每场景一份独立克隆、独立 `.git`）：
> `manifest.yaml` 的 `targets:` 段仍列出这些工程，`clone ... --scenario <id>` 会落到
> `workspace/<id>/source/<name>`。

## refs/：只读参考底座（严禁修改）

- cann-recipes-infer —— CANN 官方大模型推理优化典型样例库
- msmodelslim —— 昇腾官方量化与模型压缩工具链源码
- catlass —— 昇腾 Cube/Vector 高性能矩阵乘模板库
- pto-kernels —— 华为 CSL A2A3(910B) / A5(950) 双代算子参考实现
- Mooncake —— KVCache 跨机传输与 PD 解耦参考底座

军规：**严禁修改**。仅用于阅读、对比、参考实现思路；需要复用其思路时在
`workspace/<scenario-id>/optimized/` 自研实现，绝不直接改动 refs 内容。

## workspace/<scenario-id>/source/：待优化目标工程（不入库，每场景一份）

`manifest.yaml` 的 `targets:` 段列出 7 个待优化目标工程（vllm-ascend / vllm /
MindIE-LLM / MindIE-Motor / xllm / sglang / tilelang-ascend），
`clone <name> --scenario <id>` 落到 `workspace/<id>/source/<name>`
（**不入版本控制**、每场景一份、独立 `.git`）。

军规：

1. 每个子目录是**独立 Git 仓**（克隆自带）；Agent 须新建优化分支（如
   `opt/<model>-<feature>`）后再修改，不直接动主线。
2. 改完必须用 `scripts/manage_repos.sh export-patch <repo> --scenario <id>` 导出
   `.patch` 到 `workspace/<id>/ledger/patches/`，同时产出 `.meta.txt` 基线
   （url / branch / base_commit）。补丁用 `git apply -p1` 或 `patch -p1` 施用；
   `export-patch` 会以 intent-to-add（`git add -N`）方式把新增（untracked）
   文件一并纳入补丁。交付以 patch 为准，不依赖仓库内部中间状态。

## manifest.yaml

源清单：`targets:` 段（7 条，待优化目标工程，clone 落点
`workspace/<scenario-id>/source/`，需 `--scenario`）+ `refs:` 段（5 条，只读参考
底座，clone 落点 `repos/refs/`）。每条记录 url / branch / role，受根仓库跟踪，
由 `scripts/manage_repos.sh` 读取。12 条 url/branch 已联网核验通过，勿随意改写。

## 命令速查

    scripts/manage_repos.sh --list                              # 列出全部仓库；targets 克隆状态需 --scenario
    scripts/manage_repos.sh --list --scenario <id>              # 显示某场景 workspace/<id>/source 的克隆状态
    scripts/manage_repos.sh clone <name> --scenario <id>        # targets 单仓浅克隆到 workspace/<id>/source/<name>
    scripts/manage_repos.sh clone --targets --scenario <id>     # 批量浅克隆 targets 段到该场景
    scripts/manage_repos.sh clone --refs                        # 批量浅克隆 refs 段到 repos/refs/（不需 --scenario）
    scripts/manage_repos.sh clone <git-url> --scenario <id>     # 克隆任意 URL 到 workspace/<id>/source/
    scripts/manage_repos.sh status [--scenario <id>]            # 巡检 workspace/<id>/source（或全部场景）与 repos/refs
    scripts/manage_repos.sh export-patch <repo> --scenario <id> # 导出 workspace/<id>/source 仓改动为 patch + meta
