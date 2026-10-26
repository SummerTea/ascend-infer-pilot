---
name: ascend-network-hccl
description: 昇腾卡间通信与 PD 分离排障技能——单机全 HCCS 拓扑判读、hccl_test 基线、快慢卡三分类、RoCE/PFC 探针、DeepEP→CAM 与 NCCL→HCCL 迁移、PD 分离 KV 传输排障。Use when the user wants to verify the inter-card topology (HCCS/RoCE), run hccl_test busbw baselines, classify slow/fast ranks (host-bound / compute-bound / comm-bound), probe RoCE PFC/ECN, migrate DeepEP to CAM or NCCL to HCCL, or troubleshoot PD-disaggregation KV transfer; 中文触发：HCCL、卡间通信、hccl_test、快慢卡、RoCE、PFC、DeepEP、PD 分离、KV 传输。
---

# HCCL 卡间通信与 PD 分离排障（J3 瓶颈 4 / 阶梯 4）

对应 [docs/02 诊断 SOP](../../../docs/02-ascend-diagnosis-sop.md) 的 L4 互联层。**本机 8 卡单机全互联 = HCCS（真机实测）**，跨机才涉及 RoCE——先分清拓扑再谈通信排障，避免把 HCCS 问题按 RoCE 排查。

## 触发

多卡 TP/PP/EP 扩展倒挂、MoE 长尾卡顿、`hccl_test` 基线、快慢卡三分类、RoCE 丢包/PFC 反压、DeepEP→CAM / NCCL→HCCL 迁移、PD 分离 KV 传输慢 → 用本技能。

## 前置契约

- 工具不在默认 PATH：`hccl_test` / `ascend-dmi` 须先 `source /usr/local/Ascend/ascend-toolkit/set_env.sh`。
- 拓扑事实：本机 8 卡全互联 = **HCCS**（`npu-smi info -t topo` 实测），CPU 亲和分别绑 0-23/48-71/96-119/144-167；**跨机**才走 RoCE。
- 通信基线须与**同拓扑**历史基线比（偏差 > 10% 先查硬件），不要对公开数字比。

## 主流程

### 1. 拓扑判读（先分清 HCCS / RoCE）

```
npu-smi info -t topo
```

**完成标准**：确认单机 8 卡两两互联类型为 **HCCS**（本机实测；若显示 RoCE/PCIe 属异常或非本机）；明确 CPU 亲和绑定范围。拓扑异常（掉链路/降速）先修硬件再进通信归因。

### 2. hccl_test 基线（对应 nccl-tests）

```
source /usr/local/Ascend/ascend-toolkit/set_env.sh
all_reduce_perf -b 8 -e 1G -f 2 -g 8
alltoall_perf -b 8 -e 1G -f 2 -g 8    # 参数以 hccl_test 为准，须上机核实
```

**完成标准**：得到 8 卡 AllReduce/AlltoAll 的 busbw，与同拓扑存档基线对比；偏差 > 10% 先查链路/亲和/驱动，不进入瓶颈归因。

### 3. 快慢卡三分类

对扩展倒挂的 rank 集做三分类：**Host 下发慢 / 计算慢 / 通信慢**。

| 分类 | 判据 | 处置 |
| :--- | :--- | :--- |
| Host 下发慢 | rank 侧 msprof timeline 显示下发间隙（Bubble）集中在特定 rank；CPU 占用高 | 查绑核/NUMA/进程抢占，热路径同步 |
| 计算慢 | 该 rank 的 `msprof op` 主核耗时偏高 | 查算子/负载倾斜（专家路由统计） |
| 通信慢 | 该 rank 的 HCCL kernel 耗时/暴露时间偏高，hccl_test 单 rank 异常 | 查链路降速/PFC/小包传输 |

**完成标准**：每个慢 rank 归入三类之一并有 msprof/hccl_test 证据；专家倾斜必须直接看路由统计，别只靠 rank 间耗时方差。

### 4. RoCE 拓扑与 PFC/ECN 探针（跨机场景）

```
ethtool -S <eth> | grep -E "rx_prio[0-7]_pause|tx_prio[0-7]_pause|out_of_buffer|discards_phy"
ethtool -m <eth>    # 光模块（光功率/温度）
```

