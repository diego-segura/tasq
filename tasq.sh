#!/bin/bash

config_home="${XDG_CONFIG_HOME:-$HOME/.config}/qo"
config_file="$config_home/config"

print_help() {
  printf "tasq: a simple task manager (tasks shown alphabetically; focus pins one to the top)\n"
  printf "Usage\n"
  printf "  tasq                 open the picker: ↑/↓ or j/k (⇧J/⇧K jump 5), a add, e edit, f focus, x done/delete, q quit\n"
  printf "  -a, --add <text>     add a new task without opening the picker\n"
  printf "  -x, --mark-done      mark the focused task (or the first alphabetically) as done\n"
  printf "  sync [folder]        store your task list in a different folder (e.g. a synced cloud folder)\n"
  printf "  -h, --help           print this help text\n"
}

## expand a leading ~ to \$HOME
expand_path() {
  printf '%s' "${1/#\~/$HOME}"
}

save_config() {
  mkdir -p "$config_home"
  printf '%s\n' "$1" > "$config_file"
}

## prompt for a storage folder the very first time tasq runs
first_run_setup() {
  local default_dir input
  default_dir="${XDG_DATA_HOME:-$HOME/.local/share}/qo"
  if [[ ! -t 0 || ! -t 1 ]]; then
    task_dir="$default_dir"                       # non-interactive: just use the default
  else
    echo "Welcome to tasq!"
    echo "Where should your task list be stored?"
    echo "Tip: pick a folder inside Dropbox/iCloud/Drive to sync across devices."
    printf 'Folder [%s]: ' "$default_dir"
    IFS= read -r input
    task_dir=$(expand_path "${input:-$default_dir}")
  fi
  mkdir -p "$task_dir" || { echo "tasq: could not create $task_dir" >&2; exit 1; }
  save_config "$task_dir"
  if [[ -t 1 ]]; then
    echo "Your tasks live in: $task_dir"
    echo "Add your first task with: tasq -a \"your task\""
  fi
}

## resolve the active task directory from config, running first-run setup if needed
ensure_task_dir() {
  [[ -f "$config_file" ]] && task_dir=$(head -n 1 "$config_file")
  [[ -z "$task_dir" ]] && first_run_setup
  task_dir=$(expand_path "$task_dir")
  mkdir -p "$task_dir"
}

## connect tasq to a (possibly different) folder; adopt its tasks if any, else start fresh
sync_cmd() {
  local target="$1" current="" input count
  [[ -f "$config_file" ]] && current=$(head -n 1 "$config_file")

  if [[ -z "$target" ]]; then
    if [[ ! -t 0 || ! -t 1 ]]; then
      echo "tasq is storing tasks in: ${current:-(not set yet)}"
      echo "usage: tasq sync <folder>"
      return 0
    fi
    echo "tasq is currently storing tasks in: ${current:-(not set yet)}"
    printf 'Connect to which folder (blank to keep current): '
    IFS= read -r input
    [[ -z "$input" ]] && { echo "no change"; return 0; }
    target="$input"
  fi

  target=$(expand_path "$target")
  mkdir -p "$target" || { echo "tasq: could not access $target" >&2; return 1; }
  save_config "$target"

  if [[ -s "$target/tasks.txt" ]]; then
    count=$(grep -c '' "$target/tasks.txt")
    echo "Connected to $target — found $count task(s) already there."
  else
    [ ! -f "$target/tasks.txt" ] && touch "$target/tasks.txt"
    echo "Connected to $target — starting fresh."
  fi
}

## sort tasks alphabetically, but push tasks that start with an ISO date (YYYY-MM-DD)
## to the bottom — dated entries are future work and shouldn't dominate the top
sort_tasks() {
  awk '{
    if ($0 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) print "1\t" $0
    else print "0\t" $0
  }' | LC_ALL=C sort -f | cut -f2-
}

