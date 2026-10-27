---
name: atb-tbe-adapter-adapt
description: >
  ATB tbe_adapter 跨 CANN/3rdparty 大版本适配：release compile、stubs/CMake、
  3rdparty 分支对齐、AutoTiling 隔离、CSV/加载运行时验证与 pack。
  用于 tbe_adapter / libtbe_adapter 编译或加载失败、ops-nn/canndev/metadef/opbase
  等 release 依赖仓与 CANN 不同步，或 CANN 升级后 tbe 相关 csv（如 ScatterElementsV2、
  elewise、activation）失败等场景。
keywords:
  - atb
  - tbe_adapter
  - libtbe_adapter
  - cann
  - 3rdparty
  - ops-nn
  - canndev
  - metadef
  - opbase
  - asc-devkit
  - release.sh
  - AutoTiling
  - 适配
metadata:
  version: "1.1.0"
  updated: "2026-07-20"
  skill-type: adaptation
---

# ATB tbe_adapter 依赖适配与运行时闭环

## 目标

1. 按项目根目录 **`<项目根>/3rdparty/` 下列依赖仓** + 项目 CANN，适配 `ascend-transformer-boost/src/kernels/tbe_adapter`，使 **`scripts/release.sh compile`** 通过。  
   这些仓经软链接到 `ascend-transformer-boost/3rdparty/`（`air`≡`ge`）；**不是**泛指 ATB 树里所有第三方（MKI/googletest 等另算）。
2. 对齐 **3rdparty 分支与 CANN 版本**，避免 host tiling 与预置 device bin 契约不一致。
3. 完成关键用例运行时验证（csv / 加载），必要时出 `.run` 包供安装验证。

大版本切换（如 ops-nn `9.0.0`→`9.1.0`）以 **ATB 编译/运行报错为修改入口**；对照两版本差异，但禁止全量预改依赖仓。

### 根目录 3rdparty 依赖仓（摘要）

路径：`<项目根>/3rdparty/<名>`。出包调试（`PACKAGE_COMPILE=ON`）核心相关：

| 相关性 | 仓名 |
|--------|------|
| 高 | `ops-nn`、`canndev`、`metadef`、`opbase`、`ge`（ATB 侧 `air`）、`asc-devkit` |
| 中 / 按需 | `ops-math`、`ops-transformer` |

**权威表**（origin URL、软链名、分支策略、核对命令）只维护在 [references/reference.md](references/reference.md)「3rdparty 仓库地址与维护」。仓迁移/改名时**只改 reference**，并同步本摘要名单。

## 硬性约束

1. **报错驱动**：哪里报错改哪里；没报错先不管。
2. **版本基准**：对比用用户指定源/目标分支；改代码跟错误走。
3. **3rdparty 只切分支不改内容**：除 `git checkout` 外禁止改上表依赖仓内容；路径/符号一律在 ATB（主要 `tbe_adapter`）消化。`release.sh` 允许的 stub 头拷贝（如 `plugin_manager.h`）除外。
4. **3rdparty 分支必须匹配 CANN（核心仓）**：`ops-nn` / `canndev` / `metadef` / `opbase` / `ops-math` 须与 CANN 同一发布线。**ops-nn 停在 master 而 CANN 为发布包时，易导致 host tiling 与 opp 预置 bin 不匹配**。`ge`/`asc-devkit` 优先切同线分支；若无对应 release 分支且已编过，可保持现状并在报告中注明。
5. **仓库地址以 reference 权威表为准并随仓变更更新**。
6. **出包调试看 if 分支**：`PACKAGE_COMPILE=ON` 且非 local 时，只关心 CMake if 为 true 用到的依赖。
7. **多选先问 / 缺资源先问**。
8. **经验回流**：有效步骤与坑点回写本 skill 与 references。每次适配结束写报告时，**评估是否需要改 skill**；若需要，必须在报告中设专节**通知用户**（见「报告与 skill 回写」），由用户确认后再改 skill（或用户明确授权当场改）。
9. **终验**：清 `build` 缓存后 `bash scripts/release.sh compile --use_cxx11_abi=<与 torch 一致>`。
10. **按机器裁剪芯片**：`build_config.json` / `op_list.yaml` 仅开本机芯片；**勿提交**本地裁剪配置与 `utils.cpp` 自动改动。
11. **临时调试改动要还原**（注释 toolkit `set_env`、跳过清缓存等）；适配性脚本改动保留并写入报告。

