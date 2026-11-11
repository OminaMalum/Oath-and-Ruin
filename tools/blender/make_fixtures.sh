#!/usr/bin/env bash
# Rebuilds the artist template rigs (assets/templates/*.blend) and the asset
# contract test fixtures (tests/fixtures/assets/*.glb) from the champion specs.
# Needs Blender's Python module: python3 -m pip install bpy (it matches a
# Blender release; 5.2.2 was used), or pass a python that has it.
#   tools/blender/make_fixtures.sh [python] [godot]
set -euo pipefail
cd "$(dirname "$0")/../.."
PY="${1:-python3}"; GODOT="${2:-godot}"
"$GODOT" --headless --path . -s tools/check_assets.gd -- --spec="$PWD/assets/specs" >/dev/null
mkdir -p assets/templates tests/fixtures/assets
for spec in assets/specs/*.json; do
  id=$(basename "$spec" .json)
  "$PY" tools/blender/make_template_rig.py "$spec" "assets/templates/${id}_template.blend" >/dev/null
done
tmp=$(mktemp -d)
for v in "ok:" "big:--scale=1.5" "back:--face-back" "slide:--stride=0.6" "late:--release=1.6"; do
  n=${v%%:*}; o=${v#*:}
  "$PY" tools/blender/make_template_rig.py assets/specs/ruinscribe.json "$tmp/$n.blend" $o >/dev/null
  "$PY" tools/blender/export_champion.py "$tmp/$n.blend" "tests/fixtures/assets/ruinscribe_v$n.glb" >/dev/null
done
rm -rf "$tmp"
find assets/templates -name "*.blend1" -delete
echo "templates and fixtures rebuilt"
