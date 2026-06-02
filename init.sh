#!/usr/bin/env bash
# init.sh — Bootstrap a new PWA from sholtomaud/pwa-template.
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/sholtomaud/pwa-template/main/init.sh)
set -euo pipefail

TEMPLATE_REPO="https://github.com/sholtomaud/pwa-template.git"

# ── Helpers ───────────────────────────────────────────────────────────────────

bold() { printf '\033[1m%s\033[0m' "$*"; }

# ask PROMPT VARNAME
ask() {
  printf '%s ' "$(bold "$1")"
  read -r "$2"
}

# askd PROMPT VARNAME DEFAULT
askd() {
  local _varname=$2
  printf '%s [%s] ' "$(bold "$1")" "$3"
  read -r "$_varname"
  if [[ -z "${!_varname}" ]]; then
    printf -v "$_varname" '%s' "$3"
  fi
}

slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-' | sed 's/^-//;s/-$//'
}

pascalize() {
  echo "$1" | awk -F'-' '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2); OFS=""; print}'
}

sedi() {
  [[ "$(uname)" == "Darwin" ]] && sed -i '' "$@" || sed -i "$@"
}

# replace_in_tree OLD NEW DIR
# Replaces all occurrences of OLD with NEW in all text files under DIR.
# Uses python3 to safely handle user-provided strings without sed metachar issues.
replace_in_tree() {
  local old=$1 new=$2 dir=$3
  python3 - "$old" "$new" "$dir" <<'PYEOF'
import sys, os

old, new, directory = sys.argv[1], sys.argv[2], sys.argv[3]

SKIP_DIRS  = {'node_modules', '.git', 'dist', 'cdk.out', '.vite'}
SKIP_FILES = {'init.sh', 'package-lock.json'}
TEXT_EXTS  = {'.ts', '.js', '.html', '.css', '.json', '.md', '.yml', '.yaml', ''}
NAMED_TEXT = {'Makefile', 'Containerfile'}

for root, dirs, files in os.walk(directory):
    dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
    for fname in files:
        if fname in SKIP_FILES:
            continue
        _, ext = os.path.splitext(fname)
        if ext not in TEXT_EXTS and fname not in NAMED_TEXT:
            continue
        path = os.path.join(root, fname)
        try:
            with open(path, 'r', encoding='utf-8', errors='strict') as f:
                content = f.read()
            updated = content.replace(old, new)
            if updated != content:
                with open(path, 'w', encoding='utf-8') as f:
                    f.write(updated)
        except (UnicodeDecodeError, IOError, PermissionError):
            pass
PYEOF
}

rename_component() {
  local old=$1 new=$2 base="scripts/components"
  [[ -d "$base/$old" ]] || return 0
  for f in "$base/$old/$old".*; do
    [[ -e "$f" ]] && mv "$f" "$base/$old/$new.${f##*.}"
  done
  mv "$base/$old" "$base/$new"
}

# ── Dependency checks ─────────────────────────────────────────────────────────

for cmd in git python3; do
  command -v "$cmd" &>/dev/null || {
    echo "Error: '$cmd' is required but not found. Please install it and re-run."
    exit 1
  }
done

# ── Questions ─────────────────────────────────────────────────────────────────

echo ""
echo "=== PWA Template Bootstrap ==="
echo ""

ask  "App display name (e.g. 'My Finance App'):"                 APP_NAME

APP_SLUG_DEFAULT=$(slugify "$APP_NAME")
askd "App slug  (package name, container image):"                APP_SLUG        "$APP_SLUG_DEFAULT"

APP_PREFIX_DEFAULT=$(echo "$APP_SLUG" | cut -d'-' -f1)
askd "Component prefix  (<PREFIX-root>, <PREFIX-list>, ...):"    APP_PREFIX      "$APP_PREFIX_DEFAULT"

askd "Short description:"                                        APP_DESCRIPTION "A progressive web application."
askd "Theme color (hex):"                                        THEME_COLOR     "#1a1a2e"
askd "Version:"                                                  APP_VERSION     "1.0.0"
askd "Output directory:"                                         OUTPUT_DIR      "./$APP_SLUG"
askd "GitHub username:"                                          GITHUB_USERNAME "sholtomaud"
askd "GitHub repo name:"                                         GITHUB_REPO     "$APP_SLUG"

CLASS_PREFIX=$(pascalize "$APP_PREFIX")

# ── Confirm ───────────────────────────────────────────────────────────────────

