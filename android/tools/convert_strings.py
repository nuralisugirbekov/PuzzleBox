#!/usr/bin/env python3
"""Converts the iOS Localizable.strings files into JSON assets for the Android app.

Run from the repository root: python3 android/tools/convert_strings.py
Keys stay identical to the iOS ones (the English text), so both apps share one source of truth.
"""
import json, re, pathlib

root = pathlib.Path(__file__).resolve().parents[2]
out = root / "android/app/src/main/assets/l10n"
out.mkdir(parents=True, exist_ok=True)
pair = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;')

def unescape(s):
    return (s.replace('\\"', '"').replace("\\n", "\n").replace("\\t", "\t").replace("\\\\", "\\"))

def android_format(s):
    # iOS specifiers -> java.util.Formatter
    s = s.replace("%@", "%s").replace("%lld", "%d").replace("%ld", "%d")
    return re.sub(r"%(\d+)\$@", r"%\1$s", s)

for lproj in sorted((root / "PuzzleBoxApp").glob("*.lproj")):
    table = {}
    for line in (lproj / "Localizable.strings").read_text(encoding="utf-8").splitlines():
        m = pair.match(line)
        if m:
            table[unescape(m.group(1))] = android_format(unescape(m.group(2)))
    (out / f"{lproj.stem}.json").write_text(json.dumps(table, ensure_ascii=False, indent=0), encoding="utf-8")
    print(lproj.stem, len(table))
