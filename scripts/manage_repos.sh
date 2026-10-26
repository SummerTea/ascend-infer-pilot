#!/usr/bin/env bash
# manage_repos.sh — repos/ 双轨源码目录管理：列表 / 克隆 / 巡检 / 导出补丁
# 依赖：bash + git + python3（仅用标准库手写解析 manifest，不依赖 PyYAML / yq）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
MANIFEST="$ROOT/repos/manifest.yaml"

usage() {
  cat <<'EOF'
用法: manage_repos.sh <子命令> [参数]

子命令:
  --list
      解析 repos/manifest.yaml，分 targets / refs 两段列出 name、branch、
      本地克隆状态（[✓ 已克隆] / [ ]）与 role。
  clone <name>
      按 manifest 浅克隆单个仓到 repos/<targets|refs>/<name>
      （git clone --depth 1 -b <branch>）。
  clone --targets | clone --refs
      批量浅克隆该段全部仓库（已存在则跳过）。
  clone <git-url>
      <git-url> 非 manifest 名称且形如 URL 时，浅克隆到
      repos/targets/<basename 去掉 .git>（默认分支）。
  status
      巡检 repos/targets 与 repos/refs 下已克隆的独立 Git 仓：目录名、当前分支、
      最新提交短 hash（git log -1 --format=%h）、未提交改动数
      （git status --porcelain | wc -l）。refs 段只读，打印但标注"只读"，
      供 J3 环境冻结记录。
  export-patch <target_repo> <case_name>
      将 repos/targets/<target_repo> 相对 HEAD 的改动（含已暂存）导出为
      cases/<case_name>/patches/<repo>-<UTC时间戳>.patch，并同时写入
      <repo>-<时间戳>.meta.txt（url / branch / base_commit / 生成时间）。
      导出前会以 intent-to-add（git add -N）方式把新增（untracked）文件
      一并纳入补丁；补丁用 `git apply -p1` 或 `patch -p1` 施用。
      无改动时提示并退出非 0。
  -h | --help
      打印本帮助。

无参数时打印本帮助。
EOF
}

# run_py <mode> [args...]：用 python3 标准库解析固定 schema 的 manifest
#   mode list         —— 打印 --list 输出（含本地克隆状态）
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
    for sec in ("targets", "refs"):
        if sec == "targets":
            print("=== targets：待优化目标工程（可改，导出 patch） ===")
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
            git_dir = os.path.join(ROOT, "repos", sec, n, ".git")
            mark = "[✓ 已克隆]" if os.path.isdir(git_dir) else "[ ]"
            print("  %s%s%s%s" % (n.ljust(w_name), e["branch"].ljust(w_branch),
                                  mark.ljust(9), e["role"]))
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

