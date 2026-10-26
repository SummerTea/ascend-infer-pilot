# 03 · 昇腾硬件代际物理规格与引擎扩展挂载点

> **定位**：910B/910C vs 950PR/950DT 代际物理规格、主机环境核对（本机事实见各场景台账 `workspace/<scenario-id>/ledger/00-probe.md` 的机器档案段）、四大引擎的昇腾扩展挂载点索引、950 落地建议。
> **配套**：[流水线与物理账本](01-pipeline-and-ledger.md)（P_eff/BW_eff 校准）｜ [诊断 SOP](02-ascend-diagnosis-sop.md) ｜ [技能目录](04-skill-catalog-and-maintenance.md)
> **硬件参数以昇腾技能选型指南 §2.2 与 §5 为准**；本文档为 L2 层知识底座，**使用前须核对 CANN / torch_npu / 引擎 commit**（扩展挂载点与支持矩阵随版本变动）。

---

## 1. 910B/910C vs 950PR/950DT 代际物理规格对比

| 维度 | 910B/910C（A2/A3） | **950PR/950DT（A5，arch35）** |
| :--- | :--- | :--- |
| **Vector 单元** | 仅 **SIMD**（MemBase 体系） | **SIMD + SIMT 双模型**（DCache / Warp Scheduler / 128KB RF） |
| **UB（Unified Buffer）** | **16 group × 3 × 4KB** | **8 group × 2 × 16KB**（**Bank 冲突规则重写**，不得沿用 910B 的 Bank 规划） |
| **新增数据类型** | 无（BF16/FP16/INT8/INT4 低比特经 ATB/msmodelslim 路径） | **HiF8（hifloat8_t）**、**MXFP4 / MXFP8**（MXFP8 量化仅 A5/950 硬件支持） |
| **数据通路** | 经典 UB↔HBM / L0 体系 | 新增 **L0C→UB**、**UB→L1**、**SSBuffer** CV 消息通路 |
| **通信引擎** | — | 新增 **CCU**（IO-Die 内），msprof 可采 **CCU 带宽** |
| **msprof 指标** | 支持 **PipelineExecuteUtilization** / **MemoryAccess** | **不支持上述两项**；新增 **CCU / UB 带宽**采集 |
| **核心/Cube/Vector 边界** | Cube（矩阵）+ Vector（SIMD）分工经典；算力受限时先看 Cube 利用率 | SIMT 引入 Warp 级并行，Vector 与 Cube 的负载划分需重新核算；HiF8/MX 精度下 `P_eff` 大幅上移、`B* = P_eff/BW_eff` 同步上移 |
| **工具链支持** | 全套技能覆盖 | CANN 9.0+ 支持（→9.2.0 新增 950 系 8bit/4bit 低精度、MoE Dispatch/Combine 直驱 URMA、Engram、CATLASS Python 核函数）；**技能层仅 4 处内嵌标记** |
| **仿真验证** | — | **NPU Simulator（cannsim）仅支持 950PR/950DT** |

> **取证结论**：950 新特性（HiF8 / SIMT / RegBase / MX）全在 CANN / `cann/asc-devkit` 文档层，多处标注「资料开发中」。**技能生态滞后于硬件发布**——950 场景必须先仿真验证、再上真机（见 §5）。

**对账本公式的直接影响**（联动 [物理账本 §4](01-pipeline-and-ledger.md)）：

| 影响面 | 910B3 | 950 |
| :--- | :--- | :--- |
| `P_eff` 校准 | 大 GEMM 用 BF16/FP8 标定 | 用 HiF8 / MXFP4 / MXFP8 档位标定（`B*` 上移，访存受限区间收窄） |
| `BW_eff` 校准 | 大 copy 标定 HBM 带宽 | 需注意新增通路（L0C→UB / UB→L1 / SSBuffer）在特定算子中替代部分 HBM 往返，`bytes_min` 口径随之改变 |
| msprof 判据 | `PipelineExecuteUtilization` / `MemoryAccess` | 这两项**不可用**，改用 CCU / UB 带宽指标（判据阈值需重标，不得平移） |
| 诊断 SOP | [诊断 SOP](02-ascend-diagnosis-sop.md) 阈值直接可用 | 阈值按 §1 差异重校准后复用 |

---

## 2. 主机环境核对（只留通用探针方法与坑；本机事实见场景台账 00-probe.md 机器档案段）

