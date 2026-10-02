#!/usr/bin/env bash
set -o pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh"
# shellcheck source=naming.sh
. "$here/../naming.sh"
check 'program path normalization' nvim "$(ar_pane_label /usr/bin/nvim '' '' '')"
check 'login shell normalization' zsh "$(ar_pane_label -zsh '' '' '')"
check 'program' nvim "$(ar_pane_label nvim '' '' '')"
for shell in zsh bash fish; do
  check "prompt $shell" "$shell" "$(ar_pane_label '' "$shell" '' '')"
done
check 'Chinese agent task' 'codex：添加pane自动命名功能' "$(ar_pane_label node '' codex 添加pane自动命名功能)"
check 'untitled agent' claude "$(ar_pane_label node '' claude '')"
check 'clean controls and whitespace' 'codex：fix build' "$(ar_pane_label '' '' codex $' fix\n\tbuild ')"
MAX_TITLE_LEN=2
check 'task budget preserves full agent prefix' 'codex：添加' "$(ar_pane_label '' '' codex 添加pane自动命名功能)"
MAX_NAME_LEN=3
check 'program budget' nvi "$(ar_pane_label nvim '' '' '')"
MAX_NAME_LEN=20
HIDE_SHELL=1 TITLE_STYLE=task ICONS_ENABLED=1 SHOW_PROGRAM_ARGS=1 TAB_NAME_DIRECTORY_ONLY=1
IGNORED_PROGRAMS=(nvim); PROGRAM_ALIASES=('nvim=vi')
check 'tab knobs cannot hide program' nvim "$(ar_pane_label nvim '' '' '')"
check 'tab knobs cannot hide shell' zsh "$(ar_pane_label '' zsh '' '')"
check 'tab knobs cannot hide agent prefix' 'codex：修复' "$(ar_pane_label '' '' codex 修复构建)"
t_summary
