#!/usr/bin/env bash
# sync_ascend_skills.sh — allowlist 驱动：从 13 个昇腾生态源仓（21 条规则）发现并同步 SKILL.md 技能目录
# 优先级说明：本表是筛选过的 allowlist（上游 500+ → 21 条规则）；include 用逗号分隔 glob；
#      Triton 一律由 denylist 兜底排除；算子开发优先级 AscendC > TileLang > PyPTO/CATLASS。
# 落点（平铺）：.agents/skills/<技能目录名>/（不再有 external/<category>/<name>/ 层级）
# 缓存：.cache/skills/<url-slug>/（同一 URL 多行规则共享，只 clone/fetch 一次）
# 规则：include 为逗号分隔 glob，同时尝试匹配技能目录相对路径与目录名
#      （* 不跨 /，** 跨 /）；目录名/相对路径含 triton（不区分大小写）→ SKIPPED；
#      来源标记：同步成功写 .agents/skills/.origins/<目录名>（内容=origin，被 .gitignore 忽略）。
#      已存在判定：被 git 跟踪 → CONFLICT 绝不覆盖；标记同源 → 刷新（先安全删除再拷）；
#      标记异源/无标记：同名技能近似相同（near_identical）→ CONFLICT 保留权威源（先到先得）；
#      实质不同 → 改名为 <origin>--<name> 并存（frontmatter name: 同步改写，RENAMED 计数）；
#      --force 仅对「已存在且异源/无标记」强制覆盖原目录（不改名），仍不覆盖被 git 跟踪的。
# 持续更新：每次同步即刷新到上游分支最新；--update-lock 把上游 commit 记录到 scripts/skills.lock
#      （入库、随仓库跟踪）；--verify 校验磁盘/缓存与 lock 一致（CI 可用）；--pinned 按 lock 检出
#      指定版本复现。--prune 清陈旧：删除「有 .origins 标记但本次未命中任何 include」的目录。
# 变更报告：末尾按 ADDED/REFRESHED/RENAMED/CONFLICT/SKIPPED/REMOVED 分组打印名称清单；
#      --report <path> 另写 TSV（type<TAB>name<TAB>origin）。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
CACHE_DIR="$ROOT/.cache/skills"
DEST_ROOT="$ROOT/.agents/skills"

ADDED=0
REFRESHED=0
RENAMED=0
SKIPPED=0
CONFLICT=0
REMOVED=0
FAIL=0
DEAD_GLOBS=0
ORIGINS_DIR="$DEST_ROOT/.origins"
REPORT_ROWS=""
TOUCHED=""
CURRENT_ORIGINS=""
FAILED_ORIGINS=""

# 源表：origin|url|branch|include|note（# ===== 注释行为分组标记：开发/运维/门禁，勿当数据行）
skill_sources() {
  cat <<'EOF'
origin|url|branch|include|note
# ===== 开发（算子 / 模型接入 / 图模式 / 线性注意力）=====
agent-skills-dev|https://gitcode.com/Ascend/agent-skills.git|master|ascendc-operator-code-gen,ascendc-operator-compile-debug,ascendc-operator-design,ascendc-operator-dev,ascendc-operator-doc-gen,ascendc-operator-mssanitizer,ascendc-operator-performance-eval,ascendc-operator-performance-optim,ascendc-operator-precision-debug,ascendc-operator-precision-eval,ascendc-operator-project-init,ascendc-operator-testcase-gen,ascendc-operator-A5-migration,ascendc-operator-st-gen,tilelang-vector-ascend-ops-migration|AscendC 算子开发 14 件套 + TileLang 迁移
agent-skills-atb|https://gitcode.com/Ascend/agent-skills.git|master|atb-*|ATB/ACLNN 迁移与调试
agent-skills-catlass|https://gitcode.com/Ascend/agent-skills.git|master|catlass-operator-*|CATLASS 模板算子
tilelang|https://github.com/tile-ai/tilelang-ascend.git|ascendc_pto|tilelang-op-*,tilelang-pass-*,tilelang-perf-*,tilelang-ascend-tile-api,tilelang-a5-sim-convert,**/tilelang-custom-skill/*|TileLang 全栈（含 Pass 层）
pto|https://github.com/huawei-csl/pto-kernels.git|main|testing-pto-kernels|PyPTO 双代算子参考
xllm-tilelang|https://github.com/xLLM-AI/xllm-workflow.git|main|tilelang-pto-kernel-workflow|TileLang+PTO 工作流
cannbot-model|https://github.com/ascend-ai-coding/awesome-ascend-skills.git|main|external/cannbot/model/*|model-infer-* 模型级优化
cannbot-ops|https://github.com/ascend-ai-coding/awesome-ascend-skills.git|main|external/cannbot/ops/*,external/cannbot/ops-lab/tilelang/**|AscendC 最佳实践 / PyPTO / npu-arch
cannbot-graph|https://github.com/ascend-ai-coding/awesome-ascend-skills.git|main|external/cannbot/graph/*|npugraph_ex 图模式
fla|https://github.com/fla-org/flash-linear-attention.git|main|fla-ascend-performance,fla-optimization-loop,fla-correctness-coverage|线性注意力昇腾性能闭环
# ===== 运维（性能诊断 / 通信 / 服务化 / 部署）=====
msagent-profiler|https://github.com/kali20gakki/msAgent.git|master|skills/profiler/*|profiler 全家桶（prof-compare/快慢卡/msprof-analyze）
msagent-operator|https://github.com/kali20gakki/msAgent.git|master|skills/operator/*,compare-result-analyzer,deterministic-calculation-analysis,precision-debugger|msdebug/mssanitizer/mstx/ops 调优 + 整网精度/确定性
agent-skills-ops|https://gitcode.com/Ascend/agent-skills.git|master|hccl-test,ascend-profiling-anomaly|HCCL 基线 + profiling 异常
agent-skills-host|https://gitcode.com/Ascend/agent-skills.git|master|npu-smi,ascend-docker,cann-operator-env-config,atc-model-converter,npu-adapter-reviewer,vllm-ascend-deploy|主机/容器/环境/ATC
god|https://github.com/XiaoLuoLYG/GOD.git|main|deepep-to-cam-converter,ascend-moe-optimizer-*|DeepEP→CAM / MoE 优化追踪
mindie-motor|https://github.com/Ascend/MindIE-Motor.git|master|motor-*|PD 分离服务全生命周期
xllm-ops|https://github.com/xLLM-AI/xllm-workflow.git|main|xllm-npu-benchmark,xllm-npu-profiler,xllm-npu-incident-triage,xllm-npu-capacity-planner,xllm-npu-compute-simulation,xllm-npu-pipeline-analysis,xllm-npu-server-manager,xllm-npu-sota-loop,xllm-npu-code-review,xllm-npu-build-gate,xllm-npu-report-writer,xllm-experiment-lifecycle,xllm-npu-accuracy-debug,xllm-npu-xllm-ops-integration,xllm-npu-batch-perf|xLLM NPU 运维（profiler/benchmark/incident）
vllm-ascend|https://github.com/vllm-project/vllm-ascend.git|main|vllm-ascend-*|官方插件（model-adapter/release）
sglang-npu|https://github.com/LinyuanLi0046/Ascend-SGLang-Skills.git|main|npu-api-adaptation-checker,sglang-npu-adapter,test-regression-pr-locator|SGLang-NPU 适配检查
# ===== 门禁（量化 / 精度 / 性能）=====
msmodelslim|https://gitcode.com/Ascend/msmodelslim.git|master|quantization,tuning,sensitive-layer-analysis|量化与 evaluate/tuning
mindie-sd-gate|https://github.com/Ascend/MindIE-SD.git|dev|accuracy-gate,perf-gate,quantization-dev,profiling-collect,performance-optimization|L1/L2/L3 与探索态/验收态
EOF
}

