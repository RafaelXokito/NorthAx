"""Unit tests for the §8.5 AI-vs-deterministic contradiction guardrail."""
from app.services.ai import check_contradiction


def test_no_narrative_no_contradiction():
    assert check_contradiction(None, 78) is False
    assert check_contradiction("", 78) is False


def test_matching_score_is_not_a_contradiction():
    assert check_contradiction("Your readiness is 78/100 today.", 78) is False
    # within tolerance
    assert check_contradiction("Around 80/100 — solid.", 78) is False


def test_contradicting_score_detected():
    assert check_contradiction("You're at a peak 95/100.", 78) is True
    assert check_contradiction("Readiness 42/100 — rest.", 78) is True


def test_no_score_mentioned():
    assert check_contradiction("Your HRV is above baseline; train well.", 78) is False