> **临时 vs 保留**：注释默认 toolkit `set_env`、跳过清 `$CACHE_DIR`、MKI 强制 source toolkit → 终验后**恢复**。去掉 cann-ops-adv 检查、`tiling` 用 `ln -snf`、不向软链仓批量 `cp` stubs、CMake/stubs/AutoTiling 等 → **保留**并写入报告。

## 架构要点（必懂）

| 部件 | 来源 | 说明 |
|------|------|------|
| Host tiling | **链进** `libtbe_adapter.so`（`OPS_SOURCE` / canndev tiling） | 运行时**不会**再从 OPP 另取一份 host tiling 实现 |
| Device bin | `ASCEND_KERNEL_PATH`（CANN opp）→ `build_util.py` 嵌入 `libasdops.so` | 正常 `release.sh` **不重编** AscendC kernel，只打包预置 `.o`+`.json` |
| 契约 | tilingData 布局 + `tilingKey` 集合 | host `GetDataSize` ≤/`兼容` bin `opParaSize`；key 必须在 bin json 内 |

典型踩坑：发布线 CANN bin + 超前 `ops-nn`（如 master）。先切同线分支，勿长期 `ops_override`。核对步骤见 reference「Host tiling ↔ Device bin」。

## 适配范围

| 纳入 | 说明 |
|------|------|
| `tbe_adapter/CMakeLists.txt` | 源列表、include、链接选项（含 AutoTiling 隔离） |
| `tbe_adapter/` 自有代码 | platform、tiling_runner、include |
| `tbe_adapter/stubs/` | 固定依赖实现、error_manager、AutoTiling 注册表 |
| `configs/.../tbe_tactic_info.ini` | tactic 歧义时补 `attrs=`（可提交） |
| 为编过所需的软链/`release.sh` 适配改动 | 见 references |

| 默认不纳入 | 说明 |
|------------|------|
| `3rdparty/*` 内容修改 | 仅允许切分支 |
| `utils.cpp` / 本地 `build_config` / `example/op_demo` | 勿提交 |
| 无关 UT 小修 | 除非用户要求 |
| 通信算子（AllGather 等） | 走 HCCL/LCCL/`lcal`，与 tbe_adapter 无直接关系 |

## 工作流

```
Task Progress:
- [ ] 0. 确认源/目标版本、CANN、3rdparty 均切到目标分支
- [ ] 1. 本地编译前置（软链 + 可选临时脚本 + 按机器裁剪）
- [ ] 2. release.sh compile（调试期可不清缓存），收集报错
- [ ] 3. 报错 → 对照版本差异 → 最小修改（ATB 侧）
- [ ] 4. 重编直到 compile 通过
- [ ] 5. 终验：清缓存 + release.sh compile
- [ ] 6. 运行时验证（加载 + csv 子集 + Scatter 等契约算子）
- [ ] 7. 需要安装验证时 pack（见下）
- [ ] 8. 修改报告（含 skill 回写评估）+ 恢复临时调试；若建议改 skill 则通知用户
- [ ] 9. pre-commit 格式化相关文件后提交（作者与既有 commit 一致）
- [ ] 10. 用户确认后回写 skill（若适用）
```

### 0. 确认资源与分支

- 依赖名单见上文摘要；URL/软链/核对命令见 [references/reference.md](references/reference.md)。仓地址变了先改 reference。
- 映射：`create_softlink.sh`（`air`≡`ge`，`cann`→`canndev` 等）。
- CANN：`source <用户指定>/ascend-toolkit/set_env.sh`。
- **强制检查**：核心仓当前分支是否等于目标发布线，不要误用 `master`。`ge`/`asc-devkit` 有同线分支则切，否则注明现状。