usage() {
  cat <<'EOF'
用法: sync_ascend_skills.sh [选项]

allowlist 驱动：从 13 个昇腾生态源仓（21 条规则）发现并同步 SKILL.md 技能目录。
平铺落点：.agents/skills/<技能目录名>/；缓存复用 .cache/skills/<url-slug>/。

选项:
  --list
      离线列出源表：按 开发 / 运维 / 门禁 分组，每行 origin / url / branch /
      include / note，末尾合计条数（不访问网络，不建目录）。
  --category <dev|ops|gate|all>
      按源表分组过滤要处理的规则行（默认 all）。
  --only <origin>
      仅处理 origin 匹配的规则行（可与 --category 组合）。
  --dry-run
      执行克隆/复用缓存与匹配，但不拷贝，只列出将同步的技能（含目标路径）；
      并逐 include glob 自检命中数，0 命中的 glob 计为 DEAD_GLOBS。
  --force
      仅对「已存在且来源标记异源/无标记」的目标强制覆盖（先安全删除再拷贝）；
      被 git 跟踪的入库技能无论何种情况都不覆盖。
  --prune
      清陈旧：删除「由本脚本安装（.agents/skills/.origins/<name> 存在）但本次
      未命中任何 include」的目录。安全护栏：① 只对本次过滤后的 origin 集合生效
      （.origins 内容不属于本次 --category/--only 过滤后的集合则不删）；② 被 git 跟踪
      的 5 个入库技能绝不删（git ls-files --error-unmatch 判定）；③ 仅允许单层目录名
      （非空、非 ./..、不含 /）并复核 [ -d ] 后才删；④ .agents/skills/README.md 永不删。
      只允许与 --category all（或不指定，默认 all）一起使用；与 --only 互斥（违规 exit 1）。
      --dry-run --prune 只列出 WOULD REMOVE，不删除；删除的目录计入 REMOVED。
  --report <path>
      把本次变更报告按 ADDED / REFRESHED / RENAMED / CONFLICT / SKIPPED / REMOVED
      分组，以 type<TAB>name<TAB>origin 写 TSV 到 <path>（不截断到 50 个），便于 diff/审阅。
  --update-lock
      正常执行一次同步后，把 13 个上游仓的 (url, branch, commit) 与磁盘上 .origins 标记的
      (name, origin) 写入 scripts/skills.lock（入库、随仓库跟踪；commit 取 .cache/skills HEAD；
      默认全量同步，建议不要与 --category/--only 组合）。仅同步成功（FAIL=0）时写 lock。
  --verify
      只读自检（不联网、不改文件）：磁盘 .origins 与 lock 的 skills 段比对（缺失 / 多余 /
      origin 不符、目录缺失），缓存仓 HEAD 与 lock 的 repos commit 比对（不符打印 DRIFT）；
      有任何差异 exit 1，全一致打印 OK 并 exit 0。
  --pinned
      复现模式：若 scripts/skills.lock 存在，按 lock 记录的 commit 检出缓存仓
      （git -C <cache> checkout -q <commit>，不 fetch）再同步，用于复现 lock 对应版本；
      默认不用 pinned（保持持续更新语义）。
  -h | --help
      打印本帮助。

行为:
  - include 为逗号分隔 glob，同时尝试匹配技能目录相对路径与目录名
    （* 不跨 /，** 跨 /）。
  - 目录名或相对路径含 triton（不区分大小写）→ SKIPPED，不同步。
  - 同步成功写来源标记 .agents/skills/.origins/<目录名>（不入库）。
  - 已存在判定：被 git 跟踪 → CONFLICT；标记同源 → 刷新 REFRESHED；
    标记异源/无标记：同名技能近似相同（体积差≤10% 且改动行≤5%）→ CONFLICT
    保留权威源（先到先得的那一份）；实质不同 → 改名为 <origin>--<name> 并存（RENAMED，
    frontmatter name: 同步改写）；--force 仅对此类强制覆盖原目录（不改名）。
  - 拷贝后若 frontmatter name: 与目录名不一致，改写为目录名。
  - 单源失败计入 FAIL 不中断；末尾汇总 ADDED / REFRESHED / RENAMED / SKIPPED / CONFLICT /
    REMOVED / FAIL，并按类型打印变更报告（名称清单，每类最多列 50 个，超出显示「… 其余 N 个」）。

日常更新流程:
  bash scripts/sync_ascend_skills.sh --dry-run          # 预演（含 prune 候选）
  bash scripts/sync_ascend_skills.sh                    # 更新（新装/刷新/改名）
  bash scripts/sync_ascend_skills.sh --prune            # 清掉已失效的旧技能
  bash scripts/sync_ascend_skills.sh --update-lock      # 记录本次上游 commit
  bash scripts/sync_ascend_skills.sh --verify           # 自检（CI 可用）

无参数时打印本帮助。
EOF
}

