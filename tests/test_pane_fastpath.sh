#!/usr/bin/env bash
# Hooks target only their calling terminal, independent of tab ownership.
set -o pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh"
ENGINE="$here/../automatic-rename.sh"
setup() {
  SB=$(mktemp -d "${TMPDIR:-/tmp}/hal-pane-fast.XXXXXX")
  export HERDR_MOCK_DIR="$SB/fixtures" HERDR_MOCK_LOG="$SB/log"
  mkdir -p "$HERDR_MOCK_DIR"
  : >"$HERDR_MOCK_LOG"
  export HERDR_BIN_PATH="$here/mocks/herdr" XDG_STATE_HOME="$SB/state"
  export HERDR_AUTOMATIC_RENAME_CONFIG="$SB/config.sh" HERDR_SOCKET_PATH="$SB/herdr.sock"
  export NAME_PANES=1 NAME_TABS=0 AUTO_INDEX=0 TAB_NAME_DIRECTORY_ONLY=1 HIDE_SHELL=1
  export HERDR_PANE_ID=launch HERDR_TAB_ID=t1
  unset HERDR_SESSION HERDR_SESSION_NAME HERDR_MOCK_FAIL_VERB HERDR_MOCK_FAIL_RENAME
  mkdir -p "$XDG_STATE_HOME/herdr-automatic-rename"
  STATE="$XDG_STATE_HOME/herdr-automatic-rename/state.json"
  printf '{"t1":{"auto":"project","enabled":false}}' >"$STATE"
  fixture pane_launch.json <<'JSON'
{"result":{"pane":{"pane_id":"current","terminal_id":"terminal","tab_id":"t1","label":null,"agent":"codex","terminal_title":"stale task"}}}
JSON
}
fixture() { cat >"$HERDR_MOCK_DIR/$1"; }
run() { /bin/bash "$ENGINE" "$@"; }
log() { cat "$HERDR_MOCK_LOG"; }
cleanup() { rm -rf "$SB"; }
setup
run preexec '/usr/bin/nvim README.md'
check 'preexec ignores stale agent and targets moved current pane' 'pane rename current nvim' "$(log)"
check 'get uses launch-time alias' launch "$(cat "$HERDR_MOCK_LOG.paneget")"
check 'hook records stable terminal' nvim "$(jq -r '.["pane:terminal"].auto' "$STATE")"
for shell in zsh bash fish; do
  : >"$HERDR_MOCK_LOG"
  run precmd "$shell"
  check "precmd positively identifies $shell" "pane rename current $shell" "$(log)"
done
check 'manual tab ownership retained' false "$(jq -r '.t1.enabled' "$STATE")"
cleanup
setup
export NAME_TABS=1
fixture tab_t1.json <<'JSON'
{"result":{"tab":{"tab_id":"t1","label":"manual project"}}}
JSON
run preexec nvim
check 'manual tab cannot prevent pane update' 'pane rename current nvim' "$(log)"
cleanup
setup
fixture procinfo_current.json <<'JSON'
{"result":{"process_info":{"foreground_process_group_id":1,"foreground_processes":[{"pid":1,"argv0":"nvim"}]}}}
JSON
run preexec v shell
check 'function samples actual foreground under directory-only tab mode' 'pane rename current nvim' "$(log)"
check 'sample uses current pane id' current "$(cat "$HERDR_MOCK_LOG.procinfo")"
fixture pane_launch.json <<'JSON'
{"result":{"pane":{"pane_id":"current","terminal_id":"terminal","label":"nvim","tab_id":"t1"}}}
JSON
: >"$HERDR_MOCK_LOG"
run preexec alias shell
check 'sample unchanged program is idempotent' '' "$(log)"
fixture procinfo_current.json <<'JSON'
{"result":{"process_info":{"foreground_process_group_id":1,"foreground_processes":[{"pid":1,"argv0":"-bash"}]}}}
JSON
run preexec cd shell
check 'instant builtin resolves actual idle shell' 'pane rename current bash' "$(log)"
cleanup
setup
run preexec function shell
check 'missing sample preserves label' '' "$(log)"
fixture procinfo_current.json <<'JSON'
{"result":{"process_info":{"foreground_process_group_id":null,"foreground_processes":[{"pid":1,"argv0":"nvim"},{"pid":2,"argv0":"bash"}]}}}
JSON
run preexec function shell
check 'ambiguous sample preserves label' '' "$(log)"
export HERDR_MOCK_FAIL_VERB='pane process-info'
run preexec function shell
check 'failed sample preserves label' '' "$(log)"
cleanup
setup
fixture pane_launch.json <<'JSON'
{"result":{"pane":{"pane_id":"current","terminal_id":"terminal","label":"server logs","tab_id":"t1"}}}
JSON
run preexec nvim
check 'manual pane preserved' '' "$(log)"
check 'manual pane opted out' false "$(jq -r '.["pane:terminal"].enabled' "$STATE")"
fixture pane_launch.json <<'JSON'
{"result":{"pane":{"pane_id":"current","terminal_id":"terminal","label":"","tab_id":"t1"}}}
JSON
run preexec nvim
check 'manual pane clear resumes hooks' 'pane rename current nvim' "$(log)"
cleanup
setup
unset HERDR_PANE_ID
run preexec nvim
check 'missing launch identity does no pane work' '' "$(log)"
export HERDR_PANE_ID=launch
fixture pane_launch.json <<'JSON'
{"result":{"pane":{"pane_id":"current","label":null}}}
JSON
run preexec nvim
check 'missing terminal identity does no pane work' '' "$(log)"
fixture pane_launch.json <<'JSON'
{}
JSON
run preexec nvim
check 'missing pane object does no pane work' '' "$(log)"
cleanup

t_summary