**主机专属事实一律见各场景台账 `workspace/<scenario-id>/ledger/00-probe.md` 的「机器档案」段（不入库）**：评测服务器 IP / SSH 端口与密钥 / 卡型 / HBM 容量 / CANN·驱动·工具版本 / 镜像名与源 / 磁盘布局与模型·数据集路径 / 配套版本组合。本文档**只保留通用探针方法与坑，不落任何本机专属值**。首次上机按序执行：

```bash
# 0) 登录评测机（SSH 端口、密钥与账号见场景台账 00-probe.md 的机器档案段）
ssh -i <密钥> -o IdentitiesOnly=yes -p <端口> <用户>@<主机>

# 1) 加载 CANN 工具链（msprof / atc / hccl_test 等不在默认 PATH，须先 source）
source /usr/local/Ascend/ascend-toolkit/set_env.sh

# 2) 卡健康与拓扑
npu-smi info
npu-smi info -t topo

# 3) msprof 最小探针（确认硬件计数器可读，防假活环境；在已装 torch_npu 的容器内执行）
msprof op --output=/tmp/probe --application="python3 -c 'import torch, torch_npu; torch.npu.init(); torch.empty(1, device=\"npu:0\")'"

# 4) 通信基线（hccl_test）
all_reduce_perf -b 8 -e 1G -f 2 -g 8

# 5) P_eff / BW_eff 校准（大 GEMM / 大 copy，msprof op 计时）
msprof op --output=/tmp/gemm_calib --application="python3 calib_gemm.py"
msprof op --output=/tmp/copy_calib --application="python3 calib_copy.py"
```

**通用坑**：

- `latest/version.cfg` **可能为空文件**——取 CANN 版本用 `cann/version.cfg` 或目录名（`cann-<version>`），勿靠 `latest/` 软链。
- 工具（`msprof` / `msprof-analyze` / `atc` / `hccl_test` / `ascend-dmi`）**不在默认 PATH**，`command -v` 为空是正常的，先 `source /usr/local/Ascend/ascend-toolkit/set_env.sh`。
- 宿主通常**未安装 torch / torch_npu**，评测与采集一律进 Docker 容器；`docker ps -a` / `docker images` 核对容器与镜像（镜像名与源见场景台账 00-probe.md 的机器档案段）。
- 磁盘布局与容量以 `df -h` 实测为准（模型/数据集路径见场景台账 00-probe.md 的机器档案段）。

校准结果落 `workspace/_shared/calibration.md`（跨场景共享、不入库，按 `<模型>@<硬件>` 分节；α / β / 锁频命令 / CANN↔torch_npu↔PyTorch↔驱动配套版本）。

---

## 3. 引擎扩展挂载点索引（昇腾版）

> **路径说明**：改引擎落 `workspace/<scenario-id>/source/<engine>/`（不入库；使用前先 `bash scripts/manage_repos.sh clone <name> --scenario <scenario-id>`，manifest 见 `repos/manifest.yaml`）才有本地源码。**只读参考**一律放 `repos/refs/<repo>/`，严禁修改。改引擎必须用 `bash scripts/manage_repos.sh export-patch <engine> --scenario <scenario-id>` 导出补丁。

### 3.1 vllm-ascend / vLLM（`workspace/<scenario-id>/source/vllm-ascend/`、`workspace/<scenario-id>/source/vllm/`）

| 挂载点 | 位置（昇腾侧） | 用途 |
| :--- | :--- | :--- |
| `register_model` | vLLM `vllm/model_executor/models/registry.py`（`ModelRegistry.register_model("Arch", "my_pkg.models:MyModel")`，**非装饰器**：`register_model` 返回 `None`，字符串须 `<module>:<class>` 冒号形式） | 挂载非标模型结构（阶梯 3/4；以 `workspace/<scenario-id>/source/vllm/` 实际 pin 版本为准，须上机核实） |
| `register_backend` / `AttentionBackend` | vLLM `vllm/v1/attention/backends/registry.py`（**`class_path=None` 才返回装饰器**：`@register_backend(AttentionBackendEnum.CUSTOM)` 修饰实现类，或命名注册 `register_backend("ASCEND", "my_pkg.attn.AscendAttentionBackend")`——**点号限定名**，上游 `resolve_obj_by_qualname` 用 `rsplit(".",1)` 解析，冒号形式会 `AttributeError`；实现为 `AscendAttentionBackendImpl`） | 按平台/头维/KV dtype 分派 FIA（AscendAttentionBackend / `npu_fused_infer_attention_score`）等昇腾后端 |
| `register_quantization_config` | vLLM `vllm/model_executor/layers/quantization/__init__.py`（继承 `QuantizationConfig`） | 权重加载期转置/重排与低比特路径（ATB 量化解码 / msmodelslim 导出权重） |
| entry_points 插件 | vllm-ascend 的 pyproject entry points + 扩展包加载 | 昇腾专属算子与 hook 以插件形态隔离集成（阶梯 3） |
| torch_npu 融合算子替换 | `workspace/<scenario-id>/source/vllm-ascend/`（ops/ 目录：FIA / MLA absorb / MoE GMM / RoPE / KV write） | 识别并替换 torch_npu 融合算子（诊断 SOP 瓶颈 1 的「融合度验证」落点） |