# URL -> 缓存目录 slug：去掉 https://，/ 与非字母数字替换为 __
url_slug() {
  local url="$1"
  url="${url#https://}"
  url="${url#http://}"
  printf '%s' "$url" | sed -E 's/[^[:alnum:]]/__/g'
}

# glob -> ERE：* 不跨 /，** 跨 /，? 不跨 /，其余元字符按字面转义
glob_to_regex() {
  local glob="$1" out="" ch i=0 n
  n="${#glob}"
  while [ "$i" -lt "$n" ]; do
    ch="${glob:$i:1}"
    if [ "$ch" = "*" ]; then
      if [ "$((i + 1))" -lt "$n" ] && [ "${glob:$((i + 1)):1}" = "*" ]; then
        out="${out}.*"
        i=$((i + 2))
        continue
      fi
      out="${out}[^/]*"
    elif [ "$ch" = "?" ]; then
      out="${out}[^/]"
    else
      case "$ch" in
        '.'|'+'|'('|')'|'['|']'|'{'|'}'|'^'|'$'|'|'|'\\') out="${out}\\${ch}" ;;
        *) out="${out}${ch}" ;;
      esac
    fi
    i=$((i + 1))
  done
  printf '^%s$' "$out"
}

# include 的每个 glob 同时尝试匹配相对路径与目录名，任一命中即算匹配
match_include() {
  local include="$1" rel="$2"
  local name glob rest re
  name="$(basename "$rel")"
  rest="$include"
  while [ -n "$rest" ]; do
    glob="${rest%%,*}"
    if [ "$glob" = "$rest" ]; then
      rest=""
    else
      rest="${rest#*,}"
    fi
    re="$(glob_to_regex "$glob")"
    if [[ "$rel" =~ $re ]] || [[ "$name" =~ $re ]]; then
      return 0
    fi
  done
  return 1
}

# Triton 兜底排除：目录名或相对路径含 triton（不区分大小写）
is_triton() {
  local rel="$1" lc
  lc="$(printf '%s' "$rel" | tr 'A-Z' 'a-z')"
  case "$lc" in *triton*) return 0 ;; *) return 1 ;; esac
}

# 从 URL 取仓名（用于仓根即技能时的平铺命名）
repo_basename() {
  local url="$1"
  url="${url%.git}"
  printf '%s' "${url##*/}"
}

# 拷贝技能目录内容到平铺落点，排除 .git（不碰用户数据）
copy_skill() {
  local src="$1" dest="$2"
  mkdir -p "$dest" || return 1
  # -h：解引用符号链接。上游技能常用 `references/x.md -> ../../<repo>/...` 这类相对链接，
  #     技能目录被“平铺”到 .agents/skills/<name>/ 后该相对路径失效（断链）；
  #     解引用后拷贝真实内容。若上游本身就是悬空链接，tar 会告警，此处以 SKILL.md 是否落地为准。
  if tar -C "$src" -h --exclude='.git' --exclude='*/.git' -cf - . 2>/dev/null | tar -C "$dest" -xf - 2>/dev/null; then
    [ -f "$dest/SKILL.md" ] && return 0
  fi
  [ -f "$dest/SKILL.md" ] && return 0
  return 1
}

# 安全删除目标技能目录：仅允许 .agents/skills/<单层名>/（非空、非 .、非 ..、非隐藏）
safe_rm_dest() {
  local dest="$1" name
  case "$dest" in
    "$DEST_ROOT"/*) ;;
    *)
      echo "  错误：目标不在 .agents/skills/ 下，拒绝删除（${dest}）" >&2
      return 1
      ;;
  esac
  name="${dest#"$DEST_ROOT"/}"
  case "$name" in
    ""|.|..|.*|*/*)
      echo "  错误：非法技能目录名 '${name}'，拒绝删除" >&2
      return 1
      ;;
  esac
  if [ -d "$dest" ]; then
    rm -rf -- "$dest" || return 1
  fi
  return 0
}

# 写来源标记（内容 = origin，目录被 .gitignore 的 /.agents/skills/* 覆盖，不入库）
write_origin() {
  local dir_name="$1" origin="$2"
  mkdir -p "$ORIGINS_DIR" || return 1
  printf '%s' "$origin" > "$ORIGINS_DIR/$dir_name"
}

# 变更报告收集：REPORT_ROWS 每行 type<TAB>name<TAB>origin（bash 3.2，无关联数组）
report_add() {
  local type="$1" name="$2" origin="$3"
  local nl=$'\n' tab=$'\t'
  REPORT_ROWS="${REPORT_ROWS}${REPORT_ROWS:+$nl}${type}${tab}${name}${tab}${origin}"
}

# 本次已安装/刷新/改名的目录名集合（--prune 判定「本次未命中」用）
touched_add() {
  local name="$1"
  local nl=$'\n'
  TOUCHED="${TOUCHED}${TOUCHED:+$nl}${name}"
}

touched() {
  local name="$1"
  case $'\n'"${TOUCHED}"$'\n' in
    *$'\n'"${name}"$'\n'*) return 0 ;;
  esac
  return 1
}

# origin 是否属于本次过滤后的集合（--prune 护栏 1）
origin_in_set() {
  local o="$1"
  case " ${CURRENT_ORIGINS} " in *" ${o} "*) return 0 ;; esac
  return 1
}

# 目标技能是否被 git 跟踪（入库技能，任何情况不覆盖）
git_tracked() {
  local dir_name="$1"
  git -C "$ROOT" ls-files --error-unmatch ".agents/skills/${dir_name}/SKILL.md" >/dev/null 2>&1
}

