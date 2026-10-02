#!/usr/bin/env bash
# Pane reconciliation exercises every pane and terminal-owned manual labels.
set -o pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh"
ENGINE="$here/../automatic-rename.sh"
setup() {
  SB=$(mktemp -d "${TMPDIR:-/tmp}/hal-panes.XXXXXX")
  export HERDR_MOCK_DIR="$SB/fixtures" HERDR_MOCK_LOG="$SB/mutations"
  mkdir -p "$HERDR_MOCK_DIR"
  : >"$HERDR_MOCK_LOG"
  export HERDR_BIN_PATH="$here/mocks/herdr" XDG_STATE_HOME="$SB/state"
  export HERDR_AUTOMATIC_RENAME_CONFIG="$SB/config.sh" HERDR_SOCKET_PATH="$SB/herdr.sock"
  export NAME_PANES=1 NAME_TABS=0 AUTO_INDEX=0
  unset AUTO_INDEX_TABS AUTO_INDEX_WORKSPACES AUTO_INDEX_AGENTS HERDR_SESSION_NAME HERDR_SESSION
  unset HERDR_MOCK_FAIL_VERB HERDR_MOCK_FAIL_RENAME AGENT_TITLES AR_TRACE AR_TRACE_FILE
  unset HERDR_MOCK_STATE_DEST
  export CLAUDE_CONFIG_DIR="$SB/claude"
  STATE="$XDG_STATE_HOME/herdr-automatic-rename/state.json"
  mkdir -p "$(dirname "$STATE")"
  printf '{}\n' >"$STATE"
}
fixture() { cat >"$HERDR_MOCK_DIR/$1"; }
run() { /bin/bash "$ENGINE" "${1:-startup}"; }
log() { cat "$HERDR_MOCK_LOG"; }
state() { jq -r "$1" "$STATE"; }
cleanup() { rm -rf "$SB"; }
proc() {
  printf '{"result":{"process_info":{"foreground_process_group_id":1,"foreground_processes":[{"pid":1,"argv0":"%s"}]}}}' "$2" >"$HERDR_MOCK_DIR/procinfo_$1.json"
}
base_panes() {
  fixture panes.json <<'JSON'
{"result":{"panes":[
 {"pane_id":"p1","terminal_id":"term1","tab_id":"t1","label":null},
 {"pane_id":"p2","terminal_id":"term2","tab_id":"t1","label":""},
 {"pane_id":"p3","terminal_id":"term3","tab_id":"background","label":null},
 {"pane_id":"p4","terminal_id":"term4","tab_id":"background","agent":"codex","terminal_title_stripped":"✳ 添加pane自动命名功能","label":null},
 {"pane_id":"p5","terminal_id":"term5","tab_id":"background","agent":"claude","terminal_title":"Claude Code","label":null},
 {"pane_id":"p6","terminal_id":"term6","tab_id":"background","agent":"codex","terminal_title":"Codex","title":"修复构建","label":null}
]}}
JSON
  proc p1 -zsh; proc p2 /bin/bash; proc p3 /usr/bin/nvim
}
setup
base_panes
run
out=$(log)
check_contains 'list: idle zsh' "$out" 'pane rename p1 zsh'
check_contains 'list: actual bash despite login shell' "$out" 'pane rename p2 bash'
check_contains 'list: background editor' "$out" 'pane rename p3 nvim'
check_contains 'list: Chinese agent' "$out" 'pane rename p4 codex：添加pane自动命名功能'
check_contains 'list: startup title yields agent alone' "$out" 'pane rename p5 claude'
check_contains 'list: independent metadata title fallback' "$out" 'pane rename p6 codex：修复构建'
check 'agent task bypasses sampling' $'p1\np2\np3' "$(cat "$HERDR_MOCK_LOG.procinfo")"
check 'terminal identity owns label' zsh "$(state '.["pane:term1"].auto')"
# Mimic the successful CLI labels for an idempotent pass.
jq --slurpfile s "$STATE" '.result.panes |= map(.label = $s[0]["pane:" + .terminal_id].auto)' "$HERDR_MOCK_DIR/panes.json" >"$SB/new.json"
mv "$SB/new.json" "$HERDR_MOCK_DIR/panes.json"
: >"$HERDR_MOCK_LOG"; run
check 'repeated pass performs no rename' '' "$(log)"
# Same terminal moves to a new pane ID and remains managed.
jq '.result.panes[0].pane_id = "moved"' "$HERDR_MOCK_DIR/panes.json" >"$SB/new.json"
mv "$SB/new.json" "$HERDR_MOCK_DIR/panes.json"
proc moved /usr/bin/nvim
run
check_contains 'terminal ownership follows move' "$(log)" 'pane rename moved nvim'
cleanup

