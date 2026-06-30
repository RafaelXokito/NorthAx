"""Structured workout generation.

Turns a planned session (domain, title, intensity, duration) into structured
steps with **relative** targets — zones / %FTP / %LTHR / pace — so intervals.icu
resolves them against the athlete's own settings when it syncs to Garmin.

Target mode:
- Cycling → user preference ("hr" default, or "power")
- Running / Swimming → "pace"
- Strength / Mobility / Recovery → "none" (no structured targets)

The intervals.icu text form (see `to_intervals_text`) uses their workout-builder
syntax: `Nx` for repeats, `- <cue> <minutes>m <target>` per step, where target is
e.g. `Z2 HR`, `Z4` (power zone), or `Z2 Pace`.
"""
from __future__ import annotations

from dataclasses import dataclass, field

_ZONE_DESC = {1: "recovery", 2: "endurance", 3: "tempo", 4: "threshold", 5: "VO2max"}
WARMUP = 10  # minutes for harder sessions


@dataclass
class Step:
    cue: str
    minutes: int
    target: str  # human label, e.g. "Z2 endurance (HR)"
    icu: str     # intervals.icu token, e.g. "Z2 HR" ("" = no target)


@dataclass
class Block:
    repeat: int          # 1 = a single pass of `steps`
    steps: list[Step] = field(default_factory=list)


@dataclass
class StructuredWorkout:
    target_mode: str     # "hr" | "power" | "pace" | "none"
    blocks: list[Block] = field(default_factory=list)


def mode_for(domain: str, cycling_target: str) -> str:
    if domain == "Cycling":
        return cycling_target if cycling_target in ("hr", "power") else "hr"
    if domain in ("Running", "Swimming"):
        return "pace"
    return "none"


def _suffix(mode: str) -> str:
    return {"hr": " HR", "power": "", "pace": " Pace"}.get(mode, "")


def _token(zone: int, mode: str) -> str:
    return f"Z{zone}{_suffix(mode)}"


def _label(zone: int, mode: str) -> str:
    unit = {"hr": "HR", "power": "power", "pace": "pace"}.get(mode, "")
    base = f"Z{zone} {_ZONE_DESC.get(zone, '')}".strip()
    return f"{base} ({unit})" if unit else base


def _step(cue: str, minutes: int, zone: int, mode: str) -> Step:
    return Step(cue=cue, minutes=minutes, target=_label(zone, mode), icu=_token(zone, mode))


def build_workout(domain: str, title: str, intensity_label: str, duration_min: int, cycling_target: str) -> StructuredWorkout:
    mode = mode_for(domain, cycling_target)
    if mode == "none":
        return StructuredWorkout(mode, [Block(1, [Step("Session", duration_min, intensity_label, "")])])

    il = intensity_label.lower()
    t = title.lower()

    if "interval" in t:
        work, rec = 8, 2
        body = max(work + rec, duration_min - 2 * WARMUP)
        reps = max(1, body // (work + rec))
        return StructuredWorkout(mode, [
            Block(1, [_step("Warm-up", WARMUP, 1, mode)]),
            Block(reps, [_step("Work", work, 4, mode), _step("Recovery", rec, 1, mode)]),
            Block(1, [_step("Cool-down", WARMUP, 1, mode)]),
        ])

    if "tempo" in t or il in ("hard", "threshold"):
        body = max(5, duration_min - 2 * WARMUP)
        return StructuredWorkout(mode, [
            Block(1, [_step("Warm-up", WARMUP, 1, mode)]),
            Block(1, [_step("Tempo", body, 4, mode)]),
            Block(1, [_step("Cool-down", WARMUP, 1, mode)]),
        ])

    # Steady endurance / easy / recovery. "Easy" aerobic work is Z2; only very
    # easy or recovery rides drop to Z1.
    zone = 1 if (il in ("very easy", "minimal") or "recovery" in t) else 2
    wu = 5 if duration_min <= 60 else WARMUP
    body = max(5, duration_min - 2 * wu)
    return StructuredWorkout(mode, [
        Block(1, [_step("Warm-up", wu, 1, mode)]),
        Block(1, [_step("Steady", body, zone, mode)]),
        Block(1, [_step("Cool-down", wu, 1, mode)]),
    ])


def workout_to_dict(w: StructuredWorkout) -> dict:
    return {
        "targetMode": w.target_mode,
        "blocks": [
            {"repeat": b.repeat,
             "steps": [{"cue": s.cue, "minutes": s.minutes, "target": s.target, "icu": s.icu} for s in b.steps]}
            for b in w.blocks
        ],
    }


def to_intervals_text(workout: dict) -> str:
    """Render a workout dict to intervals.icu workout-builder text."""
    lines: list[str] = []
    for block in workout.get("blocks", []):
        rep = int(block.get("repeat", 1))
        steps = block.get("steps", [])
        if rep > 1:
            lines.append(f"{rep}x")
        for s in steps:
            cue = (s.get("cue") or "").strip()
            tok = (s.get("icu") or "").strip()
            minutes = int(s.get("minutes", 0))
            seg = "- " + (f"{cue} " if cue else "") + f"{minutes}m" + (f" {tok}" if tok else "")
            lines.append(seg)
    return "\n".join(lines)
