"""Deterministic training engines.

These are a faithful, line-by-line port of the iOS Swift engines
(ReadinessEngine.swift, PlanEngine.swift, StrengthEngine.swift). The client
engines are the source of truth: given identical inputs, these must produce
identical outputs (§1). Tests in tests/ pin the reference values.
"""
