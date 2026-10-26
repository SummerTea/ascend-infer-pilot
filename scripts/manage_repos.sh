#!/usr/bin/env bash
# manage_repos.sh — 源码仓管理：列表 / 克隆 / 巡检 / 导出补丁
#   落点：targets（待优化目标工程，按场景）→ workspace/<scenario-id>/source/<name>（每场景一份、不入库）
#         refs（只读参考底座）→ repos/refs/<name>（严禁修改）
# 依赖：bash + git + python3（仅用标准库手写解析 manifest，不依赖 PyYAML / yq）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
MANIFEST="$ROOT/repos/manifest.yaml"
REFS_DIR="$ROOT/repos/refs"

# 返回场景工作区目录 workspace/<id>（targets 落点按场景隔离，每场景一份、独立 .git）
scenario_dir() {
  printf '%s' "$ROOT/workspace/$1"
}

# 公共参数解析：抽取 --scenario <id> 到 SCENARIO，其余位置参数以空格拼接回 ARGS
parse_common() {
  SCENARIO=""
  ARGS=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --scenario)
        shift
        if [ "$#" -lt 1 ]; then
          echo "错误：--scenario 需要一个场景 ID（如 2x910B-dsv41-flash-rocm-net）。" >&2
          usage
          exit 1
        fi
        SCENARIO="$1"
        ;;
      *)
        if [ -n "$ARGS" ]; then
          ARGS="${ARGS} $1"
        else
          ARGS="$1"
        fi
        ;;
    esac
    shift
  done
}

