# tbe_adapter 适配参考

随实践更新。SKILL.md 只保留流程；细节放这里。

## 目录与产物

| 路径 | 说明 |
|------|------|
| `ascend-transformer-boost/src/kernels/tbe_adapter/` | 适配主目录 |
| `.../CMakeLists.txt` | 依赖源文件与 include 的核心清单 |
| `.../stubs/` | 固定依赖仓部分实现 |
| `.../platform/`、`tiling_runner/`、`include/` | ATB 自有适配代码 |
| `libtbe_adapter.so` | 典型产物（如 `output/atb/cxx_abi_1/lib/`） |

## 3rdparty 仓库地址与维护（权威表）

> **维护**：依赖仓增删、改名、换 hosting 或 `origin` URL 变化时，**只更新本表**，并同步 [SKILL.md](../SKILL.md) 中的仓名摘要名单。

| 本地目录（`<项目根>/3rdparty/`） | origin URL | ATB 内链到 | 与 CANN 同线时典型分支 | tbe 相关性 |
|----------------------------------|------------|------------|------------------------|------------|
| `ops-nn` | https://gitcode.com/cann/ops-nn.git | `.../3rdparty/ops-nn` | 如 `9.1.0` | 高（host tiling，如 Scatter） |
| `canndev` | https://gitcode.com/cann/canndev.git | `.../3rdparty/canndev` | 如 `9.1.0` | 高（op_tiling 主体） |
| `metadef` | https://gitcode.com/cann/metadef.git | `.../3rdparty/metadef` | 如 `9.1.0` | 高 |
| `opbase` | https://gitcode.com/cann/opbase.git | `.../3rdparty/opbase` | 如 `9.1.0` | 高 |
| `ops-math` | https://gitcode.com/cann/ops-math.git | `.../3rdparty/ops-math` | 如 `9.1.0` | 中 |
| `ge` | https://gitcode.com/cann/ge.git | `.../3rdparty/air`（`air`≡`ge`） | 有同线分支则切；否则跟编过即可 | 高（graph_metadef） |
| `asc-devkit` | https://gitcode.com/cann/asc-devkit.git | `.../3rdparty/asc-devkit` | 有同线分支则切；否则跟编过即可 | 高（tiling API） |
| `ops-transformer` | https://gitcode.com/cann/ops-transformer.git | （按需；出包 if 未必用） | 视算子 | 低～中 |

说明：

- **范围**：上表是 tbe_adapter 适配所说的「根目录 3rdparty」；不含 ATB 自带的 MKI / googletest / nlohmannJson 等。路由本 skill 时优先匹配这些仓名 + `tbe_adapter` / `libtbe_adapter` / `release.sh`，而非单个算子名。
- **canndev**：远程可能无个人读权限，依赖本机已有 clone；无法 fetch 时用本地已有 `origin/<目标分支>` 等 ref。
- **出包不需要**：`api`、`cann-ops-adv`/`ops_adv`（出包 if 分支应去掉强依赖检查）。

核对命令：

```bash
ROOT=<项目根>/3rdparty
for d in ops-nn canndev metadef opbase ops-math ge asc-devkit ops-transformer; do
  echo -n "$d: "; git -C "$ROOT/$d" remote get-url origin
  git -C "$ROOT/$d" branch --show-current
done
```

## 3rdparty 名称映射

以项目根 `create_softlink.sh`（或等价脚本）为准；实际使用时应对准当前 ATB 树。

| CMake / ATB 侧期望名 | 根目录 `3rdparty` 实际名 | 接入方式建议 |
|----------------------|--------------------------|--------------|
| `canndev` | `canndev`（脚本或写 `cann`） | `ln -snf` |
| `metadef` | `metadef` | `ln -snf` |
| `air` | **`ge`**（`air`≡`ge`） | `ln -snf ge air` |
| `api` | `api` | **出包调试不需要** |
| `cann-ops-adv` | `ops_adv` | **已从 release.sh/CMake 去掉** |
| `opbase` | `opbase`（或 `ops-base`） | `ln -snf` |
| `ops-nn` / `ops-math` / `asc-devkit` | 同名 | `ln -snf` |

CANN 包内软链（脚本后半段，依赖 `ASCEND_HOME_PATH`）：

