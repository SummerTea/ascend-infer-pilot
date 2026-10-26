# repos/ —— 只读参考底座与源码清单

本目录现只承载**只读参考底座** `refs/` 与清单 `manifest.yaml`（受根仓库跟踪）。
日常操作脚本见 `scripts/manage_repos.sh`。

> **待优化目标工程的源码不在 `repos/`，而在 `workspace/source/`**（不入库、单份共享、暂不建 git）：
> `manifest.yaml` 的 `targets:` 段仍列出这些工程，`clone` 会落到 `workspace/source/<name>`。

## refs/：只读参考底座（严禁修改）

- cann-recipes-infer —— CANN 官方大模型推理优化典型样例库
- msmodelslim —— 昇腾官方量化与模型压缩工具链源码
- catlass —— 昇腾 Cube/Vector 高性能矩阵乘模板库
- pto-kernels —— 华为 CSL A2A3(910B) / A5(950) 双代算子参考实现
- Mooncake —— KVCache 跨机传输与 PD 解耦参考底座

军规：**严禁修改**。仅用于阅读、对比、参考实现思路；需要复用其思路时在
`workspace/optimized/` 自研实现，绝不直接改动 refs 内容。

## workspace/source/：待优化目标工程（不入库）

`manifest.yaml` 的 `targets:` 段列出 7 个待优化目标工程（vllm-ascend / vllm /
MindIE-LLM / MindIE-Motor / xllm / sglang / tilelang-ascend），`clone` 落到
`workspace/source/<name>`（**不入版本控制**、单份共享、暂不建 git）。

军规：

1. 每个子目录是**独立 Git 仓**（克隆自带）；Agent 须新建优化分支（如
   `opt/<model>-<feature>`）后再修改，不直接动主线。
2. 改完必须用 `scripts/manage_repos.sh export-patch <repo> <case>` 导出 `.patch`
   到 `workspace/ledger/<case>/patches/`，同时产出 `.meta.txt` 基线
   （url / branch / base_commit）。补丁用 `git apply -p1` 或 `patch -p1` 施用；
   `export-patch` 会以 intent-to-add（`git add -N`）方式把新增（untracked）
   文件一并纳入补丁。交付以 patch 为准，不依赖仓库内部中间状态。

## manifest.yaml

源清单：`targets:` 段（7 条，待优化目标工程，clone 落点 `workspace/source/`）
+ `refs:` 段（5 条，只读参考底座，clone 落点 `repos/refs/`）。每条记录 url /
branch / role，受根仓库跟踪，由 `scripts/manage_repos.sh` 读取。12 条 url/branch
已联网核验通过，勿随意改写。

## 命令速查

    scripts/manage_repos.sh --list                     # 列出全部仓库与克隆状态
    scripts/manage_repos.sh clone <name>               # 按 manifest 浅克隆单个仓
    scripts/manage_repos.sh clone --targets|--refs     # 批量浅克隆某一段
    scripts/manage_repos.sh clone <git-url>            # 克隆任意 URL 到 workspace/source/
    scripts/manage_repos.sh status                     # 巡检 workspace/source 与 repos/refs（分支/hash/未提交改动）
    scripts/manage_repos.sh export-patch <repo> <case> # 导出 workspace/source 仓改动为 patch + meta
