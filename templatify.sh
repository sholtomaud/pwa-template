#!/usr/bin/env bash
# templatify.sh
# Run once inside pwa-template/ to convert copied app files into a generic template.
# Safe to re-run: file renames are skipped when the source dir no longer exists.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

sedi() {
  [[ "$(uname)" == "Darwin" ]] && sed -i '' "$@" || sed -i "$@"
}

rename_component() {
  local old=$1 new=$2 base="scripts/components"
  if [[ ! -d "$base/$old" ]]; then
    echo "  skip: $old (not found or already renamed)"
    return
  fi
  for f in "$base/$old/$old".*; do
    [[ -e "$f" ]] && mv "$f" "$base/$old/$new.${f##*.}"
  done
  mv "$base/$old" "$base/$new"
  echo "  $old  ->  $new"
}

# ── Step 1: Rename component directories and files ───────────────────────────
echo ""
echo "Step 1: Rename components"
rename_component "todo-app"       "tpl-root"
rename_component "todo-list"      "tpl-list"
rename_component "todo-item"      "tpl-item"
rename_component "todo-input"     "tpl-input"
rename_component "app-navigation" "tpl-nav"
rename_component "user-profile"   "tpl-profile"
if [[ -f "tests/todo-flow.spec.ts" ]]; then
  mv tests/todo-flow.spec.ts tests/app-flow.spec.ts
  echo "  todo-flow.spec.ts  ->  app-flow.spec.ts"
fi

# ── Step 2: Content substitutions ────────────────────────────────────────────
echo ""
echo "Step 2: Substitute content"

find . -type f \( \
  -name "*.ts" -o -name "*.js" -o -name "*.html" -o -name "*.css" \
  -o -name "*.json" -o -name "*.md" -o -name "*.yml" \
  -o -name "Makefile" -o -name "Containerfile" \
\) \
  -not -path "*/node_modules/*" \
  -not -path "*/.git/*" \
  -not -path "*/dist/*" \
  -not -path "*/cdk.out/*" \
  -not -name "package-lock.json" \
  -not -name "templatify.sh" \
  -not -name "init.sh" \
| while IFS= read -r f; do

  # ── localStorage keys: must run BEFORE element-name substitutions ──────────
  # 'user-profile' would otherwise become 'tpl-profile' (wrong for a storage key)
  sedi "s|localStorage\.getItem('user-profile')|localStorage.getItem('{{APP_SLUG}}-profile')|g" "$f"
  sedi "s|localStorage\.setItem('user-profile'|localStorage.setItem('{{APP_SLUG}}-profile'|g" "$f"
  sedi "s|localStorage\.getItem('todos')|localStorage.getItem('{{APP_SLUG}}-items')|g" "$f"
  sedi "s|localStorage\.setItem('todos'|localStorage.setItem('{{APP_SLUG}}-items'|g" "$f"

  # ── PascalCase class names ─────────────────────────────────────────────────
  sedi -e 's/AppNavigation/TplNav/g' \
       -e 's/UserProfile/TplProfile/g' \
       -e 's/TodoApp/TplRoot/g' \
       -e 's/TodoList/TplList/g' \
       -e 's/TodoItem/TplItem/g' \
       -e 's/TodoInput/TplInput/g' \
       "$f"

  # ── Custom element names and import paths ──────────────────────────────────
  sedi -e 's/todo-app/tpl-root/g' \
       -e 's/todo-list/tpl-list/g' \
       -e 's/todo-item/tpl-item/g' \
       -e 's/todo-input/tpl-input/g' \
       -e 's/app-navigation/tpl-nav/g' \
       -e 's/user-profile/tpl-profile/g' \
       "$f"

  # ── Custom event names ─────────────────────────────────────────────────────
  sedi -e "s/'todo-add'/'item-add'/g" \
       -e "s/'todo-toggle'/'item-toggle'/g" \
       -e "s/'todo-delete'/'item-delete'/g" \
       -e "s/'todo-edit'/'item-edit'/g" \
       "$f"

  # ── TypeScript interface, type annotations, properties ────────────────────
  sedi -e 's/interface Todo {/interface TplItem {/g' \
       -e 's/: Todo\[\]/: TplItem[]/g' \
       -e 's/Todo\[\]/TplItem[]/g' \
       -e 's/private todos:/private items:/g' \
       -e 's/this\.todos/this.items/g' \
       -e 's/const newTodo/const newItem/g' \
       "$f"

  # ── App-specific string values ─────────────────────────────────────────────
  sedi -e 's/passive-cashflow-pwa/{{APP_SLUG}}/g' \
       -e 's/mvc-pwa/{{APP_SLUG}}/g' \
       -e 's/todo-app-pwa/{{APP_SLUG}}/g' \
       -e 's/Todo App/{{APP_NAME}}/g' \
       -e 's/todo-app-v1\.2\.0/{{APP_SLUG}}-v{{APP_VERSION}}/g' \
       "$f"

  # Long description — | delimiter avoids issues with commas and dots
  sedi "s|A beautiful, premium, offline-first target and todo tracker designed for high productivity\.|{{APP_DESCRIPTION}}|g" "$f"

  # ── Theme color, version, container name ──────────────────────────────────
  sedi -e 's/#0a0a0c/{{THEME_COLOR}}/g' \
       -e 's/"version": "2\.0\.0"/"version": "{{APP_VERSION}}"/g' \
       -e 's/--name mvc-pwa-dev/--name {{APP_SLUG}}-dev/g' \
       "$f"
done

# ── Step 3: Remove artifacts and app-specific assets ─────────────────────────
echo ""
echo "Step 3: Remove artifacts"
rm -rf playwright-report test-results .antigravitycli TODO.md package-lock.json
rm -f public/images/i-love-pirates.jpg \
      public/images/parrot_plank.jpg \
      public/images/peggy_parrot.jpg \
      public/images/pirate-clip-art.jpg

echo ""
echo "Done. Review with 'git diff', then:"
echo "  git add -A && git commit -m 'chore: templatify'"