- 将 `ascend910b/ops_{legacy,math,nn,transformer}/*` 链到 `ascend910b/`（芯片目录按目标机型）
- `pkg_inc/toolchain/dlog_pub.h` → `pkg_inc/base/dlog_pub.h`（若 9.x 布局需要）
- toolkit 装完后目标芯片目录可能仅有部分 `ops_*`；其余由 **ops 包**装入后再做 softlink

## 出包调试分支（PACKAGE_COMPILE=ON 且 LOCAL_RELEASE_COMPILE≠ON）

`release.sh compile` 默认：`PACKAGE_COMPILE=ON`，`LOCAL_RELEASE_COMPILE=OFF`（除非传 `--local_release_compile`）。
此时走 CMake **if 为 true** 的分支。出包调试只关心该分支用到的文件。

| 依赖 | CMake if 为 true | CMake else（含 local） | `release.sh` `fn_build_tbe_dependency` | 出包调试 |
|------|------------------|------------------------|----------------------------------------|----------|
| `3rdparty/api` | **不使用**（`TILING_API_SRCS` 用 asc-devkit） | 使用 | 不检查 api 仓 | **不需要** |
| cann-ops-adv | 无后续引用或已移除 | 同左 | **已移除存在性检查** | **不需要** |
| `asc-devkit` | tiling API + gen 脚本 | 否 | `tiling` → `ln -snf include/adv_api`（勿 `cp`） | **需要** |

注意：当前 `fn_build_tbe_dependency` **不再**向软链 canndev/air 批量 `cp` stubs；仅：

1. `ln -snf include/adv_api` → `asc-devkit/tiling`
2. `cp` stubs 的 `plugin_manager.h` → `metadef/inc/common/plugin/`
3. `ln -snf` asc-devkit `impl`

向 metadef 拷头与「3rdparty 只切分支不改内容」略有冲突：属 `release.sh` 既定行为，适配时保留；勿再扩大对 3rdparty 的写入面。

## PACKAGE_COMPILE 分支注意

| 条件 | metadef / tiling API 倾向 |
|------|---------------------------|
| `PACKAGE_COMPILE=ON` 且非 local | `metadef/base` + `air(ge)/graph_metadef` + `asc-devkit/impl/adv_api` |
| else（含 local release） | 旧式 `metadef/exe_graph|graph|register` + `3rdparty/api` |

新版本 metadef 常偏 `base/` 布局。**仅在对应分支编译报错时再改**，不要预先整表重写。

## 已知路径漂移示例（9.0 → 9.1，报错时再改）

| 旧路径 | 新现状（示例） |
|--------|----------------|
| `ops-nn/.../scatter_elements_v2/op_host/scatter_elements_v2_tiling.cpp` | 拆到 `op_host/arch22/`、`op_host/arch35/` |
| `ops-math/common/src/op_host/tiling_util.cpp` | 迁到 `opbase` 等 |
| `canndev/.../reverse_v2_tiling_arch35.cpp` | 目标发布线可能已删除；CMake 中去掉对应 `OPS_SOURCE` 条目 |

```bash
git -C 3rdparty/ops-nn ls-tree -r --name-only origin/<源分支> -- index/scatter_elements_v2/op_host/
git -C 3rdparty/ops-nn ls-tree -r --name-only origin/<目标分支> -- index/scatter_elements_v2/op_host/
```

## 编译报错类目速查

按报错类型最小改 ATB 侧（禁止改 3rdparty 内容）：

