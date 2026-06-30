"""Parity tests for the readiness engine against TrainingMetrics.swift mock data."""
from app.engines import readiness as engine
from app.engines.readiness import Metrics, Status


def mock_fresh() -> Metrics:
    return Metrics(
        hrv=58, hrv_baseline=54, hrv_trend=[51, 49, 52, 54, 53, 56, 58],
        resting_hr=46, resting_hr_baseline=47,
        sleep_duration=7.5, sleep_score=84, rem_sleep=1.8, deep_sleep=1.4, sleep_debt=0.3,
        acute_load=68, chronic_load=72, today_load=0, weekly_load_change=0.08, body_weight=78.2,
    )


def mock_fatigued() -> Metrics:
    return Metrics(
        hrv=42, hrv_baseline=54, hrv_trend=[54, 53, 51, 48, 45, 43, 42],
        resting_hr=54, resting_hr_baseline=47,
        sleep_duration=5.8, sleep_score=58, rem_sleep=1.0, deep_sleep=0.8, sleep_debt=3.2,
        acute_load=98, chronic_load=72, today_load=0, weekly_load_change=0.28, body_weight=78.8,
    )


def test_fresh_scores():
    r = engine.calculate(mock_fresh())
    assert r.hrv_score == 81
    assert r.sleep_score == 87
    assert r.load_score == 100
    assert r.recovery_score == 89
    assert r.score == 88
    assert r.status == Status.peak
    assert r.session.domain.value == "Cycling"
    assert r.session.title == "Zone 3 Intervals"


def test_fatigued_scores():
    r = engine.calculate(mock_fatigued())
    assert r.hrv_score == 21
    assert r.sleep_score == 49
    assert r.load_score == 42
    assert r.recovery_score == 37
    assert r.score == 37
    assert r.status == Status.low


def test_status_thresholds():
    assert engine.status_for_score(85) == Status.peak
    assert engine.status_for_score(84) == Status.high
    assert engine.status_for_score(70) == Status.high
    assert engine.status_for_score(69) == Status.moderate
    assert engine.status_for_score(55) == Status.moderate
    assert engine.status_for_score(54) == Status.low
    assert engine.status_for_score(35) == Status.low
    assert engine.status_for_score(34) == Status.rest


def test_insights_shape():
    r = engine.calculate(mock_fresh())
    labels = [i.label for i in r.key_insights]
    assert labels == ["HRV", "Sleep", "Load", "Resting HR"]
