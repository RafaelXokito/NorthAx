"""Claude AI explanation layer (§8).

Transport: the **Hermes agent CLI** in one-shot mode (``hermes -z``) rather than
the Anthropic HTTP API. No API key is required — the host just needs an
authenticated ``hermes`` on PATH (``hermes login`` / ``hermes setup``). Function
signatures match what the routers expect, so the transport is local to this
module.

Hermes specifics:
- ``hermes -z PROMPT`` prints ONLY the final response text to stdout (errors go
  to stderr; stdout is empty on failure — so an empty stdout = failure).
- There is no ``--system-prompt`` flag, so the persona/system instructions are
  prepended to the prompt text.
- ``-z`` is non-streaming, so coach chat fetches the full reply and re-emits it
  as SSE deltas to preserve the §8.2 streaming contract.
- ``-m provider/model`` selects a model; empty → Hermes' configured default.

Per §8.5 the AI is best-effort: any failure or timeout returns ``None`` (or the
unmodified deterministic value). The coach stream raises AI_UNAVAILABLE so the
router can emit an error SSE event.
"""
from __future__ import annotations

import asyncio
import json
import logging
import shlex
from collections.abc import AsyncIterator

from ..config import settings
from ..engines.readiness import Metrics, ReadinessResult

log = logging.getLogger("northax.ai")

READINESS_SYSTEM = (
    "You are the NorthAx AI coach. Your role is to explain an athlete's daily readiness "
    "in plain, direct language. You never invent data — you only interpret the numbers "
    "provided. You are confident, concise, and science-literate. Maximum 3 sentences. "
    "Do not greet the user. Do not use bullet points. Start with the most important signal."
)

SESSION_SYSTEM = (
    "You are a terse athletic coach. Given the athlete's biometrics and the deterministic "
    "session recommendation, write one sentence (max 20 words) that explains why this "
    "specific session was chosen for today. Do not repeat the session name."
)

STRENGTH_SYSTEM = (
    "You are a strength and conditioning coach. Given a workout plan and the athlete's "
    "current readiness, write a rationale and any recovery warnings. "
    "Reply with ONLY a JSON object, no prose, no markdown fences, shaped exactly as: "
    '{"rationale": "<3-4 sentence paragraph>", "recoveryWarnings": ["<short sentence>", ...]}. '
    "recoveryWarnings is an empty array if there are none. "
    "Be specific about muscle groups and loading principles. No generic fitness advice."
)

COACH_SYSTEM_TEMPLATE = """You are the NorthAx AI coach — a calm, direct, science-backed athletic coach
embedded in a training OS. You have access to the athlete's real biometric data
and training history.

Athlete: {athlete_name}
Today's readiness: {score}/100 ({status})
HRV: {hrv} ms ({hrv_change_pct}% vs baseline)
Sleep last night: {sleep_duration} hrs (score {sleep_score}/100)
Training balance (TSB): {tsb}
Recent activities: {recent_activities}
This week's plan: {week_plan}

Rules:
- Be direct. Answer in 2–4 sentences unless the question requires more detail.
- Never invent biometric data. Only reference numbers provided above.
- If the user asks something outside your data, say so honestly.
- Recommend specific, actionable decisions — not generic advice.
- Never use bullet points in a conversational reply.
- Never start a sentence with "I"."""


# ── CLI invocation ───────────────────────────────────────────────────────────
def _build_args(model: str, full_prompt: str) -> list[str]:
    args = [settings.hermes_cli_path, "-z", full_prompt]
    if model:
        args += ["-m", model]
    if settings.hermes_provider:
        args += ["--provider", settings.hermes_provider]
    if settings.hermes_extra_args:
        args += shlex.split(settings.hermes_extra_args)
    return args


