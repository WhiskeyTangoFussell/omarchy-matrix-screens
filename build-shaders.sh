#!/usr/bin/env bash
# Compile the fragment shader to Qt's portable .qsb bundle. The compiled file
# is committed, so this only needs to run after editing matrix.frag.
# Requires qt6-shadertools (provides /usr/lib/qt6/bin/qsb).
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/shaders"
qsb=$(command -v qsb || echo /usr/lib/qt6/bin/qsb)
# GLSL ES 3.0 / GLSL 1.50 and up only: the shader uses texelFetch, which the
# legacy GLSL ES 1.00 and GLSL 1.20 targets lack. Hyprland itself needs GLES 3.
"$qsb" --glsl "300 es,150,330" --hlsl 50 --msl 12 -o matrix.frag.qsb matrix.frag
"$qsb" -d matrix.frag.qsb | head -3
