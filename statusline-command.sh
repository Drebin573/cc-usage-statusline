#!/bin/sh
# Claude Code status line — two-line layout
# Line 1: cwd (left) ··· context/5hr/7day progress bars (right)
# Line 2: repo hyperlink + branch (left) ··· session cost (right)
#
# ─────────────────────────────────────────────────────────────────────────────
# INSTALL (for a human or an agent — these steps are self-contained):
#
#   1. Copy this file to ~/.claude/statusline-command.sh and make it executable:
#        mkdir -p ~/.claude
#        cp statusline-command.sh ~/.claude/statusline-command.sh
#        chmod +x ~/.claude/statusline-command.sh
#
#   2. Point Claude Code at it by adding this to ~/.claude/settings.json.
#      MERGE this key into the existing JSON — do not overwrite the file:
#        "statusLine": {
#          "type": "command",
#          "command": "<ABSOLUTE-PATH-TO-HOME>/.claude/statusline-command.sh"
#        }
#      (use the absolute path, e.g. /Users/you/.claude/statusline-command.sh)
#
#   3. Requirements: `jq` and `git` must be on PATH. Claude Code v2.1.153+
#      recommended (provides accurate $COLUMNS for right-alignment).
#
#   4. Start a new Claude Code session (or run /statusline) to see it.
#
# See README.md in this directory for the full guide.
# ─────────────────────────────────────────────────────────────────────────────

input=$(cat)

# ── data extraction ──────────────────────────────────────────
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
rate_5h=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
rate_7d=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
reset_5h=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
duration_ms=$(echo "$input" | jq -r '.cost.total_api_duration_ms // empty')

# Shorten home dir
short_cwd=$(echo "$cwd" | sed "s|^$HOME|~|")

# Git info
git_branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null)
remote_url=$(git -C "$cwd" --no-optional-locks remote get-url origin 2>/dev/null)

# Convert remote URL to HTTPS for hyperlink
repo_name=""
repo_https=""
if [ -n "$remote_url" ]; then
  # Handle git@github.com:user/repo.git and https://github.com/user/repo.git
  repo_https=$(echo "$remote_url" | sed -e 's|^git@github.com:|https://github.com/|' -e 's|\.git$||')
  # Extract user/repo
  repo_name=$(echo "$repo_https" | sed -e 's|.*github.com/||')
fi

# ── colors ───────────────────────────────────────────────────
reset="\033[0m"
dim="\033[2m"
muted_blue="\033[38;5;67m"     # cwd
muted_cyan="\033[38;5;73m"     # context hex
muted_magenta="\033[38;5;133m" # 5hr hex
muted_orange="\033[38;5;173m"  # 7day hex
muted_green="\033[38;5;71m"    # branch
muted_teal="\033[38;5;109m"    # repo link
muted_gold="\033[38;5;178m"    # cost
sep_color="\033[38;5;238m"     # separators

# ── helpers ──────────────────────────────────────────────────
# High-fidelity progress bar using Unicode fractional blocks
# Usage: progress_bar <percentage> <fg_color> <width>
# Uses ▏▎▍▌▋▊▉█ for 8 sub-character levels of precision
progress_bar() {
  pct="$1"
  fg="$2"
  width="${3:-5}"
  empty_color="\033[38;5;238m"

  if [ -z "$pct" ]; then
    # No data — empty bar with background
    printf '%b' "\033[48;5;238m"
    i=0; while [ "$i" -lt "$width" ]; do printf ' '; i=$((i+1)); done
    printf '%b' "$reset"
    return
  fi

  int_pct=$(printf "%.0f" "$pct")
  [ "$int_pct" -lt 0 ] 2>/dev/null && int_pct=0
  [ "$int_pct" -gt 100 ] 2>/dev/null && int_pct=100

  # fill_eighths = total eighth-blocks to fill (0 to width*8)
  fill_eighths=$(( int_pct * width * 8 / 100 ))
  full=$(( fill_eighths / 8 ))
  frac=$(( fill_eighths % 8 ))
  empty=$(( width - full - (frac > 0 ? 1 : 0) ))

  # Fractional block chars indexed 0-7 (0 = empty, 1-7 = ▏▎▍▌▋▊▉)
  frac_char=""
  case "$frac" in
    1) frac_char="▏";; 2) frac_char="▎";; 3) frac_char="▍";;
    4) frac_char="▌";; 5) frac_char="▋";; 6) frac_char="▊";;
    7) frac_char="▉";; *) frac_char="";;
  esac

  # Build bar with background color to fill gaps behind fractional blocks
  bar_bg="\033[48;5;238m"
  bar=""
  i=0; while [ "$i" -lt "$full" ]; do bar="${bar}█"; i=$((i+1)); done
  if [ -n "$frac_char" ]; then bar="${bar}${frac_char}"; fi
  emp=""
  i=0; while [ "$i" -lt "$empty" ]; do emp="${emp} "; i=$((i+1)); done

  printf '%b%b%s%s%b' "$bar_bg" "$fg" "$bar" "$emp" "$reset"
}