### 3.2 MindIE-LLM / MindIE-Motor / MindIE-Turbo（`workspace/<scenario-id>/source/MindIE-LLM/`、`workspace/<scenario-id>/source/MindIE-Motor/`）

> ⚠️ **MindIE-Turbo 无独立 clone**（manifest 无该仓），作为面向第三方引擎（vLLM / SGLang）的通用 NPU 加速层引用，**勿**寻找 `workspace/<scenario-id>/source/MindIE-Turbo/`。

| 引擎 | 挂载点 | 用途 |
| :--- | :--- | :--- |
| **MindIE-LLM** | ATB / ACLNN 算子层（`atb::*`、`aclnn*` 单算子接口） | 昇腾原生 LLM 引擎；建模层算子替换 / 低比特路径（阶梯 2/4） |
| **MindIE-Motor** | PD 分离与集群服务化（deploy/diagnosis/validation 技能族） | 对标 Dynamo/vLLM-router 的编排层：Prefill/Decode 分离、请求分派、KV 拉取（阶梯 3 / J4 前置选项） |
| **MindIE-Turbo** | 面向第三方引擎（vLLM / SGLang）的通用 NPU 加速组件 | 不换引擎时引入的通用加速层（J4 前置「换宿主」的轻量替代） |

### 3.3 xLLM（`workspace/<scenario-id>/source/xllm/`）

| 挂载点 | 位置 | 用途 |
| :--- | :--- | :--- |
| **TileLang-Ascend 集成** | xLLM 推理栈内嵌 TileLang backend（配合 `workspace/<scenario-id>/source/tilelang-ascend/`，分支 `ascendc_pto`） | Triton→TileLang 语义映射、kernel 级移植与编译器 Pass 直达（阶梯 4/5）；`tilelang-perf-optimization` 技能强制 `msprof op` 度量 |

### 3.4 SGLang-Ascend（`workspace/<scenario-id>/source/sglang/`）

| 挂载点 | 位置 | 用途 |
| :--- | :--- | :--- |
| **LMCache 存储后端** | `python/sglang/srt/mem_cache/storage/lmcache/` | 昇腾侧 KV 远端缓存接入（LMCache 适配层，前缀复用 / KV offload） |
| **PD 解耦 hook** | `python/sglang/srt/arg_groups/pd_disaggregation_hook.py` | Prefill/Decode 解耦的调度与 KV 传输 hook（J4 前置「PD 分离」落点） |

### 3.5 只读参考（`repos/refs/<repo>/`）

| 参考仓 | 用途 |
| :--- | :--- |
| `repos/refs/cann-recipes-infer/` | CANN 官方大模型推理优化典型样例（融合/量化/KV 套路参考） |
| `repos/refs/msmodelslim/` | 昇腾量化与模型压缩工具链源码（`evaluate`/`tuning` 门禁、EP 并行） |
| `repos/refs/catlass/` | Cube/Vector 矩阵乘模板库（阶梯 4 移植参考） |
| `repos/refs/pto-kernels/` | **A2A3（910B）/ A5（950）双代**算子参考实现（双代差异直接对照） |
| `repos/refs/Mooncake/` | KV 跨机传输与 PD 解耦参考底座 |

> **阶梯 2/4/5 必须改引擎时**：改 `workspace/<scenario-id>/source/<engine>/`（如 `workspace/<scenario-id>/source/vllm-ascend/`、`workspace/<scenario-id>/source/vllm/`、`workspace/<scenario-id>/source/sglang/`、`workspace/<scenario-id>/source/MindIE-LLM/`、`workspace/<scenario-id>/source/MindIE-Motor/`、`workspace/<scenario-id>/source/xllm/`、`workspace/<scenario-id>/source/tilelang-ascend/`）；若引擎已是克隆仓，直接在仓内修改并 `export-patch`。

