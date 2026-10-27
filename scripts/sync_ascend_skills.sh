#!/usr/bin/env bash
# sync_ascend_skills.sh — allowlist 驱动：从 14 个昇腾生态源仓（22 条规则）发现并同步 SKILL.md 技能目录
# 落点（平铺）：.agents/skills/<技能目录名>/（不再有 external/<category>/<name>/ 层级）
# 缓存：.cache/skills/<url-slug>/（同一 URL 多行规则共享，只 clone/fetch 一次）
# 规则：include 为逗号分隔 glob，同时尝试匹配技能目录相对路径与目录名
#      （* 不跨 /，** 跨 /）；目录名/相对路径含 triton（不区分大小写）→ SKIPPED；
#      目标 .agents/skills/<目录名>/ 已存在 → CONFLICT，不覆盖。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
CACHE_DIR="$ROOT/.cache/skills"
DEST_ROOT="$ROOT/.agents/skills"

ADDED=0
SKIPPED=0
CONFLICT=0
FAIL=0

# 源表：origin|url|branch|include|note（# ===== 注释行为分组标记：开发/运维/门禁，勿当数据行）
skill_sources() {
  cat <<'EOF'
origin|url|branch|include|note
# ===== 开发（算子 / 模型接入 / 图模式 / 线性注意力）=====
agent-skills-dev|https://gitcode.com/Ascend/agent-skills.git|master|ascendc-operator-*|AscendC 算子开发 13 件套
agent-skills-atb|https://gitcode.com/Ascend/agent-skills.git|master|atb-*|ATB/ACLNN 迁移与调试
agent-skills-catlass|https://gitcode.com/Ascend/agent-skills.git|master|catlass-operator-*|CATLASS 模板算子
tilelang|https://github.com/tile-ai/tilelang-ascend.git|ascendc_pto|tilelang-op-*,tilelang-pass-*,tilelang-perf-*,tilelang-ascend-tile-api,tilelang-a5-sim-convert,tilelang-custom-skill/*,tilelang-vector-ascend-ops-migration|TileLang 全栈（含 Pass 层）
pto|https://github.com/huawei-csl/pto-kernels.git|main|testing-pto-kernels|PyPTO 双代算子参考
xllm-kernel|https://github.com/xLLM-AI/xllm.git|main|tilelang-ascend-kernel|TileLang kernel（含 Triton→TileLang 映射）
xllm-tilelang|https://github.com/xLLM-AI/xllm-workflow.git|main|tilelang-pto-kernel-workflow|TileLang+PTO 工作流
cannbot-model|https://github.com/ascend-ai-coding/awesome-ascend-skills.git|main|external/cannbot/model/*|model-infer-* 模型级优化
cannbot-ops|https://github.com/ascend-ai-coding/awesome-ascend-skills.git|main|external/cannbot/ops/*,external/cannbot/ops-lab/tilelang/*|AscendC 最佳实践 / PyPTO / npu-arch
cannbot-graph|https://github.com/ascend-ai-coding/awesome-ascend-skills.git|main|external/cannbot/graph/*|npugraph_ex 图模式
fla|https://github.com/fla-org/flash-linear-attention.git|main|fla-ascend-performance,fla-optimization-loop,fla-correctness-coverage|线性注意力昇腾性能闭环
# ===== 运维（性能诊断 / 通信 / 服务化 / 部署）=====
msagent-profiler|https://github.com/kali20gakki/msAgent.git|master|skills/profiler/*|profiler 全家桶（prof-compare/快慢卡/msprof-analyze）
msagent-operator|https://github.com/kali20gakki/msAgent.git|master|skills/operator/*|msdebug/mssanitizer/mstx/ops 调优
agent-skills-ops|https://gitcode.com/Ascend/agent-skills.git|master|hccl-test,ascend-profiling-anomaly|HCCL 基线 + profiling 异常
agent-skills-host|https://gitcode.com/Ascend/agent-skills.git|master|npu-smi,ascend-docker,cann-operator-env-config,atc-model-converter,npu-adapter-reviewer|主机/容器/环境/ATC
god|https://github.com/XiaoLuoLYG/GOD.git|main|deepep-to-cam-converter,ascend-moe-optimizer-*|DeepEP→CAM / MoE 优化追踪
mindie-motor|https://github.com/Ascend/MindIE-Motor.git|master|motor-*|PD 分离服务全生命周期
xllm-ops|https://github.com/xLLM-AI/xllm-workflow.git|main|xllm-npu-*|xLLM NPU 运维（profiler/benchmark/incident）
vllm-ascend|https://github.com/vllm-project/vllm-ascend.git|main|vllm-ascend-*|官方插件（model-adapter/release）
sglang-npu|https://github.com/LinyuanLi0046/Ascend-SGLang-Skills.git|main|npu-api-adaptation-checker,sglang-npu-adapter,test-regression-pr-locator|SGLang-NPU 适配检查
# ===== 门禁（量化 / 精度 / 性能）=====
msmodelslim|https://gitcode.com/Ascend/msmodelslim.git|master|*|量化与 evaluate/tuning
mindie-sd-gate|https://github.com/Ascend/MindIE-SD.git|dev|accuracy-gate,perf-gate,quantization-dev,profiling-collect,profiling-analyze,performance-optimization|L1/L2/L3 与探索态/验收态
EOF
}

