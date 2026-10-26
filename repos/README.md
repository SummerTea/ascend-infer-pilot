# repos/ —— 外部源码双轨目录

本目录管理两类外部源码仓库：`targets/`（待优化目标工程）与 `refs/`（只读参考底座）。
源清单见 `manifest.yaml`（受根仓库跟踪），日常操作脚本见 `scripts/manage_repos.sh`。

## targets/：待直接改造 / 调试 / 打补丁的目标工程

- vllm-ascend —— vLLM 昇腾官方硬件插件宿主（阶梯 1~5 主力优化对象）
- vllm —— vLLM 上游核心引擎（与 vllm-ascend 配合联调调度与接口）
- MindIE-LLM —— 昇腾原生大模型推理引擎（ATB/ACLNN 算子与建模优化）
- MindIE-Motor —— 昇腾 PD 分离与集群服务化编排引擎
- xllm —— OpenAtom 昇腾高性能推理引擎（含 TileLang-Ascend 深度集成）
- sglang —— SGLang 推理引擎（含 NPU / Ascend 后端适配层）
- tilelang-ascend —— TileLang 昇腾算子与编译器 Pass 开发仓（阶梯 4/5）

军规：

1. 每个子目录是**独立 Git 仓**；根仓库只跟踪本目录的 `.gitkeep` 与 `manifest.yaml`，
   不跟踪任何仓内代码。
2. Agent 须在其中新建优化分支（如 `opt/<model>-<feature>`）后再修改，不直接动主线。
3. 改完必须用 `scripts/manage_repos.sh export-patch <repo> <case>` 导出 `.patch`
   到 `cases/<case>/patches/`，同时产出 `.meta.txt` 基线（url / branch / base_commit）。
   补丁用 `git apply -p1` 或 `patch -p1` 施用；`export-patch` 会以 intent-to-add
   （`git add -N`）方式把新增（untracked）文件一并纳入补丁。
   交付以 patch 为准，不依赖仓库内部中间状态。

## refs/：只读参考底座（严禁修改）

- cann-recipes-infer —— CANN 官方大模型推理优化典型样例库
- msmodelslim —— 昇腾官方量化与模型压缩工具链源码
- catlass —— 昇腾 Cube/Vector 高性能矩阵乘模板库
- pto-kernels —— 华为 CSL A2A3(910B) / A5(950) 双代算子参考实现
- Mooncake —— KVCache 跨机传输与 PD 解耦参考底座

军规：**严禁修改**。仅用于阅读、对比、参考实现思路；需要复用其思路时在 `src/`
自研实现，绝不直接改动 refs 内容。

## manifest.yaml

源清单：每条记录 url / branch / role 与归属段（targets 或 refs），受根仓库跟踪，
由 `scripts/manage_repos.sh` 读取。其中 12 条 url/branch 已经联网核验通过，勿随意改写。

## 命令速查

    scripts/manage_repos.sh --list                     # 列出全部仓库与克隆状态
    scripts/manage_repos.sh clone <name>               # 按 manifest 浅克隆单个仓
    scripts/manage_repos.sh clone --targets|--refs     # 批量浅克隆某一段
    scripts/manage_repos.sh clone <git-url>            # 克隆任意 URL 到 targets/
    scripts/manage_repos.sh status                     # 巡检已克隆仓（分支/hash/未提交改动）
    scripts/manage_repos.sh export-patch <repo> <case> # 导出目标仓改动为 patch + meta