cmd_clone() {
  if [ "$#" -lt 1 ]; then
    echo "用法: manage_repos.sh clone <name|git-url|--targets|--refs>" >&2
    exit 1
  fi
  local arg="$1"
  case "$arg" in
    --targets|--refs)
      local seg="${arg#--}"
      local entries name url branch target_dir ok=0 fail=0
      entries="$(run_py section "$seg")"
      while IFS=$'\t' read -r name url branch; do
        [ -z "$name" ] && continue
        target_dir="$ROOT/repos/$seg/$name"
        if [ -d "$target_dir/.git" ]; then
          echo "跳过（已存在）: $name"
          continue
        fi
        if [ -e "$target_dir" ]; then
          echo "错误：$target_dir 已存在但不是独立 Git 仓。请手动删除或移走该目录后重试（脚本不会自动删除）。" >&2
          exit 1
        fi
        echo "克隆 ${name}（branch=${branch}，浅克隆）..."
        if git clone --depth 1 -b "$branch" "$url" "$target_dir"; then
          ok=$((ok + 1))
        else
          echo "FAIL：$name 克隆失败" >&2
          fail=$((fail + 1))
          continue
        fi
      done <<< "$entries"
      echo "完成：克隆 $ok 个仓库到 repos/$seg/（失败 $fail 个）。"
      ;;
    *)
      if is_url "$arg"; then
        local base target_dir
        base="$(basename "$arg")"
        base="${base%.git}"
        if [ -z "$base" ]; then
          echo "错误：无法从 URL 推导出目录名：$arg" >&2
          exit 1
        fi
        target_dir="$ROOT/repos/targets/$base"
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
        local entry seg name url branch role target_dir
        if ! entry="$(run_py lookup "$arg")"; then
          echo "错误：'$arg' 既不在 manifest 中，也不像 Git URL。" >&2
          exit 1
        fi
        IFS='|' read -r seg name url branch role <<< "$entry"
        target_dir="$ROOT/repos/$seg/$name"
        if [ -d "$target_dir/.git" ]; then
          echo "跳过（已存在）: $name"
          exit 0
        fi
        if [ -e "$target_dir" ]; then
          echo "错误：$target_dir 已存在但不是独立 Git 仓。请手动删除或移走该目录后重试（脚本不会自动删除）。" >&2
          exit 1
        fi
        mkdir -p "$ROOT/repos/$seg"
        echo "克隆 ${name}（branch=${branch}，浅克隆）..."
        git clone --depth 1 -b "$branch" "$url" "$target_dir"
      fi
      ;;
  esac
}

cmd_status() {
  local found=0 sec label name branch short dirty dir
  for sec in targets refs; do
    if [ "$sec" = "targets" ]; then
      label="目标工程（可修改）"
    else
      label="参考底座（只读）"
    fi
    echo "== $sec / $label =="
    for dir in "$ROOT/repos/$sec"/*/; do
      [ -d "$dir" ] || continue
      name="$(basename "$dir")"
      if [ ! -d "$dir/.git" ]; then
        echo "  跳过（无 .git，非独立 Git 仓）: $name"
        continue
      fi
      found=1
      branch="$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
      short="$(git -C "$dir" log -1 --format=%h 2>/dev/null || echo none)"
      dirty="$(git -C "$dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ' || true)"
      printf "  %-24s  分支 %-18s  最新提交 %-8s  未提交改动 %s\n" \
        "$name" "$branch" "$short" "$dirty"
    done
  done
  if [ "$found" -eq 0 ]; then
    echo ""
    echo "暂无可巡检的克隆仓库：repos/targets 与 repos/refs 下尚无带 .git 的独立 Git 仓。"
    echo "可用 'manage_repos.sh clone --targets' / 'clone --refs' 批量克隆，或 'clone <name>' 单个克隆。"
  fi
}

cmd_export_patch() {
  if [ "$#" -lt 2 ]; then
    echo "用法: manage_repos.sh export-patch <target_repo> <case_name>" >&2
    exit 1
  fi
  local repo="$1" case_name="$2"
  local repo_dir="$ROOT/repos/targets/$repo"
  if [ ! -d "$repo_dir/.git" ]; then
    echo "错误：repos/targets/$repo 不存在或不是独立 Git 仓。" >&2
    exit 1
  fi

  # intent-to-add：让 untracked 新文件进入 diff HEAD（仅标记，不真正暂存内容）
  git -C "$repo_dir" add -N . 2>/dev/null || true

  # git diff HEAD 同时覆盖已暂存、未暂存与 intent-to-add 的新文件；为空即无改动
  if [ -z "$(git -C "$repo_dir" diff HEAD --binary 2>/dev/null || true)" ]; then
    echo "repos/targets/$repo 相对 HEAD 无改动（含已暂存与新增文件），无需导出 patch。"
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
  outdir="$ROOT/cases/$case_name/patches"
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
    --list|-l) run_py list ;;
    clone) shift; cmd_clone "$@" ;;
    status) cmd_status ;;
    export-patch) shift; cmd_export_patch "$@" ;;
    *)
      echo "错误：未知子命令 '$cmd'。" >&2
      usage
      exit 1
      ;;
  esac
}

main "$@"
