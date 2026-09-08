#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
out=${1:-"$root/dist/jafl.koplugin.zip"}
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT INT TERM

mkdir -p "$stage/jafl.koplugin/contentpack" "$(dirname "$out")"
cp -R "$root/plugins/jafl.koplugin/." "$stage/jafl.koplugin/"
cp "$root/books.ini" "$root/Rules.xml" "$root/QuickRules.xml" "$root/global.jpg" "$stage/jafl.koplugin/contentpack/"
for number in 1 2 3 4 5 6; do
    cp -R "$root/book$number" "$stage/jafl.koplugin/contentpack/"
    cp -R "$root/illus$number" "$stage/jafl.koplugin/contentpack/"
done

(cd "$stage" && zip -qr "$out" jafl.koplugin)
printf 'Created %s\n' "$out"