---

## 4. 引擎能力速查（选型用）

| 引擎 | 生态位 | 昇腾适配现状 | 主要挂载手段 | 技能支撑 |
| :--- | :--- | :--- | :--- | :--- |
| **vllm-ascend** | vLLM 昇腾官方硬件插件宿主 | 官方维护，主力引擎 | 注册表（model/attention/quant）+ entry_points 插件 + torch_npu 融合算子 | `vllm-ascend-model-adapter` / `vllm-ascend-deploy`（含 950DT 镜像 tag）/ `vllm-ascend-developer` |
| **MindIE-LLM / Motor / Turbo** | 昇腾原生引擎 + 编排 + 通用加速 | 华为官方；Motor 23 技能覆盖 PD 分离全生命周期 | ATB/ACLNN 算子、Motor 服务化、Turbo 加速层 | `MindIE-Motor` 技能族（deploy/diagnosis/validation） |
| **xLLM** | OpenAtom 高性能推理引擎（TileLang 深度集成） | xLLM 专用技能仓 22 个 | TileLang-Ascend kernel、xllm-npu-profiler 五表输出 | `tilelang-ascend-kernel` / `xllm-npu-profiler` |
| **SGLang-Ascend** | 高吞吐 + 前缀缓存标杆 | NPU 专项技能几乎空白（仅社区 3-skill 小仓） | LMCache 存储后端、PD 解耦 hook | 用 vllm-ascend 技能替代；方法论从 SGLang 主仓技能取 |

---

## 5. 950 落地建议

1. **以一个 910B 技能为主体**（推荐 cannbot `model-infer-*` 家族），配合 **MXFP8 档位经验**（`dit-perf-opt`，仅 A5/950 硬件支持）做精度前提。
2. **用 950DT 镜像 tag 起服务**（vllm-ascend-deploy 的 `*-950dt` tag 线索；TorchNPU 26.1.0 官方适配 950DT）。
3. **先做 950 算子级仿真验证**：NPU Simulator（cannsim）仅支持 950PR/950DT；`hccl_test` 支持 950 系 **32K rank**；msprof 支持 950 系系统数据采集（CCU/PCIe/SIO/UB 带宽、SoC 频率上限 10000）。
4. **950 专项技能需自建**：把 §1 的代际差异（**SIMT / HiF8 / UB Bank 重写 / L0C→UB、UB→L1、SSBuffer / CCU / msprof 指标差异**）写成 950 专属约束，注入 910B 技能与诊断 SOP 阈值重校准中（落 `docs/` 与本机校准台账）。

---

## CUDA→torch_npu 迁移与图模式修复

对应昇腾接入的「J1 前置」：环境配套与迁移。**配套版本是本环节最高风险点**——CANN ↔ torch_npu ↔ PyTorch ↔ 驱动（HDK）严格对应，不可混装；换任一版本必须重跑校准与复测（本机实测配套版本见场景台账 00-probe.md 的机器档案段）。

### 1. 迁移速查（机械替换 + 语义核对）

```
.cuda()            → .npu()
device='cuda'      → device='npu'
torch.cuda.*       → torch.npu.* 对应项（如 torch.npu.init()）
cudaStream/Event   → 昇腾 stream/事件语义（API 名须上机核实，勿机械等价）
```

**完成标准**：源码无 `cuda` 残留（`rg -n 'cuda|CUDA' <迁移目录>` 零命中）；stream/同步语义差异逐处核对（昇腾异步发射语义与 CUDA 不同，热路径同步是五不准红线 1）。

### 2. 配套版本核验（防混装）

```
source /usr/local/Ascend/ascend-toolkit/set_env.sh
ls -l /usr/local/Ascend/cann                  # → cann-<version>（本机版本见场景台账 00-probe.md 的机器档案段）
cat /usr/local/Ascend/driver/version.info     # Version=… / ascendhal_version=…
python3 -c "import torch, torch_npu; print(torch.__version__, torch_npu.__version__)"   # 在容器内
```

**完成标准**：CANN / torch_npu / PyTorch / 驱动四者落在配套表内（参考 `migration-ascend-torchnpu-skills-environment-setup` 类配套表）；`import torch, torch_npu` 成功且版本可打印。**注意** `latest/version.cfg` 可能为空文件，勿靠它取版本。

### 3. 图模式接入与断图定位

