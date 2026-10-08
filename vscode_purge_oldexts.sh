#!/usr/bin/env bash
set -euo pipefail

EXT_DIR="$HOME/.vscode/extensions"

if [[ ! -d "$EXT_DIR" ]]; then
  echo "Error: Directory $EXT_DIR does not exist." >&2
  exit 1
fi

# Ensure VS Code is not actively running
if pgrep -f "Visual Studio Code" >/dev/null 2>&1; then
  echo "Error: Visual Studio Code is running. Close it before purging extensions." >&2
  exit 1
fi

# Backup manifest before modification
if [[ -f "$EXT_DIR/extensions.json" ]]; then
  cp "$EXT_DIR/extensions.json" "$EXT_DIR/extensions.json.bak"
fi

# Determine available version sort flag (GNU sort vs BSD sort)
SORT_FLAG="-n"
if sort --version-sort </dev/null >/dev/null 2>&1; then
  SORT_FLAG="-V"
elif sort -V </dev/null >/dev/null 2>&1; then
  SORT_FLAG="-V"
fi

# Identify unique extension identifier prefixes: <publisher>.<name>
find "$EXT_DIR" -mindepth 1 -maxdepth 1 -type d -name "*-*.*.*" -exec basename {} + \
  | sed -E 's/-[0-9]+(\.[0-9]+)*.*$//' \
  | sort -u \
  | while IFS= read -r ext; do

    # Collect matching folders
    mapfile -t versions < <(find "$EXT_DIR" -mindepth 1 -maxdepth 1 -type d -name "${ext}-*" -exec basename {} + | sort $SORT_FLAG)

    count="${#versions[@]}"
    if (( count > 1 )); then
      # Print all versions except the last (highest) entry
      for (( i=0; i<count-1; i++ )); do
        target="$EXT_DIR/${versions[i]}"
        echo "Purging old version: $target"
        rm -rf "$target"
      done
    fi
done

echo "Purge complete."