# Claude Code captures stdout, so `tput cols` can't read the real terminal
# width and returns stale/fallback values — causing the right side to overflow
# and get truncated to "...". Claude Code sets $COLUMNS to the true width
# (v2.1.153+); prefer it, but it can arrive as 0 or non-numeric, so validate
# and fall back to tput then 80. A small safety margin keeps the right-aligned
# content clear of the interface's built-in edge padding.
cols=$COLUMNS
case "$cols" in ''|*[!0-9]*) cols=$(tput cols 2>/dev/null);; esac
case "$cols" in ''|*[!0-9]*) cols=80;; esac
[ "$cols" -lt 20 ] && cols=80
# Claude Code's status line reserves a few columns on the right; a line that
# fills past ~COLUMNS-4 gets truncated to "...". Empirically measured at 4.
cols=$(( cols - 4 ))

# Right-align helper: takes left text, right text, and visible lengths
# Outputs: left + padding + right
align_lr() {
  left_text="$1"
  right_text="$2"
  left_len="$3"
  right_len="$4"
  gap=$(( cols - left_len - right_len ))
  [ "$gap" -lt 1 ] && gap=1
  padding=$(printf '%*s' "$gap" '')
  printf '%b%s%b' "$left_text" "$padding" "$right_text"
}

# ── context bar with 50% threshold ────────────────────────────
# Renders per-character: cyan below 50%, warning color above.
# Color transition happens at a clean character boundary (no gap).
context_bar() {
  pct="$1"
  width="${2:-5}"
  normal_color="\033[38;5;73m"   # muted cyan
  empty_color="\033[38;5;238m"
  threshold=50

  if [ -z "$pct" ]; then
    printf '%b' "\033[48;5;238m"
    i=0; while [ "$i" -lt "$width" ]; do printf ' '; i=$((i+1)); done
    printf '%b' "$reset"
    return
  fi

  int_pct=$(printf "%.0f" "$pct")
  [ "$int_pct" -lt 0 ] 2>/dev/null && int_pct=0
  [ "$int_pct" -gt 100 ] 2>/dev/null && int_pct=100

  # Pick warning color based on how far past threshold
  if [ "$int_pct" -ge 90 ]; then
    warn_color="\033[38;5;196m"   # bright red
  elif [ "$int_pct" -ge 75 ]; then
    warn_color="\033[38;5;208m"   # orange
  elif [ "$int_pct" -ge 50 ]; then
    warn_color="\033[38;5;178m"   # yellow/gold
  else
    warn_color="$normal_color"
  fi

  fill_eighths=$(( int_pct * width * 8 / 100 ))
  thresh_eighths=$(( threshold * width * 8 / 100 ))

  # Render character by character (bg color fills gaps behind fractional blocks)
  bar_bg="\033[48;5;238m"
  printf '%b' "$bar_bg"
  pos=0
  while [ "$pos" -lt "$width" ]; do
    char_start=$(( pos * 8 ))
    char_end=$(( (pos + 1) * 8 ))

    # How many eighths of this character are filled
    if [ "$fill_eighths" -ge "$char_end" ]; then
      level=8
    elif [ "$fill_eighths" -gt "$char_start" ]; then
      level=$(( fill_eighths - char_start ))
    else
      level=0
    fi

    # Color: based on whether this character starts at/after threshold
    if [ "$char_start" -ge "$thresh_eighths" ]; then
      color="$warn_color"
    else
      color="$normal_color"
    fi

    if [ "$level" -eq 8 ]; then
      printf '%b█' "$color"
    elif [ "$level" -eq 0 ]; then
      printf ' '
    else
      printf '%b' "$color"
      case "$level" in
        1) printf '▏';; 2) printf '▎';; 3) printf '▍';;
        4) printf '▌';; 5) printf '▋';; 6) printf '▊';;
        7) printf '▉';;
      esac
    fi

    pos=$(( pos + 1 ))
  done
  printf '%b' "$reset"
}