### 1–5. 编译适配

报错驱动改 CMake/stubs/platform；终验清缓存。类目与改法见 [references/reference.md](references/reference.md)「编译报错类目速查」；前置脚本见同文件「本地编译前置」。

要点：

- **ABI**：`--use_cxx11_abi=` 与本机 torch 一致；混用易 `asdops_sym_check` 失败（调用参数问题）。
- **tactic**：`update_tbe_tactic_json` 歧义时可在 `tbe_tactic_info.ini` 补 `attrs=`（可提交）。
- **边界**：缺 `torch_npu` 仅影响 `torch_atb`/wheel，**不等于** tbe 适配失败。

### 6. 运行时验证

在用户指定环境执行。清单与契约核对见 [references/reference.md](references/reference.md)「运行时最小验收」「Scatter 契约核对」「AutoTiling 与系统 liboptiling 隔离」。

环境注意：

- **驱动 vs CANN**：不匹配可能 `aclrtSetDevice` 挂死；冒烟可用匹配驱动的 CANN，**终验须目标 CANN + 匹配驱动**。
- 验证前同步出包 so 到 `output/.../lib`（`build.sh` 见已有 so 会跳过拷贝）。
- csv 需 `PYTHONPATH` 含 CANN `tbe`。

分诊摘要（细节在 reference）：

| 现象 | 方向 |
|------|------|
| 加载期 SIGSEGV / `RegisterFormatErrorMessage` | stubs `error_manager` 强定义 |
| elewise/activation 与系统 `liboptiling` 搅在一起 | AutoTiling 隔离（`AsdOps*` + 链接选项） |
| csv 正例大量 `INVALID_PARAM` / tilingdata / tilingKey | 先对齐 `ops-nn` 等与 CANN 同线分支，再谈 override |

### 7. Pack

`release.sh pack` 只打包当前 `output/`，不 compile。缺完整树时用已安装树重建后再覆盖最新 `libtbe_adapter.so`。细节见 reference「Pack 注意」。

### 8–9. 报告、格式、提交

- 修改报告落盘到约定位置（如项目内 `adaptation-report-<ver>.md`）。**实践记录（绝对路径、容器名）勿写入本 skill 仓**。
- **报告末尾必须含「skill 回写评估」**；若建议改 skill，对话中再次提醒用户。
- `pre-commit run --files ...`；格式变更单独 `style:` commit。
- Commit 作者与**该分支既有适配提交**一致；勿加入无关本地文件。

### 报告与 skill 回写

每次适配结束评估是否改 skill。报告增加：

```markdown
## N. skill 回写评估

| 项 | 内容 |
|----|------|
| 是否建议修改 skill | 是 / 否 |
| 建议改动的文件 | SKILL.md / references/…（否可填「无」） |
| 建议改动摘要 | … |
| 理由 | 本次适配中发现的… |
| 用户确认 | 待确认 / 已确认并已回写 |
```

- **否**：说明现行 skill 已覆盖即可。
- **是**：**不得静默改 skill**；写清建议并通知用户，确认后再回写。

## stubs（摘要）

固定部分依赖以产出 `libtbe_adapter.so`。要点：stubs include 优先；guard 与真实头同名；除 `release.sh` 显式拷贝外不向软链仓 `cp`。细则见 reference「stubs 与软链 canndev」。

## 完成后检查

- [ ] 3rdparty 目标分支与 CANN 一致（非误用 master）
- [ ] `release.sh compile` 终验通过（清缓存、ABI 正确）
- [ ] 加载无弱符号崩溃；最小验收套件通过（见 references「运行时最小验收」）
- [ ] 修改报告已给出，且含 **skill 回写评估**；若建议改 skill 已通知用户
- [ ] 临时调试已恢复；pre-commit 已过；无关文件未提交
- [ ] 用户确认后的 skill 回写已完成（若适用）