echo ""
echo "──────────────────────────────────────────────────────"
printf "  %-22s %s\n" "App name:"         "$APP_NAME"
printf "  %-22s %s\n" "Slug:"             "$APP_SLUG"
printf "  %-22s %s\n" "Element prefix:"   "$APP_PREFIX  →  <$APP_PREFIX-root>, <$APP_PREFIX-list>, ..."
printf "  %-22s %s\n" "Class prefix:"     "$CLASS_PREFIX  →  ${CLASS_PREFIX}Root, ${CLASS_PREFIX}List, ..."
printf "  %-22s %s\n" "Description:"      "$APP_DESCRIPTION"
printf "  %-22s %s\n" "Theme color:"      "$THEME_COLOR"
printf "  %-22s %s\n" "Version:"          "$APP_VERSION"
printf "  %-22s %s\n" "Output:"           "$OUTPUT_DIR"
printf "  %-22s %s\n" "GitHub:"           "github.com/$GITHUB_USERNAME/$GITHUB_REPO"
echo "──────────────────────────────────────────────────────"

echo ""
ask "Continue? (y/n):" CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
echo ""

# ── Clone template ────────────────────────────────────────────────────────────

echo "Cloning template..."
git clone --depth=1 "$TEMPLATE_REPO" "$OUTPUT_DIR"
cd "$OUTPUT_DIR"
rm -rf .git

# ── Rename component directories and files ────────────────────────────────────

echo "Renaming components..."
rename_component "tpl-root"    "${APP_PREFIX}-root"
rename_component "tpl-list"    "${APP_PREFIX}-list"
rename_component "tpl-item"    "${APP_PREFIX}-item"
rename_component "tpl-input"   "${APP_PREFIX}-input"
rename_component "tpl-nav"     "${APP_PREFIX}-nav"
rename_component "tpl-profile" "${APP_PREFIX}-profile"

# ── Content substitutions ─────────────────────────────────────────────────────

echo "Applying substitutions..."

# Element/class names are controlled strings — sed is safe here
find . -type f \( \
  -name "*.ts" -o -name "*.js" -o -name "*.html" -o -name "*.css" \
  -o -name "*.json" -o -name "*.md" -o -name "*.yml" -o -name "Makefile" \
\) \
  -not -path "*/node_modules/*" \
  -not -path "*/.git/*" \
  -not -path "*/dist/*" \
  -not -name "init.sh" \
  -not -name "package-lock.json" \
| while IFS= read -r f; do
  sedi \
    -e "s/TplRoot/${CLASS_PREFIX}Root/g" \
    -e "s/TplList/${CLASS_PREFIX}List/g" \
    -e "s/TplItem/${CLASS_PREFIX}Item/g" \
    -e "s/TplInput/${CLASS_PREFIX}Input/g" \
    -e "s/TplNav/${CLASS_PREFIX}Nav/g" \
    -e "s/TplProfile/${CLASS_PREFIX}Profile/g" \
    -e "s/tpl-root/${APP_PREFIX}-root/g" \
    -e "s/tpl-list/${APP_PREFIX}-list/g" \
    -e "s/tpl-item/${APP_PREFIX}-item/g" \
    -e "s/tpl-input/${APP_PREFIX}-input/g" \
    -e "s/tpl-nav/${APP_PREFIX}-nav/g" \
    -e "s/tpl-profile/${APP_PREFIX}-profile/g" \
    "$f"
done

# User-provided strings — python3 handles special characters safely
replace_in_tree "{{APP_NAME}}"        "$APP_NAME"        "."
replace_in_tree "{{APP_SLUG}}"        "$APP_SLUG"        "."
replace_in_tree "{{APP_DESCRIPTION}}" "$APP_DESCRIPTION" "."
replace_in_tree "{{THEME_COLOR}}"     "$THEME_COLOR"     "."
replace_in_tree "{{APP_VERSION}}"     "$APP_VERSION"     "."

# ── Fresh git ─────────────────────────────────────────────────────────────────

echo "Initializing git repository..."
git init
git add -A
git commit -m "chore: scaffold $APP_NAME from pwa-template"

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "=== Done! ==="
echo ""
echo "  cd $OUTPUT_DIR"
echo "  make image     # build container image (first run)"
echo "  make install   # install npm deps inside container"
echo "  make dev       # dev server at http://localhost:5173"
echo "  make test      # Playwright E2E test suite"
echo ""
echo "Push to GitHub:"
echo "  gh repo create $GITHUB_USERNAME/$GITHUB_REPO --public --source=. --push"
echo ""
