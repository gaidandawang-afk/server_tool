---
name: test-service
description: Execute a source-branch test contract and preserve evidence for every outcome.
---

# Test Service

Use this skill to run a concrete service test against the branch selected by the task profile.

## Contract

Each test is expressed by:

- `TEST.md`: goal, applicable branch, topology, phases, barriers, signals, pass/fail gates and required artifacts.
- `run.sh`: mechanical setup, launch, requests, fault injection, collection and targeted cleanup.

## Rules

1. Locate the exact test contract in the selected source branch before execution.
2. Do not replace the requested scenario with a nearby test.
3. Verify source HEAD, shared environment, selected GPU and port range.
4. Parallelize only independent work inside the same phase.
5. Preserve causal barriers between baseline, fault, recovery and validation stages.
6. Save each parallel request's response and error independently before aggregation.
7. Bound every readiness, request and outer test wait.
8. Preserve output and provenance on both success and failure.

Task-local exploratory tests go under ignored `work/<profile>/<task>/`. Stable behavioral
contracts must be promoted to the corresponding source repository, not centralized here.
