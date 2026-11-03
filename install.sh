#!/usr/bin/env bash
# Install the dsh-harness skill for Codex (default) and/or Claude Code.
#
# Usage:
#   ./install.sh                # install for Codex (~/.codex/skills)
#   ./install.sh --claude       # install for Claude Code (~/.claude/skills)
#   ./install.sh --both         # install for both
#   ./install.sh --force        # overwrite without asking
#   ./install.sh --target codex|claude|both
set -euo pipefail

TARGET="codex"
FORCE="0"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while [ $# -gt 0 ]; do
  case "$1" in
    --claude) TARGET="claude"; shift ;;
    --both) TARGET="both"; shift ;;
    --target) TARGET="${2:-}"; shift 2 ;;
    --force|-f) FORCE="1"; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

case "$TARGET" in
  codex|claude|both) ;;
  *) echo "Invalid target: $TARGET (expected codex|claude|both)" >&2; exit 2 ;;
esac

SOURCE="$REPO_ROOT/skills/dsh-harness"
if [ ! -f "$SOURCE/SKILL.md" ]; then
  echo "SKILL.md not found under $SOURCE" >&2
  exit 1
fi

install_skill() {
  local label="$1" dest_root="$2"
  local dest="$dest_root/dsh-harness"
  echo "Installing $label skill -> $dest"
  if [ -e "$dest" ]; then
    if [ "$FORCE" != "1" ]; then
      read -r -p "The skill already exists at '$dest'. Overwrite? [y/N] " answer
      case "$answer" in
        y|Y|yes|YES) ;;
        *) echo "Skipped."; return 0 ;;
      esac
    fi
    rm -rf "$dest"
  fi
  mkdir -p "$dest_root"
  cp -R "$SOURCE" "$dest"
  if [ ! -f "$dest/SKILL.md" ]; then
    echo "Install failed: SKILL.md missing at $dest" >&2
    exit 1
  fi
  echo "  OK: SKILL.md present"
}

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"

if [ "$TARGET" = "codex" ] || [ "$TARGET" = "both" ]; then
  install_skill "Codex" "$CODEX_HOME/skills"
  echo 'Codex will discover it as $dsh-harness.'
fi

if [ "$TARGET" = "claude" ] || [ "$TARGET" = "both" ]; then
  install_skill "Claude Code" "$HOME/.claude/skills"
  echo 'Claude Code auto-loads it as dsh-harness@skills-dir on the next session (or /reload-plugins).'
fi

echo "Done."