# 归一化 frontmatter name：仅当 name:（去引号后）≠ 目录名时改写该行；不改被 git 跟踪的技能
normalize_name() {
  local dest="$1" dir_name="$2" cur
  [ -f "$dest/SKILL.md" ] || return 0
  git_tracked "$dir_name" && return 0
  cur="$(awk 'BEGIN{f=0} /^---[[:space:]]*$/{f++; next} f==1 && /^name:[[:space:]]*/{sub(/^name:[[:space:]]*/,""); gsub(/^"|"$/,""); sub(/[[:space:]]+$/,""); print; exit}' "$dest/SKILL.md")"
  [ "$cur" = "$dir_name" ] && return 0
  awk -v dir="$dir_name" 'BEGIN{f=0} /^---[[:space:]]*$/{f++; print; next} f==1 && /^name:[[:space:]]*/{print "name: " dir; next} {print}' \
    "$dest/SKILL.md" > "$dest/SKILL.md.tmp" && mv "$dest/SKILL.md.tmp" "$dest/SKILL.md"
}

# 判定两个 SKILL.md 是否「近似相同」（任一条件不满足即视为实质不同）：
#   1) 两者都存在且非空；
#   2) 体积差 ≤ 10%：|sa-sb| / max(sa,sb) ≤ 0.10；
#   3) 改动行占比 ≤ 5%：diff -u 中 +/- 开头的行（去掉 ---/+++ 文件头两行）计 changed，
#      基准 total = wc -l < incoming，要求 changed / (2*total) ≤ 0.05（即 changed*100 ≤ total*10）。
# bash 3.2 兼容（无关联数组/mapfile）；set -e 下 grep -c 无匹配返回 1，需 || true。
near_identical() {
  local existing="$1" incoming="$2"
  local sa sb total changed
  [ -s "$existing" ] || return 1
  [ -s "$incoming" ] || return 1
  sa="$(wc -c < "$existing")"
  sb="$(wc -c < "$incoming")"
  if [ "$sa" -gt "$sb" ]; then
    [ $(((sa - sb) * 100)) -le $((sa * 10)) ] || return 1
  else
    [ $(((sb - sa) * 100)) -le $((sb * 10)) ] || return 1
  fi
  total="$(wc -l < "$incoming")"
  [ "$total" -gt 0 ] || return 1
  changed="$(diff -u "$existing" "$incoming" | grep -cE '^[+-]' || true)"
  changed=$((changed - 2))
  [ "$changed" -lt 0 ] && changed=0
  [ $((changed * 100)) -le $((total * 10)) ] || return 1
  return 0
}

# 克隆/复用缓存（按唯一 URL 调用一次）；pinned=1 时按 lock 的 commit 检出（不联网）
prepare_cache() {
  local url="$1" branch="$2" origin="$3" pinned="$4"
  local cache_dir commit
  cache_dir="$CACHE_DIR/$(url_slug "$url")"
  if [ -e "$cache_dir" ] && [ ! -d "$cache_dir/.git" ]; then
    echo "  错误：${cache_dir} 已存在但不是独立 Git 仓（脚本不会自动删除）。" >&2
    return 1
  fi
  if [ "$pinned" -eq 1 ]; then
    commit="$(awk -F'\t' -v u="$url" '$1=="repo" && $2==u {print $4; exit}' "$SCRIPT_DIR/skills.lock")"
    if [ -z "$commit" ] || [ "$commit" = "MISSING" ]; then
      echo "  FAIL：${origin} --pinned 但 lock 无 ${url} 的 commit 记录" >&2
      return 1
    fi
    if [ ! -d "$cache_dir/.git" ]; then
      echo "  FAIL：${origin} --pinned 但缓存 ${cache_dir} 不存在（需先以非 pinned 模式同步一次）" >&2
      return 1
    fi
    if git -C "$cache_dir" checkout -q "$commit"; then
      echo "  [cache] ${cache_dir} 检出 lock commit ${commit:0:12}（pinned）"
    else
      echo "  FAIL：${origin} --pinned 检出 ${commit} 失败（浅克隆可能不含该 commit）" >&2
      return 1
    fi
    return 0
  fi
  if [ -d "$cache_dir/.git" ]; then
    if git -C "$cache_dir" fetch --depth 1 origin "$branch" && git -C "$cache_dir" checkout -q FETCH_HEAD; then
      echo "  [cache] ${cache_dir} 已存在，已更新到 ${branch} 最新提交"
    else
      echo "  FAIL：${origin} 更新缓存失败（${url}）" >&2
      return 1
    fi
  else
    mkdir -p "$CACHE_DIR" || return 1
    if git clone --depth 1 -b "$branch" "$url" "$cache_dir"; then
      echo "  [cache] 浅克隆 ${url} -> ${cache_dir}"
    else
      echo "  FAIL：${origin} 克隆失败（${url}）" >&2
      return 1
    fi
  fi
  return 0
}

# 输出选中行（按分组/only 过滤），格式 group|origin|url|branch|include|note
filtered_rows() {
  local want="$1" only="${2:-}"
  local group="" label="" origin url branch include note
  while IFS='|' read -r origin url branch include note; do
    case "$origin" in
      \#*)
        label="${origin#\# ===== }"
        label="${label%=====}"
        label="${label% }"
        case "$label" in
          开发*) group="dev" ;;
          运维*) group="ops" ;;
          门禁*) group="gate" ;;
          *) group="" ;;
        esac
        continue
        ;;
      ""|origin) continue ;;
    esac
    [ -n "$group" ] || continue
    if [ "$want" != "all" ] && [ "$group" != "$want" ]; then
      continue
    fi
    if [ -n "$only" ] && [ "$origin" != "$only" ]; then
      continue
    fi
    printf '%s|%s|%s|%s|%s|%s\n' "$group" "$origin" "$url" "$branch" "$include" "$note"
  done < <(skill_sources)
}

# --list：完全离线，3 分组 + 21 行 + 合计
cmd_list() {
  local group="" label="" origin url branch include note
  local n_dev=0 n_ops=0 n_gate=0 total=0
  while IFS='|' read -r origin url branch include note; do
    case "$origin" in
      \#*)
        label="${origin#\# ===== }"
        label="${label%=====}"
        label="${label% }"
        echo ""
        echo "== ${label} =="
        case "$label" in
          开发*) group="dev" ;;
          运维*) group="ops" ;;
          门禁*) group="gate" ;;
          *) group="" ;;
        esac
        continue
        ;;
      ""|origin) continue ;;
    esac
    [ -n "$group" ] || continue
    total=$((total + 1))
    case "$group" in
      dev) n_dev=$((n_dev + 1)) ;;
      ops) n_ops=$((n_ops + 1)) ;;
      gate) n_gate=$((n_gate + 1)) ;;
    esac
    echo "  ${origin} / ${url} / ${branch} / ${include} / ${note}"
  done < <(skill_sources)
  echo ""
  echo "合计 ${total} 条（开发=${n_dev} 运维=${n_ops} 门禁=${n_gate}）"
}

