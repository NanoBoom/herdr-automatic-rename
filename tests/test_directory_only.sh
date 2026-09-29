#!/usr/bin/env bash
# The default tab label is exactly one project or current-directory name.

set -o pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh"

ENGINE="$here/../automatic-rename.sh"
MOCK="$here/mocks/herdr"
SB=$(mktemp -d "${TMPDIR:-/tmp}/hal-dironly.XXXXXX")
export HERDR_MOCK_DIR="$SB/fixtures"; mkdir -p "$HERDR_MOCK_DIR"
export HERDR_MOCK_LOG="$SB/renames.log"; : >"$HERDR_MOCK_LOG"
export HERDR_BIN_PATH="$MOCK" XDG_STATE_HOME="$SB/state"
export HERDR_AUTOMATIC_RENAME_CONFIG="$SB/none.sh"
export HERDR_SOCKET_PATH="$SB/herdr.sock"
export NAME_TABS=1 AUTO_INDEX=0 TAB_CONTEXT=0 HIDE_SHELL=1
unset TAB_NAME_DIRECTORY_ONLY

mkdir -p "$SB/dev/checkout/.git" "$SB/dev/checkout/src/deep" \
  "$SB/dev/marker/lib/deep" "$SB/plain/first" "$SB/plain/second" \
  "$SB/plain/verylongfoldernamehere"
: >"$SB/dev/checkout/src/package.json"
: >"$SB/dev/marker/package.json"
: >"$SB/dev/marker/lib/pyproject.toml"

snapshot() { # <pane cwd> <tab label>
  cat >"$HERDR_MOCK_DIR/snapshot.json" <<JSON
{"result":{"snapshot":{
  "workspaces":[{"workspace_id":"w1","label":"other"}],
  "tabs":[{"tab_id":"w1:t1","label":"$2","pane_count":1,"focused":true,"workspace_id":"w1"}],
  "panes":[{"pane_id":"p1","tab_id":"w1:t1","focused":true,"cwd":"$1",
    "agent":"claude","terminal_title_stripped":"Fix the build"}],
  "layouts":[{"tab_id":"w1:t1","focused_pane_id":"p1"}]
}}}
JSON
}
run_event() { /usr/bin/env bash "$ENGINE" pane.focused; }
log() { cat "$HERDR_MOCK_LOG"; }
clear_log() { : >"$HERDR_MOCK_LOG"; }

# There is deliberately no process-info fixture. Neither a program nor an agent
# title is needed to name a tab after its directory.
snapshot "$SB/dev/checkout" 1
run_event
check "Git checkout names the whole tab" "tab rename w1:t1 checkout" "$(log)"
clear_log
snapshot "$SB/dev/checkout/src/deep" checkout
run_event
check "entering a Git subdirectory leaves the label alone" "" "$(log)"

snapshot "$SB/dev/marker/lib/deep" checkout
run_event
check "manifest-only project names the whole tab" "tab rename w1:t1 marker" "$(log)"
clear_log
snapshot "$SB/dev/marker/lib" marker
run_event
check "nested manifest leaves the project label alone" "" "$(log)"

snapshot "$SB/plain/first" marker
run_event
check "plain directory uses its own final component" "tab rename w1:t1 first" "$(log)"
clear_log
snapshot "$SB/plain/second" first
run_event
check "another plain directory changes the label" "tab rename w1:t1 second" "$(log)"

clear_log
snapshot "$SB/plain/verylongfoldernamehere" second
run_event
check "the full final folder name is kept" \
  "tab rename w1:t1 verylongfoldernamehere" "$(log)"
clear_log
snapshot / verylongfoldernamehere
run_event
check "filesystem root uses its own name" "tab rename w1:t1 /" "$(log)"

# A working agent in a split pane must not override the folder of the pane the
# user is looking at when the label is directory-only.
clear_log
cat >"$HERDR_MOCK_DIR/snapshot.json" <<JSON
{"result":{"snapshot":{
  "workspaces":[{"workspace_id":"w1","label":"other"}],
  "tabs":[{"tab_id":"w1:t1","label":"/","pane_count":2,"focused":true,"workspace_id":"w1"}],
  "panes":[
    {"pane_id":"p1","tab_id":"w1:t1","focused":true,"cwd":"$SB/plain/first"},
    {"pane_id":"p2","tab_id":"w1:t1","focused":false,"cwd":"$SB/dev/checkout",
      "agent":"claude","agent_status":"working"}],
  "layouts":[{"tab_id":"w1:t1","focused_pane_id":"p1"}]
}}}
JSON
run_event
check "a split tab uses its focused pane's directory" "tab rename w1:t1 first" "$(log)"

clear_log
export AUTO_INDEX=1 AUTO_INDEX_WORKSPACES=0 AUTO_INDEX_AGENTS=0
snapshot "$SB/dev/checkout" first
run_event
check "tab numbering stays in front of the project name" \
  "tab rename w1:t1 [1] checkout" "$(log)"
export AUTO_INDEX=0
unset AUTO_INDEX_WORKSPACES AUTO_INDEX_AGENTS

# The prompt hook and the event pass must agree. Preexec no longer samples a
# foreground process or appends the command name, including for ssh.
export HERDR_TAB_ID=t1 HERDR_PANE_ID=p1
mkdir -p "$XDG_STATE_HOME/herdr-automatic-rename"
printf '{"t1":{"auto":"checkout › nvim","enabled":true,"ws":"other"}}\n' \
  >"$XDG_STATE_HOME/herdr-automatic-rename/state.json"
cat >"$HERDR_MOCK_DIR/tab_t1.json" <<'JSON'
{"result":{"tab":{"tab_id":"t1","label":"checkout › nvim"}}}
JSON
clear_log
( cd "$SB/dev/checkout/src/deep" && /usr/bin/env bash "$ENGINE" preexec 'ssh prod-01' shell )
check "preexec replaces an owned combined label" "tab rename t1 checkout" "$(log)"
cat >"$HERDR_MOCK_DIR/tab_t1.json" <<'JSON'
{"result":{"tab":{"tab_id":"t1","label":"checkout"}}}
JSON
clear_log
( cd "$SB/dev/checkout/src/deep" && /usr/bin/env bash "$ENGINE" precmd zsh )
check "precmd leaves the project label alone" "" "$(log)"
clear_log
( cd "$SB/plain/first" && /usr/bin/env bash "$ENGINE" precmd zsh )
check "precmd follows a plain directory" "tab rename t1 first" "$(log)"
cat >"$HERDR_MOCK_DIR/tab_t1.json" <<'JSON'
{"result":{"tab":{"tab_id":"t1","label":"first"}}}
JSON
clear_log
( cd "$SB/plain/second" && /usr/bin/env bash "$ENGINE" precmd zsh )
check "precmd follows the next plain directory" "tab rename t1 second" "$(log)"
cat >"$HERDR_MOCK_DIR/tab_t1.json" <<'JSON'
{"result":{"tab":{"tab_id":"t1","label":"my tab"}}}
JSON
clear_log
( cd "$SB/plain/first" && /usr/bin/env bash "$ENGINE" precmd zsh )
check "a manual tab name still opts out" "" "$(log)"
check "the manual opt-out is recorded" "false" \
  "$(jq -r '.t1.enabled' "$XDG_STATE_HOME/herdr-automatic-rename/state.json")"

rm -rf "$SB"
t_summary
