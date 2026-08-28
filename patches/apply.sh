#!/usr/bin/env bash
# DSH fork 补丁重放脚本
# 用法: 在 deepseek-harness 仓库根目录执行
#   bash patches/apply.sh
# 适用于: git fetch upstream && git merge upstream/master 之后

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

echo "=== DSH Fork Patcher ==="
echo "仓库: $REPO_ROOT"
echo ""

PATCHES=(
  "001-windows-hide.patch"
  "002-postmortem-docs.patch"
)

FAILED=0
for patch in "${PATCHES[@]}"; do
  patch_file="patches/$patch"
  if [[ ! -f "$patch_file" ]]; then
    echo "[跳过] $patch (文件不存在)"
    continue
  fi
  echo -n "[应用] $patch ... "
  if git apply --check "$patch_file" 2>/dev/null; then
    git apply "$patch_file"
    echo "OK"
  else
    echo "冲突! 手动解决后运行: git apply --3way $patch_file"
    FAILED=$((FAILED + 1))
  fi
done

if [[ $FAILED -eq 0 ]]; then
  echo ""
  echo "全部补丁应用成功。"
else
  echo ""
  echo "有 $FAILED 个补丁存在冲突，请手动解决。"
fi