setup
base_panes
jq '.result.panes[0].label="server logs" | .result.panes[1].label="7"' "$HERDR_MOCK_DIR/panes.json" >"$SB/new.json"
mv "$SB/new.json" "$HERDR_MOCK_DIR/panes.json"
run
check_absent 'first manual label preserved' "$(log)" 'pane rename p1'
check_absent 'first numeric label preserved' "$(log)" 'pane rename p2'
check 'numeric manual ownership disabled' false "$(state '.["pane:term2"].enabled')"
jq '.result.panes[0].label=""' "$HERDR_MOCK_DIR/panes.json" >"$SB/new.json"
mv "$SB/new.json" "$HERDR_MOCK_DIR/panes.json"
: >"$HERDR_MOCK_LOG"; run
check_contains 'clearing manual label re-adopts' "$(log)" 'pane rename p1 zsh'
printf '{"pane:term1":{"auto":"zsh","enabled":true}}' >"$STATE"
jq '.result.panes = [.result.panes[0] | .label="9" | .pane_id="moved"]' "$HERDR_MOCK_DIR/panes.json" >"$SB/new.json"
mv "$SB/new.json" "$HERDR_MOCK_DIR/panes.json"
: >"$HERDR_MOCK_LOG"; run
check 'manual edit after move prevents rename' '' "$(log)"
check 'manual edit opts out' false "$(state '.["pane:term1"].enabled')"
cleanup

setup
base_panes
jq '.result.panes |= .[:1]' "$HERDR_MOCK_DIR/panes.json" >"$SB/new.json"; mv "$SB/new.json" "$HERDR_MOCK_DIR/panes.json"
printf '{"tab":{"auto":"project","enabled":true},"ws:w1":{"auto":"project","enabled":true},"pane:closed":{"auto":"zsh","enabled":true}}' >"$STATE"
run
check 'pane prune preserves tab' project "$(state '.tab.auto')"
check 'pane prune preserves workspace' project "$(state '.["ws:w1"].auto')"
check 'complete nonempty list prunes closed terminal' null "$(state '.["pane:closed"]')"
printf '{"pane:closed":{"auto":"zsh","enabled":true}}' >"$STATE"
export HERDR_MOCK_FAIL_VERB='pane list'
: >"$HERDR_MOCK_LOG"; run
check 'failed pane read renames nothing' '' "$(log)"
check 'failed pane read prunes nothing' zsh "$(state '.["pane:closed"].auto')"
unset HERDR_MOCK_FAIL_VERB
fixture panes.json <<'JSON'
{"result":{"panes":{}}}
JSON
run
check 'malformed read prunes nothing' zsh "$(state '.["pane:closed"].auto')"
base_panes
export HERDR_MOCK_FAIL_RENAME=1
run
check 'failed rename never claims' null "$(state '.["pane:term1"]')"
unset HERDR_MOCK_FAIL_RENAME
export HERDR_MOCK_FAIL_VERB='pane process-info'
: >"$HERDR_MOCK_LOG"; run
check_absent 'process failure does not invent shell' "$(log)" 'pane rename p1'
unset HERDR_MOCK_FAIL_VERB
# Fail only the state writer's mv, keeping queries and the session lock working.
mkdir "$SB/bin"
cat >"$SB/bin/mv" <<'MOCK'
#!/bin/bash
[ "$2" = "$HERDR_MOCK_STATE_DEST" ] && exit 1
exec /bin/mv "$@"
MOCK
chmod +x "$SB/bin/mv"
export HERDR_MOCK_STATE_DEST="$STATE" AR_TRACE=1 AR_TRACE_FILE="$SB/trace"
PATH="$SB/bin:$PATH" run
check 'failed state write never claims renamed pane' null "$(state '.["pane:term1"]')"
check_contains 'failed state write traced' "$(cat "$AR_TRACE_FILE")" 'ownership state write failed'
# Fail the state's read separately: unreadable is unknown, never a new store.
cat >"$SB/bin/cat" <<'MOCK'
#!/bin/bash
[ "$1" = "$HERDR_MOCK_STATE_DEST" ] && exit 1
exec /bin/cat "$@"
MOCK
chmod +x "$SB/bin/cat"
: >"$HERDR_MOCK_LOG"
PATH="$SB/bin:$PATH" run
check 'unreadable state causes no pane mutation' '' "$(log)"
check_contains 'unreadable state traced' "$(cat "$AR_TRACE_FILE")" 'state unreadable: left alone' 
cleanup

