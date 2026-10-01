#!/usr/bin/env python3
"""Merge human + catalog translations into Localizable.xcstrings for all wired UI keys."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
XC = ROOT / "TheScale" / "Resources" / "Localizable.xcstrings"
EN_PATH = Path("/tmp/fatnag_en.json")
HUMAN_PATH = Path("/tmp/fatnag_l10n/human_merged.json")
GOOD_PATH = Path("/tmp/fatnag_good.json")

LOCALES = [
    "ar", "ca", "cs", "da", "de", "el", "es", "fi", "fr", "he", "hi", "hr", "hu",
    "id", "it", "ja", "ko", "ms", "nb", "nl", "pl", "pt-BR", "pt-PT", "ro", "ru",
    "sk", "sv", "th", "tr", "uk", "vi", "zh-Hans", "zh-Hant",
]

ALLOW_SAME = {
    "OK", "COACH", "LIVE", "LIMIT", "STREAM", "Keel", "fatnag", "BMI", "AI",
    "cm", "kg", "lb", "kcal", "Plus", "Pro", "Free", "IF", "Health",
    "Apple Health", "Grok", "FATNAG", "HARDCORE", "COMMANDO", "HOLD", "Coach",
    "App", "Charts", "Scale", "Macro", "Micro", "MANUAL", "Manual", "INSIGHT",
}

PH = re.compile(r"(%(?:\d+\$)?[@dDfFs]|%\.\d+f|%lld|%ld|%ds)")


def placeholders_ok(en: str, tr: str) -> bool:
    return PH.findall(en) == PH.findall(tr)


def is_en_dup(val: str, en: str) -> bool:
    if not val:
        return True
    if val == en:
        if en in ALLOW_SAME or en.strip() in ALLOW_SAME:
            return False
        if len(en) <= 3 and en.isupper():
            return False
        return True
    return False


def unit(value: str) -> dict:
    return {"stringUnit": {"state": "translated", "value": value}}


def load_extra_lists(human: dict[str, dict[str, str]]) -> None:
    uniq_path = Path("/tmp/fatnag_uniq.json")
    if not uniq_path.exists():
        return
    uniq = json.loads(uniq_path.read_text(encoding="utf-8"))
    for path in Path("/tmp/fatnag_l10n").glob("_*.json"):
        loc = path.stem[1:]
        if loc in {"keep", "partial_out", "romance_seed"}:
            continue
        data = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(data, list) and len(data) == len(uniq):
            human.setdefault(loc, {})
            for i, en in enumerate(uniq):
                tr = data[i]
                if isinstance(tr, str) and tr.strip():
                    human[loc][en] = tr.strip()


def main() -> None:
    en_map: dict[str, str] = json.loads(EN_PATH.read_text(encoding="utf-8"))
    human: dict[str, dict[str, str]] = json.loads(HUMAN_PATH.read_text(encoding="utf-8"))
    load_extra_lists(human)
    good: dict[str, dict[str, str]] = json.loads(GOOD_PATH.read_text(encoding="utf-8"))

    cat = json.loads(XC.read_text(encoding="utf-8"))
    strings = cat.setdefault("strings", {})

    stats = {loc: {"set": 0, "missing": 0} for loc in LOCALES}

    for key, en in en_map.items():
        entry = strings.setdefault(key, {})
        # wipe comment-only empty shells that block localizations? keep comment if any
        locs = entry.setdefault("localizations", {})
        locs["en"] = unit(en)

        for loc in LOCALES:
            chosen = None
            candidates = []
            if en in human.get(loc, {}):
                candidates.append(human[loc][en])
            if key in good.get(loc, {}):
                candidates.append(good[loc][key])
            existing = ((locs.get(loc) or {}).get("stringUnit") or {}).get("value")
            if existing:
                candidates.append(existing)

            for cand in candidates:
                if cand and not is_en_dup(cand, en) and placeholders_ok(en, cand):
                    chosen = cand
                    break
            if chosen is None and (en in ALLOW_SAME or en.strip() in ALLOW_SAME):
                chosen = en

            if chosen is None:
                stats[loc]["missing"] += 1
                continue

            locs[loc] = unit(chosen)
            stats[loc]["set"] += 1

    XC.write_text(json.dumps(cat, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Wrote", XC)
    for loc in LOCALES:
        s = stats[loc]
        print(f"{loc}: set={s['set']}/{len(en_map)} missing={s['missing']}")


if __name__ == "__main__":
    main()
