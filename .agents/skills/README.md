# skills/ —— Agent Skills 规范平铺目录

本目录按 **Agent Skills 规范平铺**：每个技能一个顶层目录，形如
`<skill-name>/SKILL.md`（可选 `references/`、`scripts/`、`assets/`）。
**不得再建 `vendored/`、`external/` 等分类子目录**（P11a 已删除，历史见下）。

## 入库 vs 不入库

- **随仓库跟踪**（白名单见 `.gitignore`）：下方 5 个技能 + 本 README。
- **同步而来、不入库**：`scripts/sync_ascend_skills.sh` 拉取的第三方昇腾技能，
  **平铺**落到本目录（不再按域分子目录），被 `.gitignore` 忽略，每次同步重新生成。

## 入库技能清单（5 个）

| 技能 | 来源 | 为什么留 | 昇腾注意点 |
|---|---|---|---|
| `evalscope` | modelscope/evalscope | J6 双轨评测（可打 OpenAI 兼容端点） | 性能数值须换算为 msprof 设备侧口径 |
| `kl-consistency-test` | sgl-project/sglang | J6 轨道 A 的 prefill/decode 双路径 logprob KL 方法（通用） | 无 CUDA 依赖，直接可用 |
| `mooncake-api` | kvcache-ai/Mooncake | KV 传输 / PD 解耦 API（Mooncake 支持昇腾传输） | 传输层注意走昇腾后端 |
| `mooncake-troubleshoot` | 同上 | 部署排障（服务/RDMA/env/内存注册/日志） | RDMA 侧对应 HCCL/RoCE |
| `debug-distributed-hang` | sgl-project/sglang | 分布式卡死排查（py-spy / 二分定位 / rank 状态发散） | `cuda-gdb`/CUDA coredump/`NCCL_DEBUG` 需替换为 HCCL/`hccl_test`/`msprof` |

## 已删除的 2 个（P11a 移除，不再使用）

- `triton-kernel-writing` —— 纯 `@triton.jit`，本工程不用 Triton。
- `kernel-microbenchmark` —— CUPTI/CUDA-only，直接跑会失败，且与 msprof 铁律冲突。

（原 `vendored/`、`external/` 两层目录与其 README 一并删除；上游原文逐字入库的
口径取消，筛选原则见下。）

## 同步方式

```bash
bash scripts/sync_ascend_skills.sh --list          # 离线看源清单与 allowlist（不访问网络）
bash scripts/sync_ascend_skills.sh --category all  # 全量同步
bash scripts/sync_ascend_skills.sh --only <origin> # 定向单源（如 --only vllm-ascend）
bash scripts/sync_ascend_skills.sh --dry-run       # 试跑不落盘
```

同步结果**平铺**到本目录、入 gitignore。当前源清单：**14 仓 / 22 条 allowlist**
（逐仓来源表待 P11c 补齐，以 `--list` 实际输出为准，勿编造 commit）。

## 筛选原则

- 实现路线优先级：**AscendC > TileLang > PyPTO/CATLASS**。
- **Triton / Triton-Ascend 不在实现路线**——脚本对技能名含 `triton` 的**一律跳过**。
- 只收「昇腾开发（算子/模型接入/量化/图模式）」与「昇腾运维
  （性能诊断/通信/服务化/部署）」相关技能。

## 相关链接

- [docs/04 技能目录与昇腾相关性](../../docs/04-skill-catalog-and-maintenance.md)
- [AGENTS.md §7 知识库与第三方技能路由](../../AGENTS.md)