usage() {
  cat <<'EOF'
用法: manage_repos.sh <子命令> [参数]

子命令:
  --list [--scenario <id>]
       解析 repos/manifest.yaml，分 targets / refs 两段列出 name、branch、
       本地克隆状态（[✓ 已克隆] / [ ]）与 role。targets 按场景落点
       workspace/<scenario-id>/source/，须 --scenario <id> 才能显示克隆状态；
       不给 --scenario 时 targets 状态列显示"需 --scenario"。refs 恒显示
       repos/refs/<name> 的状态。
  clone <name|--targets|--refs|URL> [--scenario <id>]
       按 manifest 浅克隆（git clone --depth 1 -b <branch>）：
       targets 段与任意 URL 必须给 --scenario <id>，落到
       workspace/<id>/source/<name>（每场景一份、不入库、独立 .git）；
       refs 段落到 repos/refs/<name>（只读），不需要 --scenario。
       --targets / --refs 批量浅克隆该段全部仓库（已存在则跳过）。
  status [--scenario <id>]
       巡检独立 Git 仓：目录名、当前分支、最新提交短 hash
       （git log -1 --format=%h）、未提交改动数（git status --porcelain | wc -l）。
       给 --scenario 巡检该场景 workspace/<id>/source；不给则按场景分组巡检
       workspace/*/source，并恒巡检 repos/refs（只读，供 J3 环境冻结记录）。
  export-patch <target_repo> --scenario <id>
       将 workspace/<id>/source/<target_repo> 相对 HEAD 的改动（含已暂存）导出
       为 workspace/<id>/ledger/patches/<repo>-<UTC时间戳>.patch，并同时写入
       <repo>-<时间戳>.meta.txt（url / branch / base_commit / 生成时间）。
       导出前会以 intent-to-add（git add -N）方式把新增（untracked）文件一并
       纳入补丁；补丁用 `git apply -p1` 或 `patch -p1` 施用。无改动时提示并退出非 0。
  -h | --help
       打印本帮助。

示例:
  manage_repos.sh clone --targets --scenario 2x910B-dsv41-flash-rocm-net
  manage_repos.sh clone vllm-ascend --scenario 2x910B-dsv41-flash-rocm-net
  manage_repos.sh clone --refs
  manage_repos.sh status --scenario 2x910B-dsv41-flash-rocm-net
  manage_repos.sh export-patch vllm-ascend --scenario 2x910B-dsv41-flash-rocm-net

无参数时打印本帮助。
EOF
}

# run_py <mode> [args...]：用 python3 标准库解析固定 schema 的 manifest
#   mode list [<scenario>] —— 打印 --list 输出（含本地克隆状态；targets 需场景参数查 workspace/<scenario>/source/<name>/.git，refs 查 repos/refs/<name>/.git）
#   mode lookup <n>   —— 命中输出 "section|name|url|branch|role" 退出 0；未命中报错退出 1
#   mode section <s>  —— 输出该段全部条目 "name<TAB>url<TAB>branch"
run_py() {
  if ! command -v python3 >/dev/null 2>&1; then
    echo "错误：未找到 python3。解析 repos/manifest.yaml 需要 python3 标准库（不依赖 PyYAML）。" >&2
    echo "      请先安装 Python 3 后重试。" >&2
    exit 1
  fi
  python3 - "$ROOT" "$@" <<'PYEOF'
import os
import sys

ROOT = sys.argv[1]
MANIFEST = os.path.join(ROOT, "repos", "manifest.yaml")
MODE = sys.argv[2] if len(sys.argv) > 2 else ""


def die(msg):
    print("错误：" + msg, file=sys.stderr)
    sys.exit(1)


def parse_manifest(path):
    """手写 YAML 子集解析器，仅支持本 manifest 的固定 schema：
    <section>:\n    <name>:\n        url: ...\n        branch: ...\n        role: ..."""
    data = {"targets": {}, "refs": {}}
    section = None
    name = None
    try:
        f = open(path, encoding="utf-8")
    except OSError as e:
        die("无法读取 manifest %s: %s" % (path, e))
    with f:
        for lineno, raw in enumerate(f, 1):
            line = raw.rstrip("\r\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            indent = len(line) - len(line.lstrip())
            stripped = line.strip()
            if indent == 0:
                if stripped.endswith(":"):
                    section = stripped[:-1]
                    if section not in data:
                        die("manifest 第 %d 行存在未知顶层段 '%s'" % (lineno, section))
                    name = None
                else:
                    die("manifest 第 %d 行不是段定义" % lineno)
            elif indent == 2 and stripped.endswith(":"):
                name = stripped[:-1]
                data[section][name] = {}
            elif indent == 4:
                if name is None:
                    die("manifest 第 %d 行缺少所属仓库" % lineno)
                key, _, val = stripped.partition(":")
                val = val.strip()
                # role 值在 manifest 中用 YAML 双引号包裹，展示时剥掉
                if len(val) >= 2 and val[0] == '"' and val[-1] == '"':
                    val = val[1:-1]
                data[section][name][key.strip()] = val
            else:
                die("manifest 第 %d 行缩进不符合固定 schema" % lineno)
    for sec in ("targets", "refs"):
        for n, e in data[sec].items():
            missing = [k for k in ("url", "branch", "role") if k not in e]
            if missing:
                die("仓库 '%s' 缺少字段 %s" % (n, missing))
    return data


data = parse_manifest(MANIFEST)

if MODE == "list":
    scenario = sys.argv[3] if len(sys.argv) > 3 else ""
    for sec in ("targets", "refs"):
        if sec == "targets":
            print("=== targets：待优化目标工程（按场景，clone 需 --scenario） ===")
            if not scenario:
                print("  提示：targets 落点 workspace/<scenario-id>/source/，未指定场景时状态列显示'需 --scenario'；")
                print("        可用 --list --scenario <id> 查看某场景的克隆状态。")
        else:
            print("=== refs：只读参考底座（严禁修改） ===")
        names = list(data[sec])
        if not names:
            print("  （空）")
            continue
        w_name = max(len(n) for n in names) + 2
        w_branch = max(len(data[sec][n]["branch"]) for n in names) + 2
        for n in names:
            e = data[sec][n]
            if sec == "targets":
                if scenario:
                    git_dir = os.path.join(ROOT, "workspace", scenario, "source", n, ".git")
                    mark = "[✓ 已克隆]" if os.path.isdir(git_dir) else "[ ]"
                else:
                    mark = "需 --scenario"
            else:
                git_dir = os.path.join(ROOT, "repos", "refs", n, ".git")
                mark = "[✓ 已克隆]" if os.path.isdir(git_dir) else "[ ]"
            print("  %s%s%s  %s" % (n.ljust(w_name), e["branch"].ljust(w_branch),
                                    mark.ljust(12), e["role"]))
        print()
elif MODE == "lookup":
    target = sys.argv[3] if len(sys.argv) > 3 else ""
    for sec in ("targets", "refs"):
        if target in data[sec]:
            e = data[sec][target]
            print("|".join([sec, target, e["url"], e["branch"], e["role"]]))
            sys.exit(0)
    die("manifest 中不存在仓库 '%s'" % target)
elif MODE == "section":
    sec = sys.argv[3] if len(sys.argv) > 3 else ""
    if sec not in data:
        die("未知段 '%s'（应为 targets 或 refs）" % sec)
    for n, e in data[sec].items():
        print("\t".join([n, e["url"], e["branch"]]))
else:
    die("未知 python 模式 '%s'" % MODE)
PYEOF
}

is_url() {
  case "$1" in
    http://*|https://*|git://*|git@*|ssh://*) return 0 ;;
    *) return 1 ;;
  esac
}

# clone_one <name> <url> <branch> <dest_parent>：单仓浅克隆
#   返回 0 = 新克隆成功；2 = 已存在跳过；目录存在但无 .git → 报错退出 1（不自动删除）
clone_one() {
  local name="$1" url="$2" branch="$3" dest_parent="$4"
  local target_dir="$dest_parent/$name"
  if [ -d "$target_dir/.git" ]; then
    echo "跳过（已存在）: $name"
    return 2
  fi
  if [ -e "$target_dir" ]; then
    echo "错误：$target_dir 已存在但不是独立 Git 仓。请手动删除或移走该目录后重试（脚本不会自动删除）。" >&2
    exit 1
  fi
  echo "克隆 ${name}（branch=${branch}，浅克隆）..."
  git clone --depth 1 -b "$branch" "$url" "$target_dir"
}

# clone_batch <seg>：批量浅克隆该段全部仓库；targets 段须已设置 SCENARIO
clone_batch() {
  local seg="$1" base_dir entries name url branch ok=0 fail=0
  if [ "$seg" = "targets" ]; then
    base_dir="$(scenario_dir "$SCENARIO")/source"
  else
    base_dir="$REFS_DIR"
  fi
  mkdir -p "$base_dir"
  entries="$(run_py section "$seg")"
  while IFS=$'\t' read -r name url branch; do
    [ -z "$name" ] && continue
    if clone_one "$name" "$url" "$branch" "$base_dir"; then
      ok=$((ok + 1))
    elif [ "$?" -eq 2 ]; then
      :
    else
      echo "FAIL：$name 克隆失败" >&2
      fail=$((fail + 1))
      continue
    fi
  done <<< "$entries"
  echo "完成：克隆 $ok 个仓库到 ${base_dir}/（失败 $fail 个）。"
}

cmd_clone() {
  parse_common "$@"
  set -- $ARGS
  if [ "$#" -lt 1 ]; then
    echo "用法: manage_repos.sh clone <name|git-url|--targets|--refs> [--scenario <id>]" >&2
    exit 1
  fi
  local arg="$1"
  case "$arg" in
    --targets)
      if [ -z "$SCENARIO" ]; then
        echo "错误：clone --targets 必须指定 --scenario <id>（targets 按场景落点 workspace/<id>/source/）。" >&2
        usage
        exit 1
      fi
      clone_batch targets
      ;;
    --refs)
      clone_batch refs
      ;;
    *)
      if is_url "$arg"; then
        local base base_dir target_dir
        base="$(basename "$arg")"
        base="${base%.git}"
        if [ -z "$base" ]; then
          echo "错误：无法从 URL 推导出目录名：$arg" >&2
          exit 1
        fi
        if [ -z "$SCENARIO" ]; then
          echo "错误：clone <git-url> 必须指定 --scenario <id>（URL 属待优化目标，落点 workspace/<id>/source/）。" >&2
          usage
          exit 1
        fi
        base_dir="$(scenario_dir "$SCENARIO")/source"
        mkdir -p "$base_dir"
        target_dir="$base_dir/$base"
        if [ -d "$target_dir/.git" ]; then
          echo "跳过（已存在）: $base"
          exit 0
        fi
        if [ -e "$target_dir" ]; then
          echo "错误：$target_dir 已存在但不是独立 Git 仓。请手动删除或移走该目录后重试（脚本不会自动删除）。" >&2
          exit 1
        fi
        echo "克隆 ${base}（默认分支，浅克隆）..."
        git clone --depth 1 "$arg" "$target_dir"
      else
        local entry seg name url branch role base_dir rc=0
        if ! entry="$(run_py lookup "$arg")"; then
          echo "错误：'$arg' 既不在 manifest 中，也不像 Git URL。" >&2
          exit 1
        fi
        IFS='|' read -r seg name url branch role <<< "$entry"
        if [ "$seg" = "targets" ]; then
          if [ -z "$SCENARIO" ]; then
            echo "错误：clone ${arg} 属 targets 段，必须指定 --scenario <id>（落点 workspace/<id>/source/${name}）。" >&2
            usage
            exit 1
          fi
          base_dir="$(scenario_dir "$SCENARIO")/source"
        else
          base_dir="$REFS_DIR"
        fi
        mkdir -p "$base_dir"
        clone_one "$name" "$url" "$branch" "$base_dir" || rc=$?
        if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then
          echo "FAIL：$name 克隆失败" >&2
          exit 1
        fi
      fi
      ;;
  esac
}

CLONED_COUNT=0

# print_cloned <base_dir>：打印 base_dir 下各独立 Git 仓状态；仓数写入全局 CLONED_COUNT
print_cloned() {
  local base_dir="$1"
  local dir name branch short dirty
  CLONED_COUNT=0
  for dir in "$base_dir"/*/; do
    [ -d "$dir" ] || continue
    name="$(basename "$dir")"
    if [ ! -d "$dir/.git" ]; then
      echo "  跳过（无 .git，非独立 Git 仓）: $name"
      continue
    fi
    CLONED_COUNT=$((CLONED_COUNT + 1))
    branch="$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
    short="$(git -C "$dir" log -1 --format=%h 2>/dev/null || echo none)"
    dirty="$(git -C "$dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ' || true)"
    printf "  %-24s  分支 %-18s  最新提交 %-8s  未提交改动 %s\n" \
      "$name" "$branch" "$short" "$dirty"
  done
}

