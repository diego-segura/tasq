#!/bin/bash

qo_home="${XDG_DATA_HOME:-$HOME/.local/share}/qo"
mkdir -p "$qo_home"

tasks_store="$qo_home/tasks.txt"

[ ! -f "$tasks_store" ] && touch "$tasks_store"

## interactive picker: choose a task to focus on; moves it to the top
focus_task() {
  local tasks=() line i sel=0 buf="" key seq num val term_lines

  while IFS= read -r line || [[ -n "$line" ]]; do
    tasks+=("$line")
  done < "$tasks_store"

  local n=${#tasks[@]}
  if [[ "$n" -eq 0 ]]; then
    echo "no tasks yet — add one with: tasq -a \"your task\""
    return 0
  fi

  term_lines=$(tput lines 2>/dev/null || echo 24)

  ## fallback for pipes or lists taller than the screen: plain numbered prompt
  if [[ ! -t 0 || ! -t 1 || $((n + 2)) -gt "$term_lines" ]]; then
    echo "which one to focus on?"
    for i in "${!tasks[@]}"; do
      printf '%2d) %s\n' "$((i + 1))" "${tasks[$i]}"
    done
    printf 'number: '
    read -r num
    if ! [[ "$num" =~ ^[0-9]+$ ]] || [[ "$num" -lt 1 || "$num" -gt "$n" ]]; then
      echo "not a valid task number" >&2
      return 1
    fi
    sel=$((num - 1))
  else
    ## interactive arrow-key picker
    printf 'which one to focus on?\n'
    printf '\033[?25l'                       # hide cursor
    trap 'printf "\033[?25h\n"; exit 130' INT

    local rendered=0
    while true; do
      if [[ "$rendered" -eq 1 ]]; then
        printf '\r\033[%dA' "$n"            # jump back to the first list row
      fi
      rendered=1
      for i in "${!tasks[@]}"; do
        printf '\033[K'
        if [[ "$i" -eq "$sel" ]]; then
          printf '\033[1m> %2d) %s\033[0m\n' "$((i + 1))" "${tasks[$i]}"
        else
          printf '  %2d) %s\n' "$((i + 1))" "${tasks[$i]}"
        fi
      done
      printf '\033[K\033[2muse ↑/↓ + Enter, or type a number + Enter — q to cancel%s\033[0m' "${buf:+  [$buf]}"

      IFS= read -rsn1 key
      case "$key" in
        $'\033')
          IFS= read -rsn2 -t 1 seq
          case "$seq" in
            '[A') sel=$(( (sel - 1 + n) % n )); buf="" ;;
            '[B') sel=$(( (sel + 1) % n )); buf="" ;;
            '')   trap - INT; printf '\r\033[%dA\033[J\033[?25h' "$((n + 1))"; echo "ok, no change"; return 0 ;;
          esac
          ;;
        [0-9])
          buf="$buf$key"
          val=$((10#$buf))
          [[ "$val" -ge 1 && "$val" -le "$n" ]] && sel=$((val - 1))
          ;;
        $'\177'|$'\b')
          buf="${buf%?}"
          if [[ -n "$buf" ]]; then
            val=$((10#$buf))
            [[ "$val" -ge 1 && "$val" -le "$n" ]] && sel=$((val - 1))
          fi
          ;;
        q|Q)
          trap - INT; printf '\r\033[%dA\033[J\033[?25h' "$((n + 1))"; echo "ok, no change"; return 0 ;;
        ''|$'\n'|$'\r')
          if [[ -n "$buf" ]]; then
            val=$((10#$buf))
            if [[ "$val" -ge 1 && "$val" -le "$n" ]]; then
              sel=$((val - 1)); break
            else
              buf=""                         # invalid number: ignore, keep picking
            fi
          else
            break
          fi
          ;;
      esac
    done

    trap - INT
    printf '\r\033[%dA\033[J\033[?25h' "$((n + 1))"   # wipe the picker, restore cursor
  fi

  ## commit: move the chosen task to the top of the store
  {
    printf '%s\n' "${tasks[$sel]}"
    for i in "${!tasks[@]}"; do
      [[ "$i" -ne "$sel" ]] && printf '%s\n' "${tasks[$i]}"
    done
  } > "$tasks_store"

  printf "ok, let's focus on \"\033[1m%s\033[0m\"\n" "${tasks[$sel]}"
}

## prints the latest task which you should be focusing on
[[ "$#" -eq 0 ]] && head -n 1 "$tasks_store"

while [[ "$#" -gt 0 ]]; do
  case $1 in
    -a|--add)
      if [[ -z "$2" ]]; then
        printf "error: -a/--add requires task text\n" >&2
        exit 1
      fi
      printf '%s\n' "$2" >> "$tasks_store"; echo "added: \"$2\""; shift ;;
    -x|--mark-done) echo "done: $(head -n 1 "$tasks_store")"; sed -i.bak '1d' "$tasks_store" && rm -f "$tasks_store.bak" ;;
    -f|--focus) focus_task || exit $? ;;
    -h|--help) printf "tasq: a simple task manager\nUsage\n-a, --add <task text> to add a new task\n-x, --mark-done to mark the latest task as done and remove it from the task queue\n-f, --focus pick a task from the list to move to the top and focus on\n" ;;
    *) printf "Unknown parameter passed: $1\nUse -h to print help text\n"; exit 1;;
  esac
  shift
done
