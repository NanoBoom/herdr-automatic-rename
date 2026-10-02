# herdr-automatic-rename

[![tests](https://github.com/nanoboom/herdr-automatic-rename/actions/workflows/ci.yml/badge.svg)](https://github.com/nanoboom/herdr-automatic-rename/actions/workflows/ci.yml) [![release](https://img.shields.io/github/v/release/nanoboom/herdr-automatic-rename)](https://github.com/nanoboom/herdr-automatic-rename/releases) [![herdr](https://img.shields.io/badge/dynamic/toml?url=https%3A%2F%2Fraw.githubusercontent.com%2Fnanoboom%2Fherdr-automatic-rename%2Fmain%2Fherdr-plugin.toml&query=%24.min_herdr_version&prefix=%3E%3D%20&label=herdr)](https://github.com/qu8n/herdr) [![license](https://img.shields.io/github/license/nanoboom/herdr-automatic-rename)](LICENSE)

## Features

### Before

By default, herdr names new tabs with plain numbers. It's difficult to know what's going on in a tab, especially when you have multiple tabs/agents running across different workspaces.

`    1    `‎‎‎‎ ‎ ‎ `    2    ` ‎ ‎ ‎‎‎`    3    `‎‎‎ ‎ ‎ +

### After

This plugin names panes after their current program, prompt shell, or agent task, and a tab after its project directory. Moving into a subdirectory keeps that name. Outside a project, the tab follows the current folder:

`  [1] api  `‎‎‎ ‎ ‎ `  [2] website  ` ‎ ‎ ‎‎‎`  [3] works  `‎‎‎ ‎ ‎ +

The label uses only the final folder name, plus the existing jump-key number when tab numbering is enabled. Set `TAB_NAME_DIRECTORY_ONLY=0` to restore the older program, branch, and agent-title labels. See the Configuration section below for more options.

## Quick start

### Requirements

- herdr `>= 0.7.1`
- `jq`
- bash
- Linux or macOS

### Install or update

```sh
curl -fsSL https://raw.githubusercontent.com/nanoboom/herdr-automatic-rename/main/install.sh | bash
```

This script installs the latest version of the plugin and adds our shell hook, which makes the renaming mechanism happen immediately when a command starts. It picks the hook for your login shell out of zsh, bash, and fish, and writes it to that shell's startup file.

<details>
<summary>Alternative, manual setup instructions</summary>

#### 1. Install the plugin

```sh
herdr plugin install nanoboom/herdr-automatic-rename --yes
```

#### 2. Add the hook for your shell

This hook makes the renaming mechanism happen immediately when a command starts. To figure out what your shell is, run `echo $SHELL`.

##### zsh

```zsh
# ~/.zshrc
for _f in ${HOME}/.config/herdr/plugins/github/herdr-automatic-rename-*/shell/hook.zsh(N); do
  source $_f; break
done
```

##### bash

```bash
# ~/.bashrc
for _f in "$HOME"/.config/herdr/plugins/github/herdr-automatic-rename-*/shell/hook.bash; do
  [ -r "$_f" ] && { source "$_f"; break; }
done
```

##### fish

```fish
# ~/.config/fish/config.fish
for _f in $HOME/.config/herdr/plugins/github/herdr-automatic-rename-*/shell/hook.fish
    test -r "$_f"; and source "$_f"; and break
end
```

</details>

### Recommended herdr configs

**1. Turn off herdr's new-tab name prompt.**

```toml
# ~/.config/herdr/config.toml
[ui]
prompt_new_tab_name = false
```

When you create a new tab, herdr prompts you to give it a name. Custom tab names are respected by this plugin. For the best UX, disable this feature to let the plugin do the naming for you by default.

**2. For combined labels, install herdr integrations for your coding agents.**

See [herdr's integrations docs](https://herdr.dev/docs/integrations/) for installation details. These help agent-title naming when `TAB_NAME_DIRECTORY_ONLY=0`.

## Configuration (optional)

To customize, create your config file at `~/.config/herdr-automatic-rename/config.sh` (or point `HERDR_AUTOMATIC_RENAME_CONFIG` elsewhere). See [config.example.sh](config.example.sh) for the full configuration details. Every setting has a default, so you only need to set what you'd like to change.

## Actions

- **reset**: When you manually name a tab, the plugin respects that name and doesn't touch it. This action lets the plugin take over renaming that tab.

- **doctor**: This action prints why the plugin named the current tab the way it did for troubleshooting purposes.

To invoke an action, either run it from the CLI:

```sh
herdr plugin action invoke herdr-automatic-rename.reset
```

Or bind it in `config.toml` as a `plugin_action`, like this:

```toml
[[keys.command]]
key = "prefix+a" # a for "automatic"
type = "plugin_action"
command = "herdr-automatic-rename.reset"
description = "hand this tab's name back to automatic naming"
```

## Caveats

- Prefix numbering stops at 9 since herdr only allows keybindings up until that number.
- In combined-label mode, an untitled Claude Code tab can get its name from the session transcript on disk. Set `AGENT_TRANSCRIPT=0` in `config.sh` to stop that.
- Combined-label mode needs herdr's foreground process detection. Some Linux containers and sandboxes hide it; on herdr `>= 0.8.0`, set `HERDR_PROCESS_DETECTION=child-groups` in herdr's environment.
- Below herdr `0.7.4`, a new name only shows at the next redraw, such as a focus change.

## Pane activity labels

Each pane is named independently of its tab: `nvim` for an editor, `zsh`, `bash`, or `fish` at that shell's prompt, and `codex：添加pane自动命名功能` for an agent with a meaningful task. An agent without a task shows its detected name, such as `claude`. Split panes and panes in background tabs each resolve their own activity.

Pane naming defaults to `NAME_PANES=1`. Set `NAME_PANES=0` in `config.sh` to stop new pane renames and retain the existing labels. Tab settings for directory context, icons, aliases, arguments, ignored programs, and hidden shells do not change pane labels. `MAX_NAME_LEN` caps program labels; `MAX_TITLE_LEN` caps the task after the agent prefix. `AGENT_TITLES=0` keeps the detected agent name alone, and `AGENT_TRANSCRIPT=0` disables the optional Claude transcript fallback.

A label you set by hand, including a numeric label, is preserved. Editing an automatic pane label opts it out; `herdr pane rename <pane_id> --clear` resumes automatic naming at the next update. Ownership follows the terminal when its pane moves between tabs or workspaces.

The shell hooks give immediate command-start and prompt updates. Delivered agent status and pane lifecycle events reconcile every pane. Agent tasks come from meaningful terminal titles, then independently reported title metadata, then the optional Claude transcript. A title-only change waits for the next reconcile because herdr does not deliver a title-change plugin event. The doctor action includes pane decisions for the selected tab.

## Uninstall

The clear action restores number prefixes and removes unchanged plugin-owned pane labels while preserving manually edited pane labels. Run it before uninstalling:

```sh
bash "$(herdr plugin list --json \
  | jq -r '.result.plugins[]|select(.plugin_id=="herdr-automatic-rename").source.managed_path')/automatic-rename.sh" --clear
herdr plugin uninstall herdr-automatic-rename
```

Then delete `~/.local/state/herdr-automatic-rename/`.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## License

MIT.