usage() {
  cat <<'EOF'
用法: sync_ascend_skills.sh [选项]

allowlist 驱动：从 14 个昇腾生态源仓（22 条规则）发现并同步 SKILL.md 技能目录。
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
      执行克隆/复用缓存与匹配，但不拷贝，只列出将同步的技能（含目标路径）。
  -h | --help
      打印本帮助。

行为:
  - include 为逗号分隔 glob，同时尝试匹配技能目录相对路径与目录名
    （* 不跨 /，** 跨 /）。
  - 目录名或相对路径含 triton（不区分大小写）→ SKIPPED，不同步。
  - 目标 .agents/skills/<目录名>/ 已存在 → CONFLICT，不覆盖。
  - 单源失败计入 FAIL 不中断；末尾汇总 ADDED / SKIPPED / CONFLICT / FAIL。

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
  if tar -C "$src" --exclude='.git' --exclude='*/.git' -cf - . | tar -C "$dest" -xf -; then
    return 0
  fi
  return 1
}

# 克隆/复用缓存（按唯一 URL 调用一次）
prepare_cache() {
  local url="$1" branch="$2" origin="$3"
  local cache_dir="$CACHE_DIR/$(url_slug "$url")"
  if [ -e "$cache_dir" ] && [ ! -d "$cache_dir/.git" ]; then
    echo "  错误：${cache_dir} 已存在但不是独立 Git 仓（脚本不会自动删除）。" >&2
    return 1
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

# --list：完全离线，3 分组 + 22 行 + 合计
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

# 处理单行规则：发现 -> 父目录覆盖去重 -> include 匹配 -> triton 排除 -> 冲突检测 -> 拷贝/列出
process_row() {
  local g="$1" origin="$2" url="$3" branch="$4" include="$5" dry_run="$6"
  local cache_dir rel dir_name dest
  local hits=0 added=0 skipped=0 conflict=0 accepted_rel=""
  echo ""
  echo "---- [${g}] ${origin} (branch=${branch}) ----"
  cache_dir="$CACHE_DIR/$(url_slug "$url")"
  if [ ! -d "$cache_dir" ]; then
    echo "  FAIL：${origin} 缓存目录缺失（${cache_dir}）" >&2
    FAIL=$((FAIL + 1))
    echo "  [${origin}] hits=0 added=0 skipped=0 conflict=0"
    return 0
  fi
  while IFS= read -r rel; do
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
      echo "  SKIPPED: ${rel}（含 triton，兜底排除）"
      continue
    fi
    if [ "$rel" = "." ]; then
      dir_name="$(repo_basename "$url")"
    else
      dir_name="$(basename "$rel")"
    fi
    dest="$DEST_ROOT/$dir_name"
    if [ -e "$dest" ]; then
      conflict=$((conflict + 1))
      CONFLICT=$((CONFLICT + 1))
      echo "  CONFLICT: ${dest} 已存在（来源 ${origin}），跳过不覆盖"
      continue
    fi
    if [ "$rel" = "." ]; then
      # 仓根即技能：整体拷贝（排除 .git），其后所有发现均视为已覆盖
      if [ "$dry_run" -eq 1 ]; then
        ADDED=$((ADDED + 1))
        added=$((added + 1))
        echo "  + ${dest}/（仓根 SKILL.md）"
      elif copy_skill "$cache_dir" "$dest"; then
        ADDED=$((ADDED + 1))
        added=$((added + 1))
      else
        echo "  FAIL：${origin} 拷贝仓根技能到 ${dest} 失败" >&2
        FAIL=$((FAIL + 1))
      fi
      echo "  ${origin}：仓根含 SKILL.md，已整体拷贝，其余发现视为已覆盖"
      break
    fi
    if [ "$dry_run" -eq 1 ]; then
      ADDED=$((ADDED + 1))
      added=$((added + 1))
      echo "  + ${dest}/"
      accepted_rel="$rel"
      continue
    fi
    if copy_skill "$cache_dir/$rel" "$dest"; then
      ADDED=$((ADDED + 1))
      added=$((added + 1))
      accepted_rel="$rel"
    else
      echo "  FAIL：${origin} 拷贝技能目录 ${rel} 失败" >&2
      FAIL=$((FAIL + 1))
    fi
  done < <(find "$cache_dir" -type f -iname SKILL.md \
           | while IFS= read -r skill_md; do
               [ -z "$skill_md" ] && continue
               dirname "${skill_md#"$cache_dir"/}"
             done | sort -u)
  echo "  [${origin}] hits=${hits} added=${added} skipped=${skipped} conflict=${conflict}"
}

cmd_sync() {
  local want="$1" only="${2:-}" dry_run="$3"
  local g origin url branch include note
  local n_rows=0 prepared="" failed=""
  if ! command -v git >/dev/null 2>&1; then
    echo "错误：未找到 git。同步技能需要 git（浅克隆与 fetch），请先安装 git。" >&2
    exit 1
  fi
  # 统计选中行数：用于 --only 无匹配的友好提示
  while IFS='|' read -r g origin url branch include note; do
    n_rows=$((n_rows + 1))
  done < <(filtered_rows "$want" "$only")
  if [ -n "$only" ] && [ "$n_rows" -eq 0 ]; then
    echo "警告：源表中没有 origin 为 '${only}' 的条目（结合 --category 过滤后亦无匹配）。" >&2
  fi
  # pass 1：按唯一 URL 准备缓存（同一 URL 多行规则共享，只 clone/fetch 一次）
  while IFS='|' read -r g origin url branch include note; do
    case " $prepared $failed " in *" $url "*) continue ;; esac
    if prepare_cache "$url" "$branch" "$origin"; then
      prepared="$prepared $url"
    else
      failed="$failed $url"
      FAIL=$((FAIL + 1))
    fi
  done < <(filtered_rows "$want" "$only")
  # pass 2：逐行匹配与同步
  while IFS='|' read -r g origin url branch include note; do
    case " $failed " in *" $url "*) continue ;; esac
    process_row "$g" "$origin" "$url" "$branch" "$include" "$dry_run"
  done < <(filtered_rows "$want" "$only")
  echo ""
  echo "汇总：ADDED ${ADDED} / SKIPPED ${SKIPPED} / CONFLICT ${CONFLICT} / FAIL ${FAIL}"
  [ "$FAIL" -eq 0 ]
}

main() {
  local category="all" only="" dry_run=0 list_only=0
  if [ "$#" -eq 0 ]; then
    usage
    exit 0
  fi
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --list) list_only=1 ;;
      -h|--help|help) usage; exit 0 ;;
      --dry-run) dry_run=1 ;;
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
  if [ "$list_only" -eq 1 ]; then
    cmd_list
    exit 0
  fi
  cmd_sync "$category" "$only" "$dry_run"
}

main "$@"
