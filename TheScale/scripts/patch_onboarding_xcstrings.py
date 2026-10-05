#!/usr/bin/env python3
"""Upsert onboarding UI strings into Localizable.xcstrings for every app locale."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
XC = ROOT / "TheScale" / "Resources" / "Localizable.xcstrings"

LOCALES = [
    "ar", "ca", "cs", "da", "de", "el", "es", "fi", "fr", "he", "hi", "hr", "hu",
    "id", "it", "ja", "ko", "ms", "nb", "nl", "pl", "pt-BR", "pt-PT", "ro", "ru",
    "sk", "sv", "th", "tr", "uk", "vi", "zh-Hans", "zh-Hant",
]

# English source of truth (matches OnboardingView defaults).
EN: dict[str, str] = {
    "onboarding.cta.next": "Next",
    "onboarding.cta.skip": "Skip for now",
    "onboarding.units.need_choice": "Choose weight and height units, then tap Next.",
    "onboarding.units.prompt": "How do you measure yourself?",
    "onboarding.identity.need_name": "Type your name, then tap Next.",
    "onboarding.identity.prompt": "What should we call you?",
    "onboarding.identity.placeholder": "First name",
    "onboarding.step.units": "Units",
    "onboarding.step.identity": "Your name",
    "onboarding.step.body": "About you",
    "onboarding.step.anatomy": "Height & weight",
    "onboarding.step.confirm": "Almost done",
    "onboarding.sub.language": "Pick the language for the app.",
    "onboarding.sub.body": "Age and gender. Adults 18+ only.",
    "onboarding.sub.dream": "Set a target weight and date.",
    "onboarding.sub.confirm": "Agree to continue, then start.",
    "onboarding.step.counter": "%d of %d",
    "onboarding.body.age_prompt": "How old are you?",
    "onboarding.body.sex_prompt": "I am…",
    "onboarding.age.label": "AGE",
    "onboarding.age.a11y": "Age",
    "onboarding.age.not_set": "not set",
    "onboarding.age.years_a11y": "%d years",
    "onboarding.age.min": "You must be 18 or older.",
    "onboarding.age.max": "Age max is 100.",
    "onboarding.age.invalid": "Enter a valid age.",
    "onboarding.anatomy.height_prompt": "How tall are you?",
    "onboarding.anatomy.weight_prompt": "What do you weigh today?",
    "onboarding.anatomy.checking_health": "Checking Apple Health…",
    "onboarding.anatomy.drag": "Drag to set.",
    "onboarding.anatomy.from_health": "From Health · %@",
    "onboarding.anatomy.change_weight": "Change",
    "onboarding.dream.target": "Target",
    "onboarding.dream.caption": "Drag. Marks move. Needle stays.",
    "onboarding.lifestyle.prompt": "How do you eat?",
    "onboarding.lifestyle.hint": "Optional. Skip if you want — we can ask later.",
    "onboarding.lifestyle.avoid_prompt": "Anything to avoid?",
    "onboarding.lifestyle.avoid_placeholder": "Peanuts, shellfish… (optional)",
    "onboarding.lifestyle.city_prompt": "Where do you live?",
    "onboarding.lifestyle.city_placeholder": "City (optional)",
    "units.weight.prompt": "Weight",
    "units.height.prompt": "Height",
    "units.location.hint": "Suggested for %@: %@ weight, %@ height. Mix freely.",
    "units.region.fallback": "your region",
    "diet.omnivore": "Omnivore",
    "diet.pescatarian": "Pescatarian",
    "diet.vegetarian": "Vegetarian",
    "diet.vegan": "Vegan",
    "diet.other": "Other / flexible",
    "profile.sex.female": "Woman",
    "profile.sex.male": "Man",
    "onboarding.confirm.lang": "Language",
    "onboarding.confirm.dream": "Dream %@ by %@",
    "onboarding.confirm.alerts": "Alerts",
    "onboarding.confirm.keel_later": "Allow live %@ Coach later",
    "onboarding.confirm.legal": "I agree to Terms, Privacy Policy, and the fitness disclaimer",
    "onboarding.confirm.privacy": "Privacy",
    "onboarding.confirm.terms": "Terms",
    "onboarding.confirm.disclaimer": "Disclaimer",
    "onboarding.confirm.age_legal": "Age %d+ required. Full copies stay in Settings → Privacy & Legal.",
    "onboarding.confirm.diet_unset": "Diet not set",
    "onboarding.confirm.location_unset": "Location not set",
    "onboarding.confirm.avoids_none": "No avoids yet",
    "onboarding.confirm.avoids": "Avoid: %@",
    "onboarding.confirm.medical_body": "Coach is educational fitness coaching, not medical advice. It does not diagnose, treat, or replace a clinician. If something feels wrong, talk to a real doctor.",
    "onboarding.inference.empty": "No note to parse. Defaults ready. Edit anything below.",
    "onboarding.inference.fm": "On-device Coach filled these from your note. Edit freely.",
    "onboarding.inference.heuristic": "Filled on-device from your note. Edit freely.",
    "onboarding.pace.too_soon": "Pick a date at least a week out. Instant transformation is a fairy tale, not a plan.",
    "onboarding.pace.hold": "Already near that number. Fine as a hold target.",
    "onboarding.pace.human": "Pace looks human: about %.2f kg/week (safe cap ~%.2f kg/week).",
    "onboarding.pace.refuse": "Keel says no. %.1f kg in %d days is about %.2f kg/week. Safe max to %@ is ~%.2f kg/week. Earliest honest date: %@.",
    "onboarding.pace.lose": "lose",
    "onboarding.pace.gain": "gain",
    "onboarding.pace.move": "move",
    "onboarding.pace.later": "later",
    "onboarding.difficulty.male.0": "Difficulty: %@. Warm-up map. Keel will still notice if you coast.",
    "onboarding.difficulty.male.1": "Difficulty: %@. Real dungeon. Consistency is the loot.",
    "onboarding.difficulty.male.2": "Difficulty: %@. Act bosses every week. Miss a day and it bites.",
    "onboarding.difficulty.male.3": "Difficulty: %@. You asked for fire. Biology still holds the ceiling.",
    "onboarding.difficulty.male.4": "Difficulty: %@. Endgame pacing. Safe cap still wins over ego.",
    "onboarding.difficulty.female.0": "Difficulty: %@. Soft entry. Still show up for the plot.",
    "onboarding.difficulty.female.1": "Difficulty: %@. Camera on. Habits are the outfit.",
    "onboarding.difficulty.female.2": "Difficulty: %@. Glossy and demanding. Keel keeps the timeline honest.",
    "onboarding.difficulty.female.3": "Difficulty: %@. Chaotic good energy. Biology is the bodyguard.",
    "onboarding.difficulty.female.4": "Difficulty: %@. Full send fantasy. Safe weekly caps still rule.",
}

# locale -> key -> value. Every EN key must exist for every locale.
TR: dict[str, dict[str, str]] = {}


def L(locale: str, **rows: str) -> None:
    missing = set(EN) - set(rows)
    extra = set(rows) - set(EN)
    if missing or extra:
        raise SystemExit(f"{locale} missing={sorted(missing)[:8]} extra={sorted(extra)[:8]}")
    TR[locale] = rows


def unit(value: str) -> dict:
    return {"stringUnit": {"state": "translated", "value": value}}


def main() -> None:
    cat = json.loads(XC.read_text(encoding="utf-8"))
    strings = cat.setdefault("strings", {})
    for key, en in EN.items():
        entry = strings.setdefault(key, {})
        locs = entry.setdefault("localizations", {})
        locs["en"] = unit(en)
        for loc in LOCALES:
            locs[loc] = unit(TR[loc][key])
        entry.pop("extractionState", None)
    XC.write_text(json.dumps(cat, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {len(EN)} onboarding keys × {len(LOCALES)} locales into {XC}")


# Translations are loaded from sibling JSON so this file stays valid Python.
_DATA = Path(__file__).with_name("onboarding_l10n.json")


def load_tr() -> None:
    raw = json.loads(_DATA.read_text(encoding="utf-8"))
    for loc in LOCALES:
        L(loc, **raw[loc])


if __name__ == "__main__":
    load_tr()
    main()