| 类目 | 典型现象 | 改哪里 |
|------|----------|--------|
| **源路径漂移** | `No such file`：scatter / tiling_util / 某 arch 专用 cpp | `tbe_adapter/CMakeLists.txt` 的 `OPS_SOURCE`：改到新路径，或删掉目标分支已不存在的条目（如 reverse arch35） |
| **头路径 / 布局** | 找不到 `metadef/...`、`graph_metadef`、tiling API | 确认走 `PACKAGE_COMPILE` if 分支；补 include（常需 CANN `include/base`）；`asc-devkit` 的 `tiling`→`ln -snf include/adv_api` |
| **stub 未覆盖** | 同目录 `#include "xxx.h"` 仍进真实头 / ODR 冲突 | stubs include **先于** 真实路径；stub 头 **include guard 与真实头同名** |
| **缺链接符号** | undefined reference：`GetViewErrorCodeStr`、`GetPaddingSize`、error_manager 等 | 在 `tbe_adapter/stubs/` 补强定义或 shim（如 `external/base/err_msg.h`） |
| **SocVersion** | 枚举未声明（如新芯片宏） | ATB `platform_ascendc.h` 补枚举 |
| **release 依赖检查** | 缺 cann-ops-adv / api | 出包 if 分支本就不需要：去掉强检查；tiling 用软链而非 `cp` |
| **tactic / bin 嵌入** | `update_tbe_tactic_json` 歧义或匹配失败 | `configs/ops/tbe_tactic_info.ini`（及 mixops 若涉及）为算子补 `attrs=`；可提交。并确认本机芯片在 `build_config`/`op_list` 中已开启（本地裁剪勿提交） |
| **ABI 不一致** | `asdops_sym_check` 或 MKI/ATB 符号对不上 | `release.sh compile --use_cxx11_abi=<与 torch 一致>`；勿混用 ABI0/ABI1 产物 |
| **torch_atb 阶段** | 缺 `torch_npu` 导致 wheel/绑定失败 | 与 `tbe_adapter` 无关；有 so 且 tbe 编过即可先验收适配 |

对照源/目标分支找文件：

```bash
# 示例：某源文件在目标分支是否还在、迁到哪
git -C <项目根>/3rdparty/<仓> ls-tree -r --name-only origin/<目标分支> | grep -E 'scatter_elements|tiling_util|reverse_v2'
```

## 本地编译前置（按内容匹配）

### release.sh：注释默认 toolkit 环境段

匹配类似内容（勿依赖行号；以下为脚本内常见片段）：

```bash
cann_default_install_path="/usr/local/Ascend/ascend-toolkit"

set +e
if [ -d "${cann_default_install_path}" ];then
    source /usr/local/Ascend/ascend-toolkit/set_env.sh
else
    export ASCEND_HOME_PATH=...
    export LD_LIBRARY_PATH=${ASCEND_HOME_PATH}/lib64:${LD_LIBRARY_PATH}
fi
set -e
```

本地已配置 `ASCEND_HOME_PATH` 时可整段注释，避免覆盖（**临时**；终验后恢复）。

### MKI build.sh：release 强制 toolkit

`3rdparty/Mind-KernelInfra/scripts/build.sh` 中 `fn_build` 内类似强制 `source` toolkit 的逻辑：本地已有环境时按需临时跳过，终验后恢复。

### 可选：加快调试

- ATB `release.sh` / MKI：`fn_build` 里对 `$CACHE_DIR` 的 `rm -rf` 可临时去掉；**终验前必须重新启用**。

### op_list.yaml / build_config.json（按机器）

- **必须按当前机器芯片裁剪**；换机器验证时改对应芯片，不要照搬他机配置。
- 本地裁剪**勿提交**进交付分支。

## canndev / 3rdparty 分支

- 编译 `tbe_adapter` 大量依赖 `canndev/ops/built-in/op_tiling` 与部分 `ops/` 下 tiling。
- `stubs` 仅覆盖少量固定实现，**不能**替代完整 canndev。
- **禁止改仓内内容**；只允许切分支。
- 核心仓（ops-nn / canndev / metadef / opbase / ops-math）应与目标 CANN 同发布线。

`metadef` 若有本地 `plugin_manager.h` 脏改动：可 stash；`release.sh` 会从 stubs 再拷一份。

## Host tiling ↔ Device bin

```text
ops-nn（等）host tiling.cpp  ──编译──►  libtbe_adapter.so   (GetDataSize / SetTilingKey)
CANN opp 预置 .o+.json       ──嵌入──►  libasdops.so        (opParaSize / kernel keys)
```

| 对齐情况 | 结果 |
|----------|------|
| 同发布线 | host size ≤ bin；tilingKey 落在 bin 集合内 |
| ops-nn 超前（如 master） | size 偏大 → memcpy 失败；或 CacheOp 生成 bin 中不存在的 key |

**结论**：先对齐分支；ATB `ops_override` 只作短期止血，对齐后删除。默认**不要**重编 AscendC device bin；先对齐 3rdparty。

### Scatter 契约核对（csv 正例大量 INVALID_PARAM 时）

