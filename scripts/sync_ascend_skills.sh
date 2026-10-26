#!/usr/bin/env bash
# sync_ascend_skills.sh — 浅克隆昇腾生态仓库，自动发现并同步 SKILL.md 技能目录
# 策略：不硬编码各仓内的技能子路径（各仓异构：skills/、.agents/skills/、
#       .claude/skills/、plugins-*/ 等），克隆后全仓 find SKILL.md 自动发现。
# 落点：.agents/skills/external/<category>/<name>/<技能目录相对路径>/（根仓库
#       .gitignore 忽略该目录内容，仅保留 README.md）。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
CACHE_DIR="$ROOT/.cache/skills"
DEST_ROOT="$ROOT/.agents/skills/external"

OK=0
FAIL=0

# 内置技能源数据表：category|name|url|branch（url/branch 已联网核验，勿改分支）
skill_sources() {
  cat <<'EOF'
operators|cannbot-skills|https://gitcode.com/cann/cannbot-skills.git|master
operators|tilelang-ascend|https://github.com/tile-ai/tilelang-ascend.git|ascendc_pto
operators|xllm|https://github.com/xLLM-AI/xllm.git|main
operators|pto-kernels|https://github.com/huawei-csl/pto-kernels.git|main
operators|catlass|https://gitcode.com/cann/catlass.git|master
operators|ascend-agent-skills|https://gitcode.com/Ascend/agent-skills.git|master
operators|xllm-workflow|https://github.com/xLLM-AI/xllm-workflow.git|main
network|god|https://github.com/XiaoLuoLYG/GOD.git|main
network|msagent|https://gitcode.com/Ascend/msagent.git|master
network|msagent-mirror|https://github.com/kali20gakki/msAgent.git|master
network|mindie-motor|https://github.com/Ascend/MindIE-Motor.git|master
tooling|msmodelslim|https://gitcode.com/Ascend/msmodelslim.git|master
tooling|mindie-sd|https://github.com/Ascend/MindIE-SD.git|dev
tooling|evalscope|https://github.com/modelscope/evalscope.git|main
tooling|model-agent|https://gitcode.com/Ascend/model-agent.git|master
tooling|awesome-ascend-skills|https://github.com/ascend-ai-coding/awesome-ascend-skills.git|main
engines|vllm-ascend|https://github.com/vllm-project/vllm-ascend.git|main
engines|ascend-sglang-skills|https://github.com/LinyuanLi0046/Ascend-SGLang-Skills.git|main
engines|cann-recipes-infer|https://gitcode.com/cann/cann-recipes-infer.git|master
engines|mindie-llm|https://gitcode.com/Ascend/MindIE-LLM.git|master
engines|sglang|https://github.com/sgl-project/sglang.git|main
EOF
}

usage() {
  cat <<'EOF'
用法: sync_ascend_skills.sh <子命令> [参数]

子命令:
  --list
      离线列出内置技能源数据表：4 大域 operators / network / tooling / engines，
      每域下 name、url、branch，末尾打印各域条目数（不访问网络）。
  --category <operators|network|tooling|engines|all> [--only <name>]
      对每个条目：浅克隆源仓到 .cache/skills/<name>（已存在则
      fetch --depth 1 + checkout FETCH_HEAD 更新），然后在仓内 find 所有含
      SKILL.md 的目录，将每个技能目录（保留仓内相对路径结构，按前缀去重，
      避免嵌套/同名混叠）拷贝到 .agents/skills/external/<category>/<name>/<相对路径>/。
      单仓失败不中断整体（该仓计入 FAIL），末尾输出 "OK n / FAIL m" 汇总。
  --only <name>
      仅同步内置表中 name 匹配的条目（与 --category 组合使用；
      --category all --only <name> 亦可），用于定向重同步。
  -h | --help
      打印本帮助。

无参数时打印本帮助。
EOF
}