# 处理单行规则：发现 -> 父目录覆盖去重 -> include 匹配 -> triton 排除 -> 冲突/刷新判定 -> 拷贝/列出
process_row() {
  local g="$1" origin="$2" url="$3" branch="$4" include="$5" dry_run="$6" force="$7"
  local cache_dir rel dir_name dest src name marker
  local hits=0 added=0 refreshed=0 renamed=0 skipped=0 conflict=0 accepted_rel=""
  local rest glob re c i refresh=0 new_dir new_dest new_marker
  echo ""
  echo "---- [${g}] ${origin} (branch=${branch}) ----"
  cache_dir="$CACHE_DIR/$(url_slug "$url")"
  if [ ! -d "$cache_dir" ]; then
    echo "  FAIL：${origin} 缓存目录缺失（${cache_dir}）" >&2
    FAIL=$((FAIL + 1))
    echo "  [${origin}] hits=0 added=0 refreshed=0 renamed=0 skipped=0 conflict=0"
    return 0
  fi
  # 收集本次发现的所有技能相对路径（父目录去重后的全集）
  local rels=()
  while IFS= read -r rel; do
    [ -z "$rel" ] && continue
    rels+=("$rel")
  done < <(find "$cache_dir" -type f -iname SKILL.md \
           | while IFS= read -r skill_md; do
               [ -z "$skill_md" ] && continue
               dirname "${skill_md#"$cache_dir"/}"
             done | sort -u)
  # A2：dry-run 时逐 include glob 自检命中数（0 命中 → WARN + DEAD_GLOBS）
  if [ "$dry_run" -eq 1 ]; then
    rest="$include"
    while [ -n "$rest" ]; do
      glob="${rest%%,*}"
      if [ "$glob" = "$rest" ]; then rest="" ; else rest="${rest#*,}"; fi
      re="$(glob_to_regex "$glob")"
      c=0
      for rel in "${rels[@]:-}"; do
        name="$(basename "$rel")"
        if [[ "$rel" =~ $re ]] || [[ "$name" =~ $re ]]; then c=$((c + 1)); fi
      done
      echo "  glob ${glob} 命中 ${c}"
      if [ "$c" -eq 0 ]; then
        echo "  WARN glob 0 命中: ${glob}"
        DEAD_GLOBS=$((DEAD_GLOBS + 1))
      fi
    done
  fi
  for rel in "${rels[@]:-}"; do
    [ -z "$rel" ] && continue
    # 父目录整体已拷贝 -> 子目录视为已覆盖（沿用现版前缀去重逻辑）
    if [ -n "$accepted_rel" ] && [ "${rel#"$accepted_rel"/}" != "$rel" ]; then
      continue
    fi
    if ! match_include "$include" "$rel"; then
      continue
    fi
    hits=$((hits + 1))
    if is_triton "$rel"; then
      skipped=$((skipped + 1))
      SKIPPED=$((SKIPPED + 1))
      report_add SKIPPED "$rel" "$origin"
      echo "  SKIPPED: ${rel}（含 triton，兜底排除）"
      continue
    fi
    if [ "$rel" = "." ]; then
      dir_name="$(repo_basename "$url")"
    else
      dir_name="$(basename "$rel")"
    fi
    dest="$DEST_ROOT/$dir_name"
    src="$cache_dir/$rel"
    [ "$rel" = "." ] && src="$cache_dir"
    refresh=0
    if [ -e "$dest" ]; then
      # 已存在：被 git 跟踪 → CONFLICT（绝不覆盖）
      if git_tracked "$dir_name"; then
        conflict=$((conflict + 1))
        CONFLICT=$((CONFLICT + 1))
        report_add CONFLICT "$dir_name" "$origin"
        echo "  CONFLICT: ${dest} 被 git 跟踪（入库技能），绝不覆盖"
        continue
      fi
      marker=""
      [ -f "$ORIGINS_DIR/$dir_name" ] && marker="$(cat "$ORIGINS_DIR/$dir_name" 2>/dev/null || true)"
      if [ "$marker" = "$origin" ]; then
        refresh=1
      elif [ "$force" -eq 1 ]; then
        # --force：仅对已存在且异源/无标记强制覆盖，仍覆盖原目录名（不改名）
        refresh=1
        echo "  --force 覆盖: ${dest}（来源 ${marker:-无标记} → ${origin}）"
      elif near_identical "$dest/SKILL.md" "$src/SKILL.md"; then
        # 近似相同 → 保留权威源（先到先得的那一份），跳过不覆盖
        conflict=$((conflict + 1))
        CONFLICT=$((CONFLICT + 1))
        report_add CONFLICT "$dir_name" "$origin"
        echo "  CONFLICT: ${dest} 与 ${origin} 同名技能近似相同（来源 ${marker:-无标记}），保留权威源，跳过不覆盖"
        continue
      else
        # 实质不同 → 改名 ${origin}--${dir_name} 并存（frontmatter name: 由 normalize_name 同步改写）
        new_dir="${origin}--${dir_name}"
        new_dest="$DEST_ROOT/$new_dir"
        if [ -e "$new_dest" ]; then
          # 改名目标已存在：同源 → 刷新；异源/无标记 → CONFLICT
          if git_tracked "$new_dir"; then
            conflict=$((conflict + 1))
            CONFLICT=$((CONFLICT + 1))
            report_add CONFLICT "$new_dir" "$origin"
            echo "  CONFLICT: ${new_dest} 被 git 跟踪（入库技能），绝不覆盖"
            continue
          fi
          new_marker=""
          [ -f "$ORIGINS_DIR/$new_dir" ] && new_marker="$(cat "$ORIGINS_DIR/$new_dir" 2>/dev/null || true)"
          if [ "$new_marker" = "$origin" ]; then
            refresh=1
            dest="$new_dest"
            dir_name="$new_dir"
          else
            conflict=$((conflict + 1))
            CONFLICT=$((CONFLICT + 1))
            report_add CONFLICT "$new_dir" "$origin"
            echo "  CONFLICT: ${new_dest} 已存在（来源 ${new_marker:-未知}），跳过不覆盖"
            continue
          fi
        else
          # 目标不存在 → 改名新增
          if [ "$dry_run" -eq 1 ]; then
            renamed=$((renamed + 1))
            RENAMED=$((RENAMED + 1))
            report_add RENAMED "$new_dir" "$origin"
            touched_add "$new_dir"
            echo "  RENAME: ${dir_name}（来源 ${marker:-无标记}）≠ ${origin} 实质不同 → 并存为 ${new_dir}"
            accepted_rel="$rel"
            continue
          fi
          if copy_skill "$src" "$new_dest" && write_origin "$new_dir" "$origin" && normalize_name "$new_dest" "$new_dir"; then
            renamed=$((renamed + 1))
            RENAMED=$((RENAMED + 1))
            report_add RENAMED "$new_dir" "$origin"
            touched_add "$new_dir"
            echo "  RENAME: ${dir_name}（来源 ${marker:-无标记}）≠ ${origin} 实质不同 → 并存为 ${new_dir}"
            accepted_rel="$rel"
          else
            echo "  FAIL：${origin} 改名并存技能 ${rel} → ${new_dir} 失败" >&2
            FAIL=$((FAIL + 1))
          fi
          continue
        fi
      fi
    fi
    if [ "$refresh" -eq 1 ]; then
      # 刷新：先安全删除目标再拷贝（唯一允许的删除路径）
      if [ "$dry_run" -eq 1 ]; then
        REFRESHED=$((REFRESHED + 1))
        refreshed=$((refreshed + 1))
        report_add REFRESHED "$dir_name" "$origin"
        touched_add "$dir_name"
        echo "  ~ ${dest}/（刷新）"
        accepted_rel="$rel"
        continue
      fi
      if ! safe_rm_dest "$dest"; then
        echo "  FAIL：${origin} 安全删除 ${dest} 失败" >&2
        FAIL=$((FAIL + 1))
        continue
      fi
      if copy_skill "$src" "$dest" && write_origin "$dir_name" "$origin" && normalize_name "$dest" "$dir_name"; then
        REFRESHED=$((REFRESHED + 1))
        refreshed=$((refreshed + 1))
        report_add REFRESHED "$dir_name" "$origin"
        touched_add "$dir_name"
        accepted_rel="$rel"
      else
        echo "  FAIL：${origin} 刷新技能目录 ${rel} 失败" >&2
        FAIL=$((FAIL + 1))
      fi
      continue
    fi
    # 目标不存在 → ADDED（拷贝 + 写来源标记）
    if [ "$dry_run" -eq 1 ]; then
      ADDED=$((ADDED + 1))
      added=$((added + 1))
      report_add ADDED "$dir_name" "$origin"
      touched_add "$dir_name"
      if [ "$rel" = "." ]; then
        echo "  + ${dest}/（仓根 SKILL.md）"
        echo "  ${origin}：仓根含 SKILL.md，将整体拷贝，其余发现视为已覆盖"
      else
        echo "  + ${dest}/"
      fi
      accepted_rel="$rel"
      if [ "$rel" = "." ]; then break; fi
      continue
    fi
    if copy_skill "$src" "$dest" && write_origin "$dir_name" "$origin" && normalize_name "$dest" "$dir_name"; then
      ADDED=$((ADDED + 1))
      added=$((added + 1))
      report_add ADDED "$dir_name" "$origin"
      touched_add "$dir_name"
      if [ "$rel" = "." ]; then
        echo "  ${origin}：仓根含 SKILL.md，已整体拷贝，其余发现视为已覆盖"
      fi
      accepted_rel="$rel"
      if [ "$rel" = "." ]; then break; fi
    else
      echo "  FAIL：${origin} 拷贝技能目录 ${rel} 失败" >&2
      FAIL=$((FAIL + 1))
    fi
  done
  echo "  [${origin}] hits=${hits} added=${added} refreshed=${refreshed} renamed=${renamed} skipped=${skipped} conflict=${conflict}"
}