async def _run(model: str, system: str, prompt: str, timeout: float) -> str | None:
    """Run ``hermes -z`` once. Returns stripped stdout, or None on any failure.

    Hermes has no system-prompt flag, so the system instructions are prepended.
    On failure Hermes writes to stderr and leaves stdout empty (and may still
    exit 0), so an empty stdout is treated as failure.
    """
    full_prompt = f"{system}\n\n{prompt}"
    try:
        proc = await asyncio.create_subprocess_exec(
            *_build_args(model, full_prompt),
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
    except FileNotFoundError:
        log.warning("hermes CLI not found on PATH (%s)", settings.hermes_cli_path)
        return None
    try:
        out, err = await asyncio.wait_for(proc.communicate(), timeout=timeout)
    except asyncio.TimeoutError:
        proc.kill()
        log.warning("hermes CLI timed out after %ss", timeout)
        return None
    text = out.decode().strip()
    if not text:
        log.warning("hermes CLI produced no output: %s", err.decode()[:500])
        return None
    return text


def _extract_json(text: str) -> dict | None:
    """Parse a JSON object from model output, tolerating ``` fences / stray prose."""
    if not text:
        return None
    candidate = text.strip()
    if candidate.startswith("```"):
        candidate = candidate.strip("`")
        candidate = candidate[candidate.find("{") :]
    start, end = candidate.find("{"), candidate.rfind("}")
    if start == -1 or end == -1:
        return None
    try:
        return json.loads(candidate[start : end + 1])
    except json.JSONDecodeError:
        return None


def _hrv_change_pct(m: Metrics) -> int:
    return int(m.hrv_change * 100)


def _tsb(m: Metrics) -> int:
    return int(m.training_balance)


# ── 8.1 Readiness explanation (fast model, cached per day) ───────────────────
async def readiness_explanation(m: Metrics, result: ReadinessResult, now) -> dict | None:
    prompt = (
        f"Readiness score: {result.score}/100 ({result.status.value})\n"
        f"HRV: {m.hrv:g} ms (baseline {m.hrv_baseline:g} ms, change {_hrv_change_pct(m)}%)\n"
        f"Sleep: {m.sleep_duration:g} hrs, score {m.sleep_score}/100, sleep debt {m.sleep_debt:g} hrs\n"
        f"Training balance (TSB): {_tsb(m)} (ATL {m.acute_load:g}, CTL {m.chronic_load:g})\n"
        f"Resting HR: {m.resting_hr} bpm ({m.resting_hr_change:+d} vs baseline)\n\n"
        f"Explain why this athlete's readiness is {result.status.value} today."
    )
    narrative = await _run(
        settings.ai_model_fast, READINESS_SYSTEM, prompt, settings.ai_cli_fast_timeout
    )
    if not narrative:
        return None
    model_used = settings.ai_model_fast or "hermes-default"
    return {"narrative": narrative, "generatedAt": now.isoformat(), "model": model_used}


# ── 8.3 Session suggestion rationale (fast model) ────────────────────────────
async def session_rationale(m: Metrics, result: ReadinessResult) -> str | None:
    s = result.session
    prompt = (
        f"Readiness: {result.score}/100. Suggested: {s.title} ({s.intensity_label}, {s.duration} min).\n"
        f"HRV change: {_hrv_change_pct(m)}%. Sleep: {m.sleep_duration:g} hrs. TSB: {_tsb(m)}.\n"
        "Why is this the right session today?"
    )
    return await _run(settings.ai_model_fast, SESSION_SYSTEM, prompt, settings.ai_cli_fast_timeout)


# ── 8.4 Strength augmentation (fast model) ───────────────────────────────────
async def strength_augment(
    score: int, muscle_groups: list[str], exercise_list: str, recent_summary: str, recovery_map: str
) -> dict | None:
    prompt = (
        f"Today's readiness: {score}/100.\n"
        f"Muscle groups: {', '.join(muscle_groups)}.\n"
        f"Exercises:\n{exercise_list}\n"
        f"Recent strength activities: {recent_summary}\n"
        f"Hours since last worked each group: {recovery_map}"
    )
    raw = await _run(settings.ai_model_fast, STRENGTH_SYSTEM, prompt, settings.ai_cli_fast_timeout)
    parsed = _extract_json(raw or "")
    if not parsed or "rationale" not in parsed:
        return None
    parsed.setdefault("recoveryWarnings", [])
    return parsed


# ── 8.2 Coach chat (default model; SSE via post-hoc chunking) ────────────────
def _history_to_prompt(history: list[dict]) -> str:
    """Flatten the conversation into a single transcript prompt.

    ``hermes -z`` is single-shot, so prior turns are replayed as a transcript and
    the model is asked to produce the next coach reply.
    """
    lines = []
    for msg in history:
        speaker = "Athlete" if msg["role"] == "user" else "Coach"
        lines.append(f"{speaker}: {msg['content']}")
    lines.append("Coach:")
    return "\n".join(lines)


def _chunk(text: str, size: int = 24) -> list[str]:
    """Split text into small word-aligned chunks for SSE deltas."""
    words = text.split(" ")
    chunks, buf = [], ""
    for w in words:
        candidate = f"{buf} {w}".strip() if buf else w
        if len(candidate) >= size:
            chunks.append(candidate + " ")
            buf = ""
        else:
            buf = candidate
    if buf:
        chunks.append(buf)
    return chunks


async def coach_stream(system_prompt: str, history: list[dict]) -> AsyncIterator[str]:
    """Yield text deltas. Hermes one-shot is non-streaming, so the full reply is
    fetched then re-emitted as deltas. Raises AI_UNAVAILABLE if the call fails."""
    prompt = _history_to_prompt(history)
    full = await _run(
        settings.ai_model_default, system_prompt, prompt, settings.ai_cli_default_timeout
    )
    if not full:
        from ..errors import ai_unavailable

        raise ai_unavailable()
    for piece in _chunk(full):
        yield piece
