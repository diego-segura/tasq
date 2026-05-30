# tasq

[![made-with-bash](https://img.shields.io/badge/Made%20with-Bash-1f425f.svg)](https://www.gnu.org/software/bash/)
[![GPLv3 license](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://github.com/diego-segura/tasq/blob/master/LICENSE)

A dead-simple terminal task manager. Tasks live in an alphabetical list (handy when you label them by project), with one pinned to the top as your **focus**.

Forked from [navxio/tasq.sh](https://github.com/navxio/tasq.sh).

### Install

Download [`tasq.sh`](https://raw.githubusercontent.com/diego-segura/tasq/master/tasq.sh), `chmod +x` it, and put it on your `$PATH` (rename to `tasq` if you like).

### Storage

First run prompts you for a folder. Pick one inside Dropbox / iCloud / Drive to sync across machines. The choice is saved in `~/.config/qo/config`. Re-point later with `tasq sync <folder>`.

### Usage

`tasq` opens the interactive picker:

| key | action |
|---|---|
| `↑` `↓` / `j` `k` | move 1 |
| `⇧J` `⇧K` | jump 5 |
| `f` or `Enter` | focus selected (pins to top, exits) |
| `a` | add a task inline |
| `e` | edit selected inline (Enter saves, Esc cancels) |
| `x` | mark selected done / delete |
| `q` or `Esc` | quit |

One-shot flags (skip the picker):

- `tasq -a "task"` — add a task
- `tasq -x` — mark the focused task done
- `tasq sync [folder]` — change storage folder
- `tasq -h` — help

Tasks always sort alphabetically (case-insensitive), so anything you prefix with a project label groups together. The focused task is the one exception — it pins to the top until done.