## the pinned/focused task, but only if it still exists in the store
pinned_task() {
  local pin=""
  [[ -f "$focus_store" ]] && pin=$(head -n 1 "$focus_store")
  if [[ -n "$pin" ]] && grep -qxF -- "$pin" "$tasks_store"; then
    printf '%s\n' "$pin"
  fi
}

## the task to focus on right now: the pinned one, else the first alphabetically
current_task() {
  local pin
  pin=$(pinned_task)
  if [[ -n "$pin" ]]; then
    printf '%s\n' "$pin"
  else
    sort_tasks < "$tasks_store" | head -n 1
  fi
}

## all tasks in display order: pinned first (if any), then the rest alphabetically
## (with ISO-date-prefixed tasks pushed to the bottom — see sort_tasks)
display_tasks() {
  local pin
  pin=$(pinned_task)
  if [[ -n "$pin" ]]; then
    printf '%s\n' "$pin"
    grep -vxF -- "$pin" "$tasks_store" | sort_tasks
  else
    sort_tasks < "$tasks_store"
  fi
}

## inline line editor (bash 3.2 compatible — read -e -i isn't available there).
## pre-seeds the buffer with $1, returns the result in REPLY, or empty if cancelled (Esc).
## supports: left/right arrows, Home/End, Backspace, Ctrl-U (clear), Enter (save), Esc (cancel).
edit_line() {
  local buf="$1" pos=${#1} key seq cancelled=0
  printf '\033[?25h'
  while true; do
    ## \r → col 1, \033[K → wipe to EOL, then prompt + buffer, then place cursor at 3+pos
    printf '\r\033[K\033[1m✎ \033[0m%s\r\033[%dC' "$buf" $((2 + pos))

    IFS= read -rsn1 key || { cancelled=1; break; }
    ## Enter often arrives as '' because newline is read's delimiter and gets stripped
    case "$key" in
      ''|$'\n'|$'\r') break ;;
      $'\033')
        IFS= read -rsn2 -t 1 seq
        case "$seq" in
          '[D') (( pos > 0 )) && pos=$((pos - 1)) ;;
          '[C') (( pos < ${#buf} )) && pos=$((pos + 1)) ;;
          '[H') pos=0 ;;
          '[F') pos=${#buf} ;;
          *)    cancelled=1; break ;;                             # bare Esc or unrecognized seq → cancel
        esac
        ;;
      $'\177'|$'\b')
        if (( pos > 0 )); then
          buf="${buf:0:pos-1}${buf:pos}"
          pos=$((pos - 1))
        fi
        ;;
      $'\025')                                                    # Ctrl-U: clear line
        buf=""; pos=0
        ;;
      *)
        buf="${buf:0:pos}${key}${buf:pos}"
        pos=$((pos + 1))
        ;;
    esac
  done
  printf '\033[?25l'
  if (( cancelled )); then REPLY=""; else REPLY="$buf"; fi
}

## replace the first exact occurrence of a task with new text, preserving the pin if it matched
edit_task() {
  local old="$1" new="$2"
  TASK_OLD="$old" TASK_NEW="$new" awk '
    BEGIN { old = ENVIRON["TASK_OLD"]; new = ENVIRON["TASK_NEW"]; done = 0 }
    $0 == old && !done { print new; done = 1; next }
    { print }
  ' "$tasks_store" > "$tasks_store.tmp" && mv "$tasks_store.tmp" "$tasks_store"
  if [[ -f "$focus_store" && "$(head -n 1 "$focus_store")" == "$old" ]]; then
    printf '%s\n' "$new" > "$focus_store"
  fi
}

## remove the first exact occurrence of a task, clearing the pin if it matched
remove_task() {
  local t="$1"
  TASK_TO_REMOVE="$t" awk '
    BEGIN { target = ENVIRON["TASK_TO_REMOVE"]; gone = 0 }
    $0 == target && !gone { gone = 1; next }
    { print }
  ' "$tasks_store" > "$tasks_store.tmp" && mv "$tasks_store.tmp" "$tasks_store"
  if [[ -f "$focus_store" && "$(head -n 1 "$focus_store")" == "$t" ]]; then
    : > "$focus_store"
  fi
}