# --prune：删除「由本脚本安装（有 .origins 标记）但本次未命中任何 include」的目录
run_prune() {
  local dry_run="$1"
  local candidates=0 name origin f
  if [ ! -d "$ORIGINS_DIR" ]; then
    if [ "$dry_run" -eq 1 ]; then
      echo "WOULD REMOVE: 0（.origins 不存在）"
    fi
    return 0
  fi
  for f in "$ORIGINS_DIR"/*; do
    [ -f "$f" ] || continue
    name="${f##*/}"
    # 护栏 3/4：单层目录名（非空、非 ./..、不含 /）；README.md 永不删
    case "$name" in
      ""|.|..|*/*|README.md) continue ;;
    esac
    origin="$(cat "$f" 2>/dev/null || true)"
    [ -n "$origin" ] || continue
    # 护栏 1：只对本次过滤后的 origin 集合生效
    origin_in_set "$origin" || continue
    # 护栏：本次 prepare 失败的源不清理（避免误删）
    case " $FAILED_ORIGINS " in *" $origin "*) continue ;; esac
    # 本次已安装/刷新/改名 → 不算陈旧
    touched "$name" && continue
    # 护栏 2：被 git 跟踪的入库技能绝不删
    git_tracked "$name" && continue
    # 护栏 3：复核目标目录存在
    [ -d "$DEST_ROOT/$name" ] || continue
    candidates=$((candidates + 1))
    if [ "$dry_run" -eq 1 ]; then
      echo "WOULD REMOVE: ${name}"
    else
      if safe_rm_dest "$DEST_ROOT/$name"; then
        rm -f -- "$f"
        REMOVED=$((REMOVED + 1))
        report_add REMOVED "$name" "$origin"
        echo "REMOVED: ${name}"
      else
        echo "  FAIL：--prune 安全删除 ${name} 失败" >&2
        FAIL=$((FAIL + 1))
      fi
    fi
  done
  if [ "$dry_run" -eq 1 ]; then
    echo "WOULD REMOVE: ${candidates}"
  fi
  return 0
}

# 末尾按类型分组打印变更报告（每类最多列 50 个，超出显示「… 其余 N 个」）
print_report() {
  local type n i t name origin
  if [ -z "$REPORT_ROWS" ]; then
    echo ""
    echo "变更报告：本次无任何变更"
    return 0
  fi
  echo ""
  echo "变更报告："
  for type in ADDED REFRESHED RENAMED CONFLICT SKIPPED REMOVED; do
    n="$(printf '%s\n' "$REPORT_ROWS" | awk -F'\t' -v t="$type" '$1==t{c++} END{print c+0}')"
    if [ "$n" -eq 0 ]; then
      continue
    fi
    echo "  ${type}（${n}）:"
    i=0
    while IFS=$'\t' read -r t name origin; do
      [ "$t" = "$type" ] || continue
      i=$((i + 1))
      if [ "$i" -le 50 ]; then
        echo "    ${name}"
      fi
    done < <(printf '%s\n' "$REPORT_ROWS")
    if [ "$n" -gt 50 ]; then
      echo "    … 其余 $((n - 50)) 个"
    fi
  done
}

# 生成 scripts/skills.lock（入库、随仓库跟踪）：13 个上游仓 (url,branch,commit) + 磁盘技能清单
cmd_update_lock() {
  local lock="$SCRIPT_DIR/skills.lock"
  local tmp="$lock.tmp"
  local seen="" url branch commit cache origin include note name f
  if ! {
    echo '# scripts/skills.lock —— 由 `bash scripts/sync_ascend_skills.sh --update-lock` 生成，勿手改'
    echo '# ===== repos ====='
    while IFS='|' read -r origin url branch include note; do
      case "$origin" in
        \#*|""|origin) continue ;;
      esac
      case " $seen " in *" $url "*) continue ;; esac
      seen="$seen $url"
      cache="$CACHE_DIR/$(url_slug "$url")"
      if [ -d "$cache/.git" ]; then
        commit="$(git -C "$cache" rev-parse HEAD)"
      else
        commit="MISSING"
      fi
      printf 'repo\t%s\t%s\t%s\n' "$url" "$branch" "$commit"
    done < <(skill_sources)
    echo '# ===== skills ====='
    for f in "$ORIGINS_DIR"/*; do
      [ -f "$f" ] || continue
      name="${f##*/}"
      origin="$(cat "$f" 2>/dev/null || true)"
      printf 'skill\t%s\t%s\n' "$name" "$origin"
    done | LC_ALL=C sort
  } > "$tmp"; then
    rm -f -- "$tmp"
    echo "错误：写 lock 失败（${tmp}）" >&2
    return 1
  fi
  mv "$tmp" "$lock"
  echo "已写入 ${lock}（repos $(awk -F'\t' '$1=="repo"{n++} END{print n+0}' "$lock") / skills $(awk -F'\t' '$1=="skill"{n++} END{print n+0}' "$lock")）"
}