# ── line 1: cwd + progress bars ──────────────────────────────
bar_w=5

left1="${muted_blue}${short_cwd}${reset}"
left1_len=${#short_cwd}

sep="${sep_color}·${reset}"

bar_ctx=$(context_bar "$used" "$bar_w")
bar_5h=$(progress_bar "$rate_5h" "$muted_magenta" "$bar_w")
bar_7d=$(progress_bar "$rate_7d" "$muted_orange" "$bar_w")

right1="${bar_ctx} ${bar_5h} ${bar_7d}"
# Visible length: 3 bars × width + 2 spaces
right1_len=$(( bar_w * 3 + 2 ))

line1=$(align_lr "$left1" "$right1" "$left1_len" "$right1_len")

# ── line 2: repo link + branch ··· bar-aligned metrics ──────
left2=""
left2_len=0

if [ -n "$repo_name" ] && [ -n "$repo_https" ]; then
  # OSC 8 clickable hyperlink
  link="\033]8;;${repo_https}\033\\${muted_teal}${repo_name}${reset}\033]8;;\033\\"
  left2="${link}"
  left2_len=${#repo_name}
else
  left2="${dim}no remote${reset}"
  left2_len=9
fi

if [ -n "$git_branch" ]; then
  left2="${left2} ${sep} ${muted_green}${git_branch}${reset}"
  left2_len=$(( left2_len + 3 + ${#git_branch} ))
fi

# Right side: three values aligned vertically under the line-1 bars —
#   session time (under context bar) · 5h renewal (under 5h bar) · cost (under 7d bar)

# Elapsed session time
time_str=""
if [ -n "$duration_ms" ]; then
  total_sec=$(( duration_ms / 1000 ))
  hrs=$(( total_sec / 3600 ))
  mins=$(( (total_sec % 3600) / 60 ))
  secs=$(( total_sec % 60 ))
  if [ "$hrs" -gt 0 ]; then
    time_str=$(printf '%dh%02dm' "$hrs" "$mins")
  elif [ "$mins" -gt 0 ]; then
    time_str=$(printf '%dm%02ds' "$mins" "$secs")
  else
    time_str=$(printf '%ds' "$secs")
  fi
fi

# Time until the 5-hour limit renews (resets_at is unix epoch seconds)
renew_str=""
if [ -n "$reset_5h" ]; then
  remain=$(( reset_5h - $(date +%s) ))
  if [ "$remain" -gt 0 ]; then
    r_h=$(( remain / 3600 ))
    r_m=$(( (remain % 3600) / 60 ))
    if [ "$r_h" -gt 0 ]; then
      renew_str=$(printf '%dh%02dm' "$r_h" "$r_m")
    else
      renew_str=$(printf '%dm' "$r_m")
    fi
  fi
fi

# Cost
cost_str=""
[ -n "$cost" ] && cost_str=$(printf '$%.2f' "$cost")

# cell <text> <color>: print the text centered in a bar_w-wide column.
# Cells match the line-1 bar geometry so values line up under their bars.
cell() {
  c_text="$1"; c_color="$2"; c_len=${#c_text}
  if [ "$c_len" -ge "$bar_w" ]; then
    printf '%b%s%b' "$c_color" "$c_text" "$reset"
  else
    pad=$(( bar_w - c_len )); pl=$(( pad / 2 )); pr=$(( pad - pl ))
    printf '%*s%b%s%b%*s' "$pl" '' "$c_color" "$c_text" "$reset" "$pr" ''
  fi
}
# visible width of a cell = max(text length, bar_w)
cellvis() { _l=${#1}; [ "$_l" -ge "$bar_w" ] && printf '%s' "$_l" || printf '%s' "$bar_w"; }

right2="$(cell "$time_str" "$dim") $(cell "$renew_str" "$muted_magenta") $(cell "$cost_str" "$muted_gold")"
right2_len=$(( $(cellvis "$time_str") + 1 + $(cellvis "$renew_str") + 1 + $(cellvis "$cost_str") ))

line2=$(align_lr "$left2" "$right2" "$left2_len" "$right2_len")

# ── output ───────────────────────────────────────────────────
printf '%b\n%b\n' "$line1" "$line2"
