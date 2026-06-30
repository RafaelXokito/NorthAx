"""Tests for structured workout generation + intervals.icu text rendering."""
from app.engines.workouts import build_workout, to_intervals_text, workout_to_dict


def _text(domain, title, intensity, duration, mode):
    return to_intervals_text(workout_to_dict(build_workout(domain, title, intensity, duration, mode)))


def test_cycling_hr_default_intervals():
    w = build_workout("Cycling", "Zone 3 Intervals", "Threshold", 75, "hr")
    assert w.target_mode == "hr"
    txt = to_intervals_text(workout_to_dict(w))
    assert "5x" in txt                      # (75 - 20) // 10 = 5 reps
    assert "- Work 8m Z4 HR" in txt
    assert "- Recovery 2m Z1 HR" in txt
    assert "- Warm-up 10m Z1 HR" in txt


def test_cycling_power_mode_uses_power_zones():
    txt = _text("Cycling", "Zone 3 Intervals", "Threshold", 75, "power")
    assert "Z4 HR" not in txt
    assert "- Work 8m Z4" in txt            # power zones have no suffix


def test_running_is_pace():
    w = build_workout("Running", "Easy Run", "Easy", 45, "hr")  # cycling_target ignored for run
    assert w.target_mode == "pace"
    txt = to_intervals_text(workout_to_dict(w))
    assert "Z2 Pace" in txt
    assert "Steady" in txt


def test_running_tempo_structure():
    txt = _text("Running", "Tempo Run", "Hard", 40, "hr")
    assert "- Tempo" in txt and "Z4 Pace" in txt


def test_strength_has_no_structured_target():
    w = build_workout("Strength", "Push Day", "Moderate", 60, "hr")
    assert w.target_mode == "none"
    d = workout_to_dict(w)
    assert d["blocks"][0]["steps"][0]["icu"] == ""
    # a duration-only step, no zone token
    assert to_intervals_text(d).strip() == "- Session 60m"