# --verify：只读自检（不联网、不改文件），有任何差异 exit 1；全一致打印 OK exit 0
cmd_verify() {
  local lock="$SCRIPT_DIR/skills.lock"
  if [ ! -f "$lock" ]; then
    echo "错误：${lock} 不存在，请先运行 --update-lock 生成。" >&2
    return 1
  fi
  local n_repos=0 n_skills=0 drift=0 issues=0
  local tag url branch commit cache head name origin lk dk
  # --- repos 段：缓存仓 HEAD vs lock commit ---
  while IFS=$'\t' read -r tag url branch commit; do
    [ "$tag" = "repo" ] || continue
    n_repos=$((n_repos + 1))
    cache="$CACHE_DIR/$(url_slug "$url")"
    if [ ! -d "$cache/.git" ]; then
      echo "DRIFT: ${url} 缓存缺失（${cache}）"
      drift=$((drift + 1))
      continue
    fi
    head="$(git -C "$cache" rev-parse HEAD 2>/dev/null || true)"
    if [ "$head" != "$commit" ]; then
      echo "DRIFT: ${url}（lock=${commit}，磁盘=${head}）"
      drift=$((drift + 1))
    fi
  done < <(awk -F'\t' '$1=="repo"' "$lock")
  # --- skills 段：lock vs 磁盘 .origins ---
  # 缺失（lock 有、磁盘无标记）
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    echo "缺失: ${name}"
    issues=$((issues + 1))
  done < <(comm -23 \
      <(awk -F'\t' '$1=="skill"{print $2}' "$lock" | LC_ALL=C sort) \
      <(for f in "$ORIGINS_DIR"/*; do [ -f "$f" ] || continue; printf '%s\n' "${f##*/}"; done | LC_ALL=C sort))
  # 多余（磁盘有标记、lock 无）
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    echo "多余: ${name}"
    issues=$((issues + 1))
  done < <(comm -13 \
      <(awk -F'\t' '$1=="skill"{print $2}' "$lock" | LC_ALL=C sort) \
      <(for f in "$ORIGINS_DIR"/*; do [ -f "$f" ] || continue; printf '%s\n' "${f##*/}"; done | LC_ALL=C sort))
  # 共同项：origin 相符 + 目录存在
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    lk="$(awk -F'\t' -v n="$name" '$1=="skill" && $2==n {print $3; exit}' "$lock")"
    dk="$(cat "$ORIGINS_DIR/$name" 2>/dev/null || true)"
    if [ "$lk" != "$dk" ]; then
      echo "origin 不符: ${name}（lock=${lk}，磁盘=${dk:-无标记}）"
      issues=$((issues + 1))
    fi
    if [ ! -d "$DEST_ROOT/$name" ]; then
      echo "缺失: ${name}（目录不存在）"
      issues=$((issues + 1))
    fi
  done < <(comm -12 \
      <(awk -F'\t' '$1=="skill"{print $2}' "$lock" | LC_ALL=C sort) \
      <(for f in "$ORIGINS_DIR"/*; do [ -f "$f" ] || continue; printf '%s\n' "${f##*/}"; done | LC_ALL=C sort))
  n_skills="$(awk -F'\t' '$1=="skill"{n++} END{print n+0}' "$lock")"
  if [ "$drift" -gt 0 ] || [ "$issues" -gt 0 ]; then
    echo "校验失败：DRIFT ${drift} 处 / 技能差异 ${issues} 处"
    return 1
  fi
  echo "OK: 磁盘与 lock 一致（${n_skills} 技能 / ${n_repos} 源）"
  return 0
}

cmd_sync() {
  local want="$1" only="${2:-}" dry_run="$3" force="$4" prune="$5" report="${6:-}" pinned="$7"
  local g origin url branch include note
  local n_rows=0 prepared="" failed=""
  if ! command -v git >/dev/null 2>&1; then
    echo "错误：未找到 git。同步技能需要 git（浅克隆与 fetch），请先安装 git。" >&2
    exit 1
  fi
  # 统计选中行数：用于 --only 无匹配的报错
  while IFS='|' read -r g origin url branch include note; do
    n_rows=$((n_rows + 1))
  done < <(filtered_rows "$want" "$only")
  if [ -n "$only" ] && [ "$n_rows" -eq 0 ]; then
    echo "错误：--only ${only} 未匹配任何源行（结合 --category 过滤后亦无匹配）。" >&2
    exit 1
  fi
  CURRENT_ORIGINS=""
  FAILED_ORIGINS=""
  # pass 1：按唯一 URL 准备缓存（同一 URL 多行规则共享，只 clone/fetch 一次）
  while IFS='|' read -r g origin url branch include note; do
    CURRENT_ORIGINS="$CURRENT_ORIGINS $origin"
    case " $prepared $failed " in *" $url "*) continue ;; esac
    if prepare_cache "$url" "$branch" "$origin" "$pinned"; then
      prepared="$prepared $url"
    else
      failed="$failed $url"
      FAIL=$((FAIL + 1))
    fi
  done < <(filtered_rows "$want" "$only")
  # 记录本次 prepare 失败的 origin（--prune 护栏：失败源不参与清理判定）
  while IFS='|' read -r g origin url branch include note; do
    case " $failed " in *" $url "*) FAILED_ORIGINS="$FAILED_ORIGINS $origin" ;; esac
  done < <(filtered_rows "$want" "$only")
  # pass 2：逐行匹配与同步
  while IFS='|' read -r g origin url branch include note; do
    case " $failed " in *" $url "*) continue ;; esac
    process_row "$g" "$origin" "$url" "$branch" "$include" "$dry_run" "$force"
  done < <(filtered_rows "$want" "$only")
  # pass 3：--prune 清陈旧（仅全量 + 无 --only 时允许，main 已校验）
  if [ "$prune" -eq 1 ]; then
    run_prune "$dry_run"
  fi
  echo ""
  echo "汇总：ADDED ${ADDED} / REFRESHED ${REFRESHED} / RENAMED ${RENAMED} / SKIPPED ${SKIPPED} / CONFLICT ${CONFLICT} / REMOVED ${REMOVED} / FAIL ${FAIL}"
  if [ "$dry_run" -eq 1 ]; then
    echo "DEAD_GLOBS ${DEAD_GLOBS}"
  fi
  print_report
  if [ -n "$report" ]; then
    if [ -n "$REPORT_ROWS" ]; then
      printf '%s\n' "$REPORT_ROWS" > "$report"
    else
      : > "$report"
    fi
    echo "报告已写入: ${report}"
  fi
  [ "$FAIL" -eq 0 ]
}