## interactive picker: arrows / j-k navigate; a add, f focus (exits), x done/delete, q quit
interactive_picker() {
  local tasks=() line i sel=0 top=0 key seq msg="" added removed t
  local term_lines visible_n show_n n

  while IFS= read -r line || [[ -n "$line" ]]; do tasks+=("$line"); done < <(display_tasks)
  n=${#tasks[@]}

  ## non-interactive: just print the list, no UI
  if [[ ! -t 0 || ! -t 1 ]]; then
    for line in "${tasks[@]}"; do printf '%s\n' "$line"; done
    return 0
  fi

  ## take over the terminal (alt screen) so we have the full height to render into
  printf '\033[?1049h\033[H\033[?25l'
  trap 'printf "\033[?25h\033[?1049l"; exit 130' INT

  while true; do
    ## re-read on each render so resizing the window adjusts the viewport;
    ## stty reads the actual tty size, tput/$LINES can be stale in tmux or some terminals
    term_lines=$(stty size </dev/tty 2>/dev/null | awk '{print $1}')
    [[ -z "$term_lines" || "$term_lines" -lt 5 ]] && term_lines=$(tput lines 2>/dev/null || echo 24)
    visible_n=$((term_lines - 2))
    [[ "$visible_n" -lt 1 ]] && visible_n=1

    if [[ "$n" -eq 0 ]]; then
      show_n=1
    else
      show_n=$visible_n
      [[ "$n" -lt "$show_n" ]] && show_n=$n
      [[ "$sel" -lt "$top" ]] && top=$sel
      [[ "$sel" -ge $((top + show_n)) ]] && top=$((sel - show_n + 1))
      [[ "$top" -lt 0 ]] && top=0
    fi

    printf '\033[H\033[J'                                         # home + clear screen

    if [[ "$n" -eq 0 ]]; then
      printf 'your tasks (none)\n'
      printf '\033[2m  (press a to add your first task)\033[0m\n'
    else
      printf 'your tasks (%d)\n' "$n"
      for ((i = top; i < top + show_n; i++)); do
        if [[ "$i" -eq "$sel" ]]; then
          printf '\033[1m> %s\033[0m\n' "${tasks[$i]}"
        else
          printf '  %s\n' "${tasks[$i]}"
        fi
      done
    fi
    printf '\033[2m↑/↓ or j/k · ⇧J/⇧K jump 5 · a add · e edit · f focus · x done/delete · q quit%s\033[0m' "${msg:+ — $msg}"

    IFS= read -rsn1 key
    case "$key" in
      $'\033')
        IFS= read -rsn2 -t 1 seq
        case "$seq" in
          '[A') if [[ "$n" -gt 0 ]]; then sel=$((sel - 1)); [[ "$sel" -lt 0 ]] && sel=0; fi; msg="" ;;
          '[B') if [[ "$n" -gt 0 ]]; then sel=$((sel + 1)); [[ "$sel" -ge "$n" ]] && sel=$((n - 1)); fi; msg="" ;;
          '')   trap - INT; printf '\033[?25h\033[?1049l'; return 0 ;;
        esac
        ;;
      j)
        if [[ "$n" -gt 0 ]]; then sel=$((sel + 1)); [[ "$sel" -ge "$n" ]] && sel=$((n - 1)); fi
        msg=""
        ;;
      k)
        if [[ "$n" -gt 0 ]]; then sel=$((sel - 1)); [[ "$sel" -lt 0 ]] && sel=0; fi
        msg=""
        ;;
      J)
        if [[ "$n" -gt 0 ]]; then sel=$((sel + 5)); [[ "$sel" -ge "$n" ]] && sel=$((n - 1)); fi
        msg=""
        ;;
      K)
        if [[ "$n" -gt 0 ]]; then sel=$((sel - 5)); [[ "$sel" -lt 0 ]] && sel=0; fi
        msg=""
        ;;
      a|A)
        ## clear screen, show cursor, prompt at the top
        printf '\033[H\033[J\033[?25h'
        trap - INT
        printf '\033[1m+ \033[0m'
        IFS= read -r added
        trap 'printf "\033[?25h\033[?1049l"; exit 130' INT
        printf '\033[?25l'
        if [[ -n "$added" ]]; then
          printf '%s\n' "$added" >> "$tasks_store"
          tasks=()
          while IFS= read -r line || [[ -n "$line" ]]; do tasks+=("$line"); done < <(display_tasks)
          n=${#tasks[@]}
          ## land the carat on the new task wherever it sorted to
          for ((i = 0; i < n; i++)); do
            if [[ "${tasks[$i]}" == "$added" ]]; then sel=$i; break; fi
          done
          msg="added"
        else
          msg="add cancelled"
        fi
        ;;
      e|E)
        if [[ "$n" -gt 0 ]]; then
          local original="${tasks[$sel]}" edited
          ## clear screen, then run an inline line editor pre-seeded with the task text
          printf '\033[H\033[J'
          trap - INT
          edit_line "$original"
          edited="$REPLY"
          trap 'printf "\033[?25h\033[?1049l"; exit 130' INT
          if [[ -z "$edited" ]]; then
            msg="edit cancelled"
          elif [[ "$edited" == "$original" ]]; then
            msg="no changes"
          else
            edit_task "$original" "$edited"
            tasks=()
            while IFS= read -r line || [[ -n "$line" ]]; do tasks+=("$line"); done < <(display_tasks)
            n=${#tasks[@]}
            ## land the carat on the edited task wherever it sorted to
            for ((i = 0; i < n; i++)); do
              if [[ "${tasks[$i]}" == "$edited" ]]; then sel=$i; break; fi
            done
            msg="edited"
          fi
        fi
        ;;
      f|F|$'\n'|$'\r')
        if [[ "$n" -gt 0 ]]; then
          t="${tasks[$sel]}"
          printf '%s\n' "$t" > "$focus_store"
          trap - INT
          printf '\033[?25h\033[?1049l'
          printf "ok, let's focus on \"\033[1m%s\033[0m\"\n" "$t"
          return 0
        fi
        ;;
      x|X)
        if [[ "$n" -gt 0 ]]; then
          removed="${tasks[$sel]}"
          remove_task "$removed"
          tasks=()
          while IFS= read -r line || [[ -n "$line" ]]; do tasks+=("$line"); done < <(display_tasks)
          n=${#tasks[@]}
          [[ "$sel" -ge "$n" ]] && sel=$((n - 1))
          [[ "$sel" -lt 0 ]] && sel=0
          msg="done: $removed"
        fi
        ;;
      q|Q)
        trap - INT
        printf '\033[?25h\033[?1049l'
        return 0
        ;;
    esac
  done
}

## --- main ---

## help and sync never trigger first-run setup
case "$1" in
  -h|--help) print_help; exit 0 ;;
  sync) shift; sync_cmd "$1"; exit $? ;;
esac

ensure_task_dir
tasks_store="$task_dir/tasks.txt"
focus_store="$task_dir/focus.txt"
[ ! -f "$tasks_store" ] && touch "$tasks_store"

## with no args, open the interactive picker
if [[ "$#" -eq 0 ]]; then
  interactive_picker
  exit $?
fi

while [[ "$#" -gt 0 ]]; do
  case $1 in
    -a|--add)
      if [[ -z "$2" ]]; then
        printf "error: -a/--add requires task text\n" >&2
        exit 1
      fi
      printf '%s\n' "$2" >> "$tasks_store"; echo "added: \"$2\""; shift ;;
    -x|--mark-done)
      t=$(current_task)
      if [[ -z "$t" ]]; then
        echo "no tasks to mark done"
      else
        echo "done: $t"; remove_task "$t"
      fi ;;
    -f|--focus) interactive_picker || exit $? ;;
    -h|--help) print_help ;;
    *) printf "Unknown parameter passed: $1\nUse -h to print help text\n"; exit 1;;
  esac
  shift
done