- 触发图模式：`npugraph_ex`（昇腾图捕获）或 TorchAir / GE 路径（入口与配置项以引擎/框架文档为准，须上机核实）。
- 录制前提：**静态 shape、静态显存地址（预分配 buffer 用 `copy_()` 更新）、预热、捕获期无 GPU/NPU-CPU 同步、无动态分配、无动态控制流**。
- 断图定位：`TORCH_LOGS=graph_breaks` 查 graph break 点（对应昇腾侧日志机制，等效手段须上机核实）；在 timeline 中找 NPU-CPU 同步点。

**常见断图原因**：

| 原因 | 定位 |
| :--- | :--- |
| GPU/NPU-CPU 同步 | `.item()` / `.cpu()` / `torch.nonzero()` / 基于张量结果的 Python `if`（红线 1） |
| 动态 shape | 输入/中间张量 shape 随 batch/seq 变化 → 分档静态最大网格捕获 |
| 动态控制流 | 捕获期出现数据相关分支 → 重构为静态分支/桶 |
| 未 support 算子 | 昇腾算子缺 graph 支持 → 替换为 torch_npu 融合算子或自研 kernel |

**完成标准**：定位到具体断图原因并给出修复动作；修复后图可稳定录制，replay 不触发重捕获。

### 4. msprobe 精度比对（dump → 比对 → 可视化）

```
msprobe dump --output=/tmp/probe_dump <运行命令>     # 子命令参数以 msprobe --help 为准，须上机核实
```

**完成标准**：dump 出中间张量，与 golden（transformers eager / CUDA 侧）比对，输出精度比对报告（可视化）；定位到首个偏差张量/算子，作为 J6 轨道 A 的输入证据。

### 常见坑

1. **配套混装**：CANN / torch_npu / PyTorch / 驱动任一版本错配即出现诡异的 import 失败或 profiler 不可读；严格按配套表。
2. **拿 `latest/version.cfg` 取版本**：该文件可能为空；用 `cann/version.cfg` 或目录名。
3. **机械平移 CUDA stream/Event 语义**：昇腾的异步发射与同步语义与 CUDA 不同，`torch.npu.Event` 计时在调度/图模式下失真且禁用（[诊断 SOP §2.1](02-ascend-diagnosis-sop.md)）。
4. **图捕获期有动态分配/同步**：热路径 `.item()`、`torch.nonzero()`、动态 shape 都导致断图；先分档静态化再捕获。
5. **把迁移等价性当正确性**：「改造前后对比」只证明没变；正确性必须锚定独立 golden（J1.5 纪律，见 [01 流水线 §3](01-pipeline-and-ledger.md)），并用 `msprobe`/L2 双指标核验。
6. **msprobe 参数照抄旧文档**：子命令与参数随 CANN 版本变动，以 `msprobe --help` 为准（须上机核实）。

---

## vllm-ascend 接入与融合算子替换

vllm-ascend 是本工程主力引擎。模型接入走**注册表 + entry_points 插件**（阶梯 3），融合算子替换落 `workspace/<scenario-id>/source/vllm-ascend/`（阶梯 4）。挂载点索引见 §3.1；引擎与源码落点纪律见 §3 开篇。**类名/接口以实际源码为准**，编码前 grep 实际源码确认，禁止臆造不存在的类名。

### 1. 两段门禁（接入冒烟，J1.5 入口检查点）

- **dummy 快步冒烟**：小权重/随机权重起服务，验证模型可加载、注册路径不报错（不进正确性判定）。
- **真权重强制验证**：换真权重，锚定独立 golden（transformers eager / 官方实现）比对 logits 与 token 序列。

**完成标准**：dummy 快步通过 → 真权重强制验证通过（含 RoPE scaling、attention mask、MoE 路由、tie embedding、量化 scale 反量化等易错点单测）；**「改造前后对比」不作正确性锚点**（J1.5 纪律）。

### 2. 模型接入（register_model + 权重名映射）

- 挂载点：`vllm/model_executor/models/registry.py` 的 `ModelRegistry.register_model("Arch", "my_pkg.models:MyModel")`——**非装饰器**（`register_model` 返回 `None`），须先 `from vllm.model_executor.models.registry import ModelRegistry`；以 `workspace/<scenario-id>/source/vllm/` 实际 pin 版本为准（须上机核实）。
- 权重名映射：safetensors 键名 ↔ 建模层参数名逐层对齐；`config.json` 不被识别的字段（`tie_word_embeddings`、RoPE scaling、MoE 路由、量化 scale 布局）单独处理。