cmd_list() {
  local cat_cur="" category name url branch
  local n_operators=0 n_network=0 n_tooling=0 n_engines=0
  while IFS='|' read -r category name url branch; do
    [ -z "$category" ] && continue
    if [ "$category" != "$cat_cur" ]; then
      [ -n "$cat_cur" ] && echo ""
      cat_cur="$category"
      echo "== $category =="
    fi
    case "$category" in
      operators) n_operators=$((n_operators + 1)) ;;
      network) n_network=$((n_network + 1)) ;;
      tooling) n_tooling=$((n_tooling + 1)) ;;
      engines) n_engines=$((n_engines + 1)) ;;
    esac
    echo "  $name  $url  (branch: $branch)"
  done < <(skill_sources)
  echo ""
  echo "各域条目数：operators=$n_operators network=$n_network tooling=$n_tooling engines=${n_engines}（共 $((n_operators + n_network + n_tooling + n_engines)) 条）"
}

# 同步单个源仓：克隆/更新缓存 -> find 发现 SKILL.md 目录 -> 拷贝到 external 落点
sync_one() {
  local category="$1" name="$2" url="$3" branch="$4"
  local cache_dir="$CACHE_DIR/$name"
  local dest_base="$DEST_ROOT/$category/$name"
  local repo_fail=0
  echo ""
  echo "---- [$category] $name (branch=$branch) ----"
  if [ -e "$cache_dir" ] && [ ! -d "$cache_dir/.git" ]; then
    echo "错误：$cache_dir 已存在但不是独立 Git 仓。请手动删除或移走该目录后重试（脚本不会自动删除）。" >&2
    exit 1
  fi
  if [ -d "$cache_dir/.git" ]; then
    # 缓存已存在：浅层拉取该分支最新提交并切到 FETCH_HEAD，保持浅克隆体积
    if git -C "$cache_dir" fetch --depth 1 origin "$branch" && git -C "$cache_dir" checkout -q FETCH_HEAD; then
      echo "  缓存已存在，已更新到 $branch 最新提交"
    else
      echo "  FAIL：$name 更新缓存失败" >&2
      FAIL=$((FAIL + 1))
      return 0
    fi
  else
    mkdir -p "$CACHE_DIR" || {
      echo "  FAIL：$name 无法创建缓存目录 $CACHE_DIR" >&2
      FAIL=$((FAIL + 1))
      return 0
    }
    if git clone --depth 1 -b "$branch" "$url" "$cache_dir"; then
      echo "  浅克隆完成"
    else
      echo "  FAIL：$name 克隆失败" >&2
      FAIL=$((FAIL + 1))
      return 0
    fi
  fi

  # 发现阶段：收集所有含 SKILL.md 的技能目录（相对缓存仓的路径），字典序排序。
  # 排序保证父目录排在子目录前（父目录是其子目录路径的前缀），按前缀覆盖跳过重复拷贝。
  local n=0 rel accepted_rel=""
  while IFS= read -r rel; do
    [ -z "$rel" ] && continue
    if [ -n "$accepted_rel" ] && [ "${rel#"$accepted_rel"/}" != "$rel" ]; then
      # 已被已接受的目录前缀覆盖（父目录整体已拷贝），跳过
      continue
    fi
    if [ "$rel" = "." ]; then
      # 仓根含 SKILL.md：整体拷贝（排除 .git），其后所有条目均视为被覆盖
      if ! mkdir -p "$dest_base"; then
        echo "  FAIL：$name 创建落点目录 $dest_base 失败" >&2
        repo_fail=1
        return 0
      fi
      local item base
      for item in "$cache_dir"/* "$cache_dir"/.[!.]*; do
        [ -e "$item" ] || continue
        base="$(basename "$item")"
        [ "$base" = ".git" ] && continue
        if cp -R "$item" "$dest_base/"; then
          n=$((n + 1))
        else
          echo "  FAIL：$name 拷贝 $base 失败" >&2
          repo_fail=1
        fi
      done
      echo "  ${name}：仓根含 SKILL.md，已整体拷贝 $n 项，其余子目录视为已覆盖"
      break
    fi
    # 常规技能目录：保留仓内相对路径结构，落点唯一（无同名混叠）
    if ! mkdir -p "$(dirname "$dest_base/$rel")"; then
      echo "  FAIL：$name 创建落点目录 $(dirname "$dest_base/$rel") 失败" >&2
      repo_fail=1
      return 0
    fi
    if cp -R "$cache_dir/$rel" "$dest_base/$rel"; then
      n=$((n + 1))
      accepted_rel="$rel"
    else
      echo "  FAIL：$name 拷贝技能目录 $rel 失败" >&2
      repo_fail=1
    fi
  done < <(find "$cache_dir" -type f -iname SKILL.md \
           | while IFS= read -r skill_md; do
               [ -z "$skill_md" ] && continue
               dirname "${skill_md#"$cache_dir"/}"
             done | sort -u)

  if [ "$repo_fail" -eq 0 ]; then
    OK=$((OK + 1))
    echo "  ${name}：发现并同步 $n 个技能目录 -> $dest_base/"
  else
    FAIL=$((FAIL + 1))
    echo "  ${name}：存在失败项，该仓计入 FAIL" >&2
  fi
}

cmd_category() {
  local want="$1" only="${2:-}"
  local category name url branch matched=0
  case "$want" in
    operators|network|tooling|engines|all) ;;
    *)
      echo "错误：--category 参数必须是 operators | network | tooling | engines | all。" >&2
      exit 1
      ;;
  esac
  if ! command -v git >/dev/null 2>&1; then
    echo "错误：未找到 git。同步技能需要 git（浅克隆与 fetch）。请先安装 git。" >&2
    exit 1
  fi
  while IFS='|' read -r category name url branch; do
    [ -z "$category" ] && continue
    if [ "$want" != "all" ] && [ "$category" != "$want" ]; then
      continue
    fi
    if [ -n "$only" ] && [ "$name" != "$only" ]; then
      continue
    fi
    matched=$((matched + 1))
    sync_one "$category" "$name" "$url" "$branch"
  done < <(skill_sources)
  if [ -n "$only" ] && [ "$matched" -eq 0 ]; then
    echo "警告：内置表中没有 name 为 '$only' 的条目（结合 --category 过滤后亦无匹配）。" >&2
  fi
  echo ""
  echo "汇总：OK $OK / FAIL $FAIL"
  [ "$FAIL" -eq 0 ]
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    ""|-h|--help|help) usage ;;
    --list) cmd_list ;;
    --category|--only)
      local want="all" only=""
      if [ "$cmd" = "--category" ]; then
        if [ "$#" -lt 2 ]; then
          echo "错误：--category 需要一个参数（operators|network|tooling|engines|all）。" >&2
          usage
          exit 1
        fi
        want="$2"
        if [ "${3:-}" = "--only" ]; then
          if [ "$#" -lt 4 ]; then
            echo "错误：--only 需要一个参数（内置表中的 name）。" >&2
            usage
            exit 1
          fi
          only="$4"
        fi
      else
        if [ "$#" -lt 2 ]; then
          echo "错误：--only 需要一个参数（内置表中的 name）。" >&2
          usage
          exit 1
        fi
        only="$2"
        if [ "${3:-}" = "--category" ]; then
          if [ "$#" -lt 4 ]; then
            echo "错误：--category 需要一个参数（operators|network|tooling|engines|all）。" >&2
            usage
            exit 1
          fi
          want="$4"
        fi
      fi
      cmd_category "$want" "$only"
      ;;
    *)
      echo "错误：未知子命令 '$cmd'。" >&2
      usage
      exit 1
      ;;
  esac
}

main "$@"