setup
base_panes
jq -n --slurpfile p "$HERDR_MOCK_DIR/panes.json" '{result:{snapshot:{workspaces:[],tabs:[],agents:[],panes:$p[0].result.panes}}}' >"$HERDR_MOCK_DIR/snapshot.json"
export HERDR_MOCK_FAIL_VERB='pane list'
run
check_contains 'snapshot names background panes without pane list' "$(log)" 'pane rename p3 nvim'
cleanup

setup
fixture panes.json <<'JSON'
{"result":{"panes":[{"pane_id":"p1","terminal_id":"term1","tab_id":"t1","label":"zsh"},{"pane_id":"p2","terminal_id":"term2","label":"custom"}]}}
JSON
printf '{"pane:term1":{"auto":"zsh","enabled":true},"pane:term2":{"auto":"bash","enabled":true}}' >"$STATE"
export NAME_PANES=0
run
check 'toggle off issues no pane mutation' '' "$(log)"
run --clear
check_contains 'clear works when toggle off' "$(log)" 'pane rename p1 --clear'
check_absent 'clear protects manual edit' "$(log)" 'pane rename p2'
check 'clear removes owned record' null "$(state '.["pane:term1"]')"
check 'clear retains manual edited record' bash "$(state '.["pane:term2"].auto')"
printf '{"pane:term1":{"auto":"zsh","enabled":true}}' >"$STATE"
export HERDR_MOCK_FAIL_RENAME=1
run --clear
check 'failed clear retains record' zsh "$(state '.["pane:term1"].auto')"
check_contains 'failed clear reported accurately' "$(log)" 'Clear incomplete'
unset HERDR_MOCK_FAIL_RENAME
export HERDR_MOCK_FAIL_VERB='pane list'
: >"$HERDR_MOCK_LOG"; run --clear
check_contains 'failed pane read makes clear incomplete' "$(log)" 'Clear incomplete'
cleanup

setup
base_panes
export HERDR_TAB_ID=background
out=$(run doctor)
check_contains 'doctor includes pane toggle' "$out" 'NAME_PANES=1'
check_contains 'doctor shows actual pane decisions for tab' "$out" 'pane:term4'
check_contains 'doctor shows task source' "$out" '添加pane自动命名功能'
cleanup

setup
fixture panes.json <<'JSON'
{"result":{"panes":[{"pane_id":"p1","terminal_id":"term1","agent":"claude","terminal_title":"Claude Code","cwd":"/work","agent_session":{"value":"11111111-1111-1111-1111-111111111111"}}]}}
JSON
mkdir -p "$CLAUDE_CONFIG_DIR/projects/-work"
printf '{"type":"ai-title","aiTitle":"修复回归测试"}\n' >"$CLAUDE_CONFIG_DIR/projects/-work/11111111-1111-1111-1111-111111111111.jsonl"
run
check 'Claude transcript supplies pane task' 'pane rename p1 claude：修复回归测试' "$(log)"
export AGENT_TRANSCRIPT=0
: >"$HERDR_MOCK_LOG"; run
check 'transcript toggle yields agent alone' 'pane rename p1 claude' "$(log)"
unset AGENT_TRANSCRIPT
cleanup

setup
printf '{"pane:closed":{"auto":"zsh","enabled":true}}' >"$STATE"
fixture panes.json <<'JSON'
{"result":{"panes":[{"pane_id":"p1","terminal_id":"term1"},{"pane_id":"p2"}]}}
JSON
proc p1 -zsh
run
check_absent 'missing terminal is never renamed' "$(log)" 'pane rename p2'
check 'missing terminal makes read partial for pruning' zsh "$(state '.["pane:closed"].auto')"
fixture panes.json <<'JSON'
{"result":{"panes":[]}}
JSON
run
check 'empty list conservatively retains state' zsh "$(state '.["pane:closed"].auto')"
cleanup

t_summary