**完成标准**：pause 帧/PFC storm 计数不疯跳；无误码级告警。PFC 反压使通信延迟从 μs 级飙到 ms 级时，查交换机侧 PFC 配置与 ECN（pfcwd），不是换线缆能解决。

### 5. DeepEP→CAM / NCCL→HCCL 迁移

MoE EP 算子从 DeepEP 迁 CAM（昇腾 EP 算子语义），集合通信从 NCCL 迁 HCCL。

**完成标准**：迁移清单明确（通信原语映射：NCCL 集合 → HCCL 对应接口；DeepEP dispatch/combine → CAM 单边语义）；迁移后必跑 `hccl_test` + `msprof` timeline 验证重叠度（exposed_comm 不上升）。

### 6. PD 分离排障（KV 传输）

观测 KV 传输层（LLM-DataDist / Mooncake / LMCache）与 P/D 节点：

```
# 引擎侧指标（vllm-ascend / SGLang-Ascend）
#   vllm:nixl_xfer_time_seconds / vllm:nixl_bytes_transferred（若走 NIXL 类通道）
#   sglang:kv_transfer_speed_gb_s / sglang:kv_transfer_latency_ms（SGLang-Ascend）
#   Mooncake：MC_TE_METRIC=1 看周期带宽日志
```

**完成标准**：量化 `exposed_comm = comm_time - overlapped_time` 在 step 关键路径占比；KV page 逐块拷贝被延迟主导 → 攒批合并为连续大块（MB 级才接近峰值）；传输层慢 → 查 RDMA 计数器/误码/降速。

## 关键命令与判定表

| 场景 | 命令 | 判定 |
| :--- | :--- | :--- |
| 拓扑 | `npu-smi info -t topo` | 单机 8 卡全互联 = **HCCS** |
| 通信基线 | `all_reduce_perf -b 8 -e 1G -f 2 -g 8` | 与同拓扑基线比，偏差 > 10% 先修硬件 |
| 通信瓶颈 | msprof timeline 的 exposed_comm | 暴露时间在关键路径占比高才是瓶颈（「通信总耗时 > 25%」被计算覆盖则不是） |
| RoCE 拥塞 | `ethtool -S <eth> \| grep pause` | PFC storm 计数疯跳 → 查交换机 PFC/ECN |
| PD 传输 | 引擎 KV 传输指标 + RDMA 计数器 | 小包延迟主导 → 攒批大块；误码 → 换线缆/模块 |

## 常见坑

1. **把单机 HCCS 当 RoCE 排查**：本机 8 卡全互联实测为 HCCS（非 RoCE）；RoCE 只出现在跨机，先 `npu-smi info -t topo` 判读再选探针。
2. **忘了 `source set_env.sh`**：`hccl_test` / `all_reduce_perf` 不在默认 PATH，直接调用报 `command not found`。
3. **直接对公开带宽数字比**：busbw 必须与**同拓扑**历史基线比；低于基线 10% 以上先查链路/NUMA/亲和。
4. **只靠 rank 间耗时方差判断专家倾斜**：热门专家倾斜须直接看路由统计（SGLang `--expert-distribution-recorder-mode stat`、vLLM EPLB 统计），耗时方差只能作辅证。
5. **KV page 逐块拷贝**：小包传输被延迟主导（KB 级远低于峰值），应攒批/合并为连续大块再传。
6. **PFC 反压误判为物理层误码**：`rx_prioN_pause`/pause storm 是拥塞信号（查交换机 PFC/ECN），`SymbolErrorCounter` 高才是物理层误码（换线缆）。

## 关联

- 通信判据与 SOP：[docs/02 诊断 SOP](../../../docs/02-ascend-diagnosis-sop.md)；基线探针见 [docs/03 硬件与引擎](../../../docs/03-ascend-hardware-and-engines.md)
- 参考底座：`repos/refs/Mooncake/`（KV 跨机传输与 PD 解耦，只读）；清单见 [manifest.yaml](../../../repos/manifest.yaml)
- 上机前置：[ascend-910b-server](../ascend-910b-server/SKILL.md)；测量口径：[ascend-msprof-diagnosis](../ascend-msprof-diagnosis/SKILL.md)