cmd_status() {
  parse_common "$@"
  set -- $ARGS
  if [ "$#" -gt 0 ]; then
    echo "错误：status 不支持位置参数，请用 --scenario <id> 限定单个场景。" >&2
    usage
    exit 1
  fi
  local found=0 sdir sid
  if [ -n "$SCENARIO" ]; then
    echo "== targets / 场景 ${SCENARIO} 目标工程（可修改，workspace/${SCENARIO}/source） =="
    print_cloned "$(scenario_dir "$SCENARIO")/source"
    found=$((found + CLONED_COUNT))
  else
    for sdir in "$ROOT"/workspace/*/; do
      [ -d "$sdir" ] || continue
      sid="$(basename "$sdir")"
      echo "== targets / 场景 ${sid} 目标工程（可修改，workspace/${sid}/source） =="
      print_cloned "$sdir/source"
      found=$((found + CLONED_COUNT))
    done
  fi
  echo "== refs / 参考底座（只读，repos/refs） =="
  print_cloned "$REFS_DIR"
  found=$((found + CLONED_COUNT))
  if [ "$found" -eq 0 ]; then
    echo ""
    echo "暂无可巡检的克隆仓库：workspace/<scenario-id>/source 与 repos/refs 下尚无带 .git 的独立 Git 仓。"
    echo "可用 'manage_repos.sh clone --targets --scenario <id>' / 'clone --refs' 批量克隆，或 'clone <name> --scenario <id>' 单个克隆。"
  fi
}

cmd_export_patch() {
  parse_common "$@"
  set -- $ARGS
  if [ "$#" -lt 1 ]; then
    echo "用法: manage_repos.sh export-patch <target_repo> --scenario <id>" >&2
    exit 1
  fi
  if [ -z "$SCENARIO" ]; then
    echo "错误：export-patch 必须指定 --scenario <id>（仓目录 workspace/<id>/source/<repo>）。" >&2
    usage
    exit 1
  fi
  local repo="$1"
  local repo_dir="$(scenario_dir "$SCENARIO")/source/$repo"
  if [ ! -d "$repo_dir/.git" ]; then
    echo "错误：workspace/${SCENARIO}/source/${repo} 不存在或不是独立 Git 仓。" >&2
    exit 1
  fi

  # intent-to-add：让 untracked 新文件进入 diff HEAD（仅标记，不真正暂存内容）
  git -C "$repo_dir" add -N . 2>/dev/null || true

  # git diff HEAD 同时覆盖已暂存、未暂存与 intent-to-add 的新文件；为空即无改动
  if [ -z "$(git -C "$repo_dir" diff HEAD --binary 2>/dev/null || true)" ]; then
    echo "workspace/${SCENARIO}/source/${repo} 相对 HEAD 无改动（含已暂存与新增文件），无需导出 patch。"
    exit 1
  fi

  local entry url="" branch="" _sec _name _role
  if entry="$(run_py lookup "$repo")"; then
    IFS='|' read -r _sec _name url branch _role <<< "$entry"
  else
    echo "警告：$repo 不在 manifest 中，meta.txt 的 url/branch 将留空。" >&2
  fi

  local ts outdir patch_file meta_file base_commit
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  outdir="$(scenario_dir "$SCENARIO")/ledger/patches"
  mkdir -p "$outdir"
  patch_file="$outdir/$repo-$ts.patch"
  meta_file="$outdir/$repo-$ts.meta.txt"

  git -C "$repo_dir" diff HEAD --binary > "$patch_file"
  base_commit="$(git -C "$repo_dir" rev-parse HEAD)"
  {
    echo "repo: $repo"
    echo "url: $url"
    echo "branch: $branch"
    echo "base_commit: $base_commit"
    echo "generated_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$meta_file"

  echo "已导出 patch: $patch_file"
  echo "基线信息:    $meta_file"
  echo "施用方式:    git apply -p1 ${patch_file}（或 patch -p1 < ${patch_file}）"
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    ""|-h|--help|help) usage ;;
    --list|-l) shift; parse_common "$@"; run_py list "$SCENARIO" ;;
    clone) shift; cmd_clone "$@" ;;
    status) shift; cmd_status "$@" ;;
    export-patch) shift; cmd_export_patch "$@" ;;
    *)
      echo "错误：未知子命令 '$cmd'。" >&2
      usage
      exit 1
      ;;
  esac
}

main "$@"