**完成标准**：模型类加载成功，权重名映射无遗漏（加载后无「weight not found」类告警，具体报错形态须上机核实）；非标结构判定落阶梯 3/4。

### 3. 注意力后端注册（勿臆造类名）

- 挂载点：vLLM `vllm/v1/attention/backends/registry.py` 的 `register_backend`——**`class_path=None` 才返回装饰器**；正确写法二选一：装饰器 `@register_backend(AttentionBackendEnum.CUSTOM)`（直接修饰实现类，class_path 自动生成），或命名注册 `register_backend("ASCEND", "my_pkg.attn.AscendAttentionBackend")`——**点号限定名**（上游 `resolve_obj_by_qualname` 用 `rsplit(".", 1)` 解析，冒号形式会 `AttributeError`）。实现为 **`AscendAttentionBackendImpl`**。
- 底层调用昇腾融合注意力 `npu_fused_infer_attention_score`；按平台/头维/KV dtype 分派。

**完成标准**：服务日志/代码路径确认走了 ASCEND 后端而非 fallback（如 naive attention）；`msprof op` 可见融合注意力算子生效。**禁止**臆造昇腾注意力类名——昇腾侧无 FlashAttention 系类名，实现是 `AscendAttentionBackendImpl`。

### 4. 量化配置注册（register_quantization_config）

- 挂载点：`vllm/model_executor/layers/quantization/__init__.py`，继承 `QuantizationConfig` 注册 `@register_quantization_config("method")`。
- 用途：权重加载期转置/重排与低比特路径（ATB 量化解码 / msmodelslim 导出权重，见 [01 §J6 实操](01-pipeline-and-ledger.md)）。

**完成标准**：量化方法被引擎识别，权重加载走注册路径；加载期一次完成重排/反量化（五不准红线 2，前向禁止动态转换权重）。

### 5. entry_points 插件落点（阶梯 3）

vllm-ascend 的 pyproject entry points + 扩展包加载，昇腾专属算子与 hook 以插件形态隔离集成。

**完成标准**：插件落 `workspace/<scenario-id>/optimized/plugins/`（本工程源码落点，不入库），独立加载、不侵入引擎主干；可热替换/回退。

### 6. torch_npu 融合算子替换（阶梯 4）

按 [诊断 SOP §3 瓶颈 1](02-ascend-diagnosis-sop.md) 的「融合度验证」识别未生效的融合算子，在 `workspace/<scenario-id>/source/vllm-ascend/` 的 ops/ 目录替换：

| 算子族 | 替换目标 |
| :--- | :--- |
| 注意力 | FIA（`npu_fused_infer_attention_score`）/ MLA absorb |
| 位置编码 | RoPE 融合 |
| KV 管理 | KV write 融合 |
| 归一化 | QK Norm |
| MoE | GMM（Grouped GEMM） |

**完成标准**：替换后 `msprof op` 确认融合算子生效且有效带宽/耗时改善；按 J6 双轨门禁验收（[门禁规则](../gates/README.md)）。

### 常见坑

1. **臆造注意力后端类名**：昇腾侧不存在 FlashAttention 系类名；昇腾后端实现是 `AscendAttentionBackendImpl`，底层 `npu_fused_infer_attention_score`——编码前 grep 实际源码（`rg -n 'AscendAttentionBackend' workspace/<scenario-id>/source/vllm-ascend/`）。
2. **注册后仍走 fallback**：`register_backend` 只登记，分派还看平台/头维/KV dtype 条件；服务日志确认走了 ASCEND 后端才作数。
3. **config 不识别字段硬塞**：`tie_word_embeddings`、RoPE scaling、MoE 路由等字段须显式处理，否则静默用默认值 → 精度错而加载不报错。
4. **前向动态转换权重**：反量化/`.contiguous()` 必须在加载期一次完成（红线 2）；`.t()` 只改 stride 也会留非连续布局，同样在加载期消除。
5. **只用「改造前后对比」当正确性**：必须锚定独立 golden；两段门禁的**真权重强制验证**不可跳过。
6. **改 `workspace/<scenario-id>/source/` 不 export-patch**：引擎改动以 patch 交付（`bash scripts/manage_repos.sh export-patch <engine> --scenario <scenario-id>`，产物落 `workspace/<scenario-id>/ledger/patches/`，不入库），否则交付不可复现。
