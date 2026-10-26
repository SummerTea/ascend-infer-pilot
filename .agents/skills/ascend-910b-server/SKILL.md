---
name: ascend-910b-server
description: 昇腾 910B3 评测机（10.19.93.115）的登录、环境盘点与容器基线——登录、核对 CANN/驱动版本、盘点 8 卡健康与 HBM 水位、容器与镜像、磁盘与模型落点。Use when the user wants to SSH into the Ascend 910B3 server, verify CANN/driver versions, check NPU health or HBM usage, list ascend containers/images, locate models or datasets, or prepare the environment for an NPU evaluation; 中文触发：登录 910B、盘点 NPU、核对 CANN、起昇腾容器、找模型/数据集、评测前环境核查。
---

# 910B3 评测服务器地基（10.19.93.115）

本机是昇腾推理优化工程的固定靶场：**8×910B3 / CANN 9.0.0-beta.1 / Ubuntu 24.04 / 单机全 HCCS**。任何 J2 校准、J3 基线、J6 门禁的第一步都是把地基打绿（本技能每一段的「完成标准」）。**环境事实均经真机核验（2026-10 实测），换版本后须按 [AGENTS.md](../../../AGENTS.md) 红线复测。**

## 触发

要在 10.19.93.115 上登录、盘点 NPU/容器/磁盘、核对 CANN 与驱动版本、定位模型与数据集、为评测准备环境 → 用本技能。它是 `ascend-msprof-diagnosis`、`ascend-network-hccl`、`vllm-ascend-adapter`、`ascend-quant-and-gate` 的公共前置。

## 前置契约

- 登录凭据：SSH 密钥 `~/.ssh/910b_ed25519`（免密），必须 `-i` 指定并加 `-o IdentitiesOnly=yes`，端口 `22022`；账号 `root`，另有 `puaiuc`（普通用户）。
- **工具不在默认 PATH**：`msprof` / `msprof-analyze` / `ascend-dmi` / `atc` / `hccl_test` 直接 `command -v` 均为空，必须先 `source /usr/local/Ascend/ascend-toolkit/set_env.sh`（该文件存在，是 `latest/set_env.sh` 的符号链接）。
- **宿主无 torch / torch_npu**（宿主 Python 3.12.3，`import torch` 失败）：真机评测**一律走 Docker 容器**，不在宿主跑。起容器用 `docker`（29.8.0，`/snap/bin/docker`）。

## 主流程

### 1. 登录（地基绿 §1）

```
ssh -i ~/.ssh/910b_ed25519 -o IdentitiesOnly=yes -p 22022 root@10.19.93.115
```

**完成标准**：`hostname` 返回 `phy-10-19-93-115`，能执行 `npu-smi info`。若批量连过后遇 `Permission denied`，多为 SSH 限速，等 8s 重试。

### 2. 8 卡健康与 HBM 水位（地基绿 §2）

```
npu-smi info
npu-smi info -t topo
```

**完成标准**：8 张卡全部 `Normal`、每卡 HBM **65536MB**（64GB）、无 ECC/告警异常；`topo` 显示**卡间全互联 = HCCS**（本机实测，非 RoCE），CPU 亲和分别绑 0-23/48-71/96-119/144-167。任一卡掉线/降速，先修硬件再进评测（见判定表）。

### 3. 核对 CANN / 驱动版本（地基绿 §3）

```
source /usr/local/Ascend/ascend-toolkit/set_env.sh
ls -l /usr/local/Ascend/cann
cat /usr/local/Ascend/driver/version.info
```

**完成标准**：`/usr/local/Ascend/cann -> /usr/local/Ascend/cann-9.0.0-beta.1`（即 **CANN 9.0.0-beta.1**）；驱动 `Version=25.5.1`、`ascendhal_version=7.35.23`。**版本取法**：`latest/version.cfg` 是空文件，勿靠它取版本；用 `cann/version.cfg` 或目录名。

### 4. 盘点容器与镜像（地基绿 §4）

```
docker ps -a
docker images | grep -Ei 'ascend|vllm|aisbench'
```

**完成标准**：知道当前运行中的容器（如 `vllm-ascend:v0.21.0rc1` 服务容器）与可用镜像清单。镜像源：`quay.io/ascend/vllm-ascend`、内网 harbor（`10.19.28.45:8003`、`10.19.32.152:1780`、`10.19.93.215:5000`）、`aisbench/all-services`。

### 5. 资源核对（地基绿 §5）

```
df -h /data /
nproc
free -g
```

**完成标准**：`/data` **14T**（已用约 59%）、`/` 7.4T（已用约 21%）；**192 核**；内存约 **1TB（1005 GB）**。大文件下载/缓存一律放 `/data`，勿写系统盘。

### 6. 模型与数据集落点（地基绿 §6）

```
ls /data/ai-stack-models/models
ls /data/datasets
```

**完成标准**：找到目标模型权重目录（含 Qwen2.5/Qwen3 系列等，检查 safetensors 与 tokenizer 齐全、非 0 字节）与数据集目录。

## 关键命令与判定表

| 检查项 | 命令 | 判定 |
| :--- | :--- | :--- |
| 卡健康 | `npu-smi info` | 8 卡均 `Normal`、HBM 65536MB；任一卡异常 → 先修硬件 |
| 拓扑 | `npu-smi info -t topo` | 单机 8 卡全互联 = **HCCS**（非 RoCE）；跨机才涉及 RoCE（见 `ascend-network-hccl`） |
| CANN 版本 | `ls -l /usr/local/Ascend/cann` | 指向 `cann-9.0.0-beta.1`；`latest/version.cfg` 为空，用 `cann/version.cfg` 或目录名 |
| 驱动版本 | `cat /usr/local/Ascend/driver/version.info` | `Version=25.5.1`、`ascendhal_version=7.35.23` |
| 工具可用性 | `command -v msprof hccl_test atc` | 为空即未 `source set_env.sh` |
| 资源 | `df -h /data /`；`nproc`；`free -g` | `/data` 14T、192 核、约 1TB 内存 |

## 常见坑

1. **拿 `latest/version.cfg` 取版本**：该文件为空（`/usr/local/Ascend/ascend-toolkit/latest/version.cfg`），取不到任何版本号；用 `cann/version.cfg` 或目录名。
2. **把 `cann-9.0.0` 当目录**：`/usr/local/Ascend/cann-9.0.0` 是 **0 字节占位文件**，`cd` 会失败；真实目录是 `cann-9.0.0-beta.1`。
3. **工具直接 `command -v` 为空就以为没装**：`msprof` / `hccl_test` / `atc` 都已安装但**不在默认 PATH**，必须先 `source /usr/local/Ascend/ascend-toolkit/set_env.sh`。
4. **在宿主跑 torch 评测**：宿主未装 torch / torch_npu，`import torch` 直接失败——评测、msprof 采集、量化全部在 **Docker 容器**内执行。
5. **根分区写大文件**：`/` 7.4T 但属系统盘，模型/缓存/日志一律落 `/data`。

## 关联

- 环境事实与红线：[AGENTS.md](../../../AGENTS.md)；硬件规格与探针脚本：[docs/03 硬件与引擎](../../../docs/03-ascend-hardware-and-engines.md)
- 下一跳：采集与归因用 [ascend-msprof-diagnosis](../ascend-msprof-diagnosis/SKILL.md)、通信排障用 [ascend-network-hccl](../ascend-network-hccl/SKILL.md)
- 校准台账分母口径：[calibration-template.md](../../../templates/calibration-template.md)；测量铁律见 [docs/02 诊断 SOP](../../../docs/02-ascend-diagnosis-sop.md)
