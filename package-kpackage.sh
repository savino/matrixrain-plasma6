#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT="${1:-${SCRIPT_DIR}/matrixrain-plasma6-wallpaper.zip}"

case "${OUTPUT}" in
    /*) ;;
    *) OUTPUT="${PWD}/${OUTPUT}" ;;
esac

mkdir -p "$(dirname -- "${OUTPUT}")"
(cd "${SCRIPT_DIR}/package" &&
    cmake -E tar cf "${OUTPUT}" --format=zip contents metadata.json)
printf 'Created Plasma wallpaper archive: %s\n' "${OUTPUT}"
