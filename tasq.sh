#!/bin/bash

qo_home="${XDG_DATA_HOME:-$HOME/.local/share}/qo"
mkdir -p "$qo_home"

tasks_store="$qo_home/tasks.txt"
focus_store="$qo_home/focus.txt"

[ ! -f "$tasks_store" ] && touch "$tasks_store"

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
    sort -f "$tasks_store" | head -n 1
  fi
}

## all tasks in display order: pinned first (if any), then the rest alphabetically
display_tasks() {
  local pin
  pin=$(pinned_task)
  if [[ -n "$pin" ]]; then
    printf '%s\n' "$pin"
    grep -vxF -- "$pin" "$tasks_store" | sort -f
  else
    sort -f "$tasks_store"
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

## interactive picker: focus a task (pin to top) or mark one done
focus_task() {
  local tasks=() line i sel=0 buf="" key seq val msg="" removed term_lines prev_n=0 rendered=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    tasks+=("$line")
  done < <(display_tasks)

  local n=${#tasks[@]}
  if [[ "$n" -eq 0 ]]; then
    echo "no tasks yet — add one with: tasq -a \"your task\""
    return 0
  fi

  term_lines=$(tput lines 2>/dev/null || echo 24)

  ## fallback for pipes / lists taller than the screen: plain numbered prompt (focus only)
  if [[ ! -t 0 || ! -t 1 || $((n + 3)) -gt "$term_lines" ]]; then
    echo "which one to focus on?"
    for i in "${!tasks[@]}"; do
      printf '%2d) %s\n' "$((i + 1))" "${tasks[$i]}"
    done
    printf 'number: '
    read -r val
    if ! [[ "$val" =~ ^[0-9]+$ ]] || [[ "$val" -lt 1 || "$val" -gt "$n" ]]; then
      echo "not a valid task number" >&2
      return 1
    fi
    printf '%s\n' "${tasks[$((val - 1))]}" > "$focus_store"
    printf "ok, let's focus on \"\033[1m%s\033[0m\"\n" "${tasks[$((val - 1))]}"
    return 0
  fi

  printf '\033[?25l'                                  # hide cursor
  trap 'printf "\033[?25h\n"; exit 130' INT

  while true; do
    if [[ "$rendered" -eq 1 ]]; then
      printf '\r\033[%dA\033[J' "$((prev_n + 1))"     # back to header, wipe the block
    fi
    rendered=1
    printf 'which one to focus on?\n'
    for i in "${!tasks[@]}"; do
      if [[ "$i" -eq "$sel" ]]; then
        printf '\033[1m> %2d) %s\033[0m\n' "$((i + 1))" "${tasks[$i]}"
      else
        printf '  %2d) %s\n' "$((i + 1))" "${tasks[$i]}"
      fi
    done
    printf '\033[2m%s↑/↓ + Enter focus · x done · q cancel%s\033[0m' "${msg:+$msg — }" "${buf:+  [$buf]}"
    prev_n=$n

    IFS= read -rsn1 key
    case "$key" in
      $'\033')
        IFS= read -rsn2 -t 1 seq
        case "$seq" in
          '[A') sel=$(( (sel - 1 + n) % n )); buf=""; msg="" ;;
          '[B') sel=$(( (sel + 1) % n )); buf=""; msg="" ;;
          '')   trap - INT; printf '\r\033[%dA\033[J\033[?25h' "$((n + 1))"; echo "ok, no change"; return 0 ;;
        esac
        ;;
      [0-9])
        buf="$buf$key"; msg=""
        val=$((10#$buf)); [[ "$val" -ge 1 && "$val" -le "$n" ]] && sel=$((val - 1))
        ;;
      $'\177'|$'\b')
        buf="${buf%?}"
        if [[ -n "$buf" ]]; then val=$((10#$buf)); [[ "$val" -ge 1 && "$val" -le "$n" ]] && sel=$((val - 1)); fi
        ;;
      x|X)
        removed="${tasks[$sel]}"
        remove_task "$removed"
        tasks=()
        while IFS= read -r line || [[ -n "$line" ]]; do tasks+=("$line"); done < <(display_tasks)
        n=${#tasks[@]}
        if [[ "$n" -eq 0 ]]; then
          trap - INT; printf '\r\033[%dA\033[J\033[?25h' "$((prev_n + 1))"
          printf "done: \"%s\" — all clear, no tasks left\n" "$removed"
          return 0
        fi
        [[ "$sel" -ge "$n" ]] && sel=$((n - 1))
        buf=""; msg="done: $removed"
        ;;
      q|Q)
        trap - INT; printf '\r\033[%dA\033[J\033[?25h' "$((n + 1))"; echo "ok, no change"; return 0 ;;
      ''|$'\n'|$'\r')
        if [[ -n "$buf" ]]; then
          val=$((10#$buf))
          if [[ "$val" -ge 1 && "$val" -le "$n" ]]; then sel=$((val - 1)); break; else buf=""; msg="no task #$val"; fi
        else
          break
        fi
        ;;
    esac
  done

  trap - INT
  printf '\r\033[%dA\033[J\033[?25h' "$((n + 1))"     # wipe picker, restore cursor

  printf '%s\n' "${tasks[$sel]}" > "$focus_store"
  printf "ok, let's focus on \"\033[1m%s\033[0m\"\n" "${tasks[$sel]}"
}

## with no args, print the task you should be focusing on
[[ "$#" -eq 0 ]] && current_task

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
    -f|--focus) focus_task || exit $? ;;
    -h|--help) printf "tasq: a simple task manager (tasks shown alphabetically; focus pins one to the top)\nUsage\n-a, --add <task text> to add a new task\n-x, --mark-done to mark the focused task (or the first alphabetically) as done\n-f, --focus to pick a task: arrows or type its number, Enter to focus, x to mark done, q to cancel\n" ;;
    *) printf "Unknown parameter passed: $1\nUse -h to print help text\n"; exit 1;;
  esac
  shift
done