main() {
  local category="all" only="" dry_run=0 list_only=0 force=0 prune=0 report="" update_lock=0 verify=0 pinned=0
  if [ "$#" -eq 0 ]; then
    usage
    exit 0
  fi
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --list) list_only=1 ;;
      -h|--help|help) usage; exit 0 ;;
      --dry-run) dry_run=1 ;;
      --force) force=1 ;;
      --prune) prune=1 ;;
      --update-lock) update_lock=1 ;;
      --verify) verify=1 ;;
      --pinned) pinned=1 ;;
      --report)
        if [ "$#" -lt 2 ]; then
          echo "错误：--report 需要一个参数（TSV 输出路径）。" >&2
          usage
          exit 1
        fi
        report="$2"
        shift
        ;;
      --category)
        if [ "$#" -lt 2 ]; then
          echo "错误：--category 需要一个参数（dev|ops|gate|all）。" >&2
          usage
          exit 1
        fi
        category="$2"
        shift
        ;;
      --only)
        if [ "$#" -lt 2 ]; then
          echo "错误：--only 需要一个参数（源表 origin）。" >&2
          usage
          exit 1
        fi
        only="$2"
        shift
        ;;
      *)
        echo "错误：未知参数 '$1'。" >&2
        usage
        exit 1
        ;;
    esac
    shift
  done
  case "$category" in
    dev|ops|gate|all) ;;
    *)
      echo "错误：--category 必须是 dev | ops | gate | all（收到 '$category'）。" >&2
      exit 1
      ;;
  esac
  # --prune 安全约束：仅全量（默认 all）且不与 --only 同用
  if [ "$prune" -eq 1 ] && [ "$category" != "all" ]; then
    echo "错误：--prune 只允许与 --category all（或不指定，默认 all）一起使用，避免部分类别运行时误删。" >&2
    exit 1
  fi
  if [ "$prune" -eq 1 ] && [ -n "$only" ]; then
    echo "错误：--prune 与 --only 互斥（--only 只处理单个 origin，无法安全判定全局陈旧项）。" >&2
    exit 1
  fi
  # --verify 为独立只读自检，优先执行并退出（不联网、不改文件）
  if [ "$verify" -eq 1 ]; then
    cmd_verify
    exit 0
  fi
  if [ "$pinned" -eq 1 ] && [ ! -f "$SCRIPT_DIR/skills.lock" ]; then
    echo "错误：--pinned 需要 scripts/skills.lock 存在（请先运行 --update-lock 生成）。" >&2
    exit 1
  fi
  if [ "$list_only" -eq 1 ]; then
    cmd_list
    exit 0
  fi
  cmd_sync "$category" "$only" "$dry_run" "$force" "$prune" "$report" "$pinned"
  # 同步成功（FAIL=0，set -e 保证失败不会走到这里）才写 lock
  if [ "$update_lock" -eq 1 ]; then
    cmd_update_lock
  fi
}

main "$@"