1. 确认核心仓（尤其 `ops-nn`）已在与 CANN 同线的发布分支，而非 `master`。
2. 从 CANN opp 取出该算子 json，读 `opParaSize` / `kernelList`（或等价字段）里的 tilingKey 集合。
3. 对照 host：当前编进 `libtbe_adapter` 的 tiling 源，其 `GetDataSize()`（或结构体大小）应 **≤** `opParaSize`；`SetTilingKey` 结果须落在 bin 的 key 集合内。
4. 若曾加 ATB `ops_override` / 人为垫高 tiling buffer：分支对齐后应删除，回链 ops-nn 对应 arch 下源文件。

CSV 判读：`ExpectedError=NO_ERROR` 的正例失败才是功能回归；`ExpectedError` 为 `ERROR_*` 的反例即使 `result: fail` 也会记为 Passed（Yes）。

## 运行时最小验收

验证前：

```bash
# 将安装树/出包 lib 同步到源码树 output（路径按本机替换）
# build.sh 若发现 output 已有 so 会跳过拷贝
PKG=<ATB安装或res>/.../cxx_abi_<N>/lib
OUT=<ATB源码树>/output/atb/cxx_abi_<N>/lib
for lib in libtbe_adapter.so libatb.so libasdops.so libmki.so; do
  [ -f "$PKG/$lib" ] && cp -f "$PKG/$lib" "$OUT/$lib"
done
```

加载自检（示意）：

- `nm -D libtbe_adapter.so | grep RegisterFormatErrorMessage` → 应为强定义（`T`），不是空弱引用。
- 按需 `dlopen` 链路：`libmki` → `libtbe_adapter` → `libatb` 无 SIGSEGV。

推荐最小套件（在用户指定环境；驱动与 CANN 至少一组可 `aclrtSetDevice`）：

| 顺序 | 项 | 目的 |
|------|----|------|
| 1 | 加载自检 | 弱符号 / AutoTiling 隔离 |
| 2 | csv elewise / activation / linear **子集**（如 `-n 1:5` 或 `1:10`） | 通用 tbe 路径 |
| 3 | csv ScatterElementsV2 **全量**（或至少全部 `NO_ERROR` 正例） | host↔bin 契约 |
| 4 | 可选：`atb_cinterface` / `pythontest` 单测 / `torch_atb` 冒烟 | 框架与绑定 |

环境注意（通用）：

- `PYTHONPATH` 须含 CANN 的 `tbe`，否则 csv 可能因 `No module named 'tbe'` 间接失败。
- 目标 CANN 与驱动不匹配时 `aclrtSetDevice` 可能挂死：可用匹配驱动的 CANN 做冒烟，**终验仍须目标 CANN + 匹配驱动**。
- 缺 `torch_npu` 时跳过 `torch_atb`，不据此判 tbe 适配失败。

## AutoTiling 与系统 liboptiling 隔离

症状：activation/elewise 等加载或首跑崩溃；与 `liboptiling.so` 的 `AutoTilingRegister` 经 `STB_GNU_UNIQUE` 合并。

ATB 侧做法：

1. stub：`AsdOpsAutoTilingRegister` + 出线 `RegisterTiling/Parser`
2. include guard 与 canndev 真实头一致（如 `OPS_BUILT_IN_OP_TILING_AUTO_TILING_REGISTER_H_`）
3. CMake：`-include` stub 头、`-fno-gnu-unique`、`-Wl,-Bsymbolic`、`--version-script=stubs/auto_tiling_register.version`

## Pack 注意

| 点 | 说明 |
|----|------|
| `pack` 不含 compile | 只 makeself 当前 `output/` |
| 完整树 | 需 include/bin/lib/configs/whl 等；可用已安装树重建后再覆盖新 `libtbe_adapter.so` |
| 产物 | `output/<arch>/Ascend-cann-atb_<ver>_linux-<arch>.run` |
| 旧 run | 不含事后增量 so；安装验证前核对 md5/时间 |

## stubs 与软链 canndev（重要）

软链后禁止改仓时：

1. **include 顺序**：stubs 下 canndev/ops、ops/common、ops/common/inc、air/graph_metadef 放在对应真实路径之前。
2. **include guard 对齐**：stub 的 `#ifndef` 必须与真实头文件相同。
3. **shim**：需要时在 `stubs/include/external/base/err_msg.h` 等包一层。
4. **不要**把 `stubs/include/metadef` 整体提到最前。
5. **AutoTiling**：`-include` 预占 guard，防止 canndev 同目录真实头抢先。
