# tasq

[![made-with-bash](https://img.shields.io/badge/Made%20with-Bash-1f425f.svg)](https://www.gnu.org/software/bash/)
[![GPLv3 license](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://github.com/navxio/tasq/blob/master/LICENSE)

A dead simple task manager that arranges your tasks in a queue
so you could focus on them **one at a time**, without distractions

### Installation
Download [tasq.sh](https://raw.githubusercontent.com/navxio/tasq.sh/master/tasq.sh) and add it to your `$PATH`

### Usage

Run `./tasq.sh` to print out the latest task to the console

Flags

`-h, --help` print help text

`-a, --add "task"` adds a task to the *end* of the queue

`-x, --mark-done` marks the latest task as done and removes it from the queue

`-f, --focus` shows a numbered list and lets you pick a task to focus on — navigate with the arrow keys (a `>` marks the current row) or just type its number, then press enter. The chosen task moves to the top of the queue
