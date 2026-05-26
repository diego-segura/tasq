# tasq

[![made-with-bash](https://img.shields.io/badge/Made%20with-Bash-1f425f.svg)](https://www.gnu.org/software/bash/)
[![GPLv3 license](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://github.com/navxio/tasq/blob/master/LICENSE)

A dead simple task manager that keeps your tasks in an **alphabetical** list
(handy when you label tasks by project) and lets you pin one to **focus** on
it, **one at a time**, without distractions

### Installation
Download [tasq.sh](https://raw.githubusercontent.com/navxio/tasq.sh/master/tasq.sh) and add it to your `$PATH`

### Where your tasks are stored

The first time you run tasq it asks where to keep your task list, suggesting a
sensible default. Pick a folder inside Dropbox/iCloud/Drive and your list syncs
across machines automatically. The chosen folder is remembered in
`~/.config/qo/config`.

To point tasq at a different folder later, run `tasq sync <folder>` (or just
`tasq sync` to be prompted). If that folder already has a task list, tasq adopts
it; if it's empty, you start fresh there. `tasq sync` only re-points where tasks
are read from and written to — it never moves or merges your existing files.

### Usage

Run `./tasq.sh` to print the task you should be focusing on — the one you've
pinned, or the first alphabetically if you haven't pinned anything.

Tasks are always shown in alphabetical (case-insensitive) order, so tasks that
share a project label group together. The one exception is your focused task,
which is pinned to the top until it's done.

Flags

`-h, --help` print help text

`-a, --add "task"` adds a task to the list

`-x, --mark-done` marks the focused task (or the first alphabetically) as done and removes it

`-f, --focus` opens an interactive picker. Navigate with the arrow keys (a `>` marks the current row) or type a task's number, then:
  - **enter** to focus it — it gets pinned to the top of the list
  - **x** to mark the highlighted task done
  - **q** or **esc** to cancel

`sync [folder]` store your task list in a different folder (see *Where your tasks are stored* above)
