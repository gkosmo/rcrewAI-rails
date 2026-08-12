# Observation Engine Design

**Date:** 2026-08-12
**Status:** Approved for planning
**Repos affected:** `rcrewai-rails` (primary), `rcrewAI` (upstream fix)

## Problem

`ExecutionLog` records execution as a flat list of `level` / `message` / `details` rows. It renders,
but it cannot answer the questions that matter:

- What did each agent actually do, and where did it break? (debugging)
- What did this run cost, and which agent or model was slow? (cost and performance)
- What is the crew doing right now? (live monitoring)

The raw material already exists. `RCrewAI::Events` emits iterations, tool calls, token usage with
`cost_usd`, text deltas, and errors. `CrewExecutionJob#stream_sink_for` flattens all of it into
strings, discarding the structure.

There is also a wiring bug upstream. `Crew#execute` builds `@stream_sink` (`crew.rb:66`) and never
passes it to `Agent#execute_task`, which accepts a `stream:` argument and forwards it to the runner
as `event_sink`. Both halves of the plumbing exist; they are not connected. Until they are, no
agent-level events reach the Rails engine at all.

## Goals

1. **Debugging** — inspect one run in full detail: per agent, per LLM call, per tool call.
2. **Cost and performance** — aggregate across runs: spend, tokens, latency, error rates.
3. **Live monitoring** — watch a run assemble in real time in the dashboard.

All three read one substrate: a span tree. They differ only in how they read it — deeply (1),
aggregated (2), or as it arrives (3).

## Non-goals for v1

- OpenTelemetry export. The schema stays OTel-mappable; the adapter comes later.
- Evaluation and scoring (guardrail outcomes, human feedback, run-to-run quality comparison).
- Cross-run diffing.
- Sampling. When enabled, every run is traced.

## Architecture

Three layers, each testable in isolation.

```
rcrewai events ──> Capture ──> Storage ──> Read models ──> Dashboard
                 (Collector)   (spans)     (rollups)
```

### 1. Capture

A single sink passed to `crew.execute(stream:)`, as the job does today. No monkey-patching, no
wrapping of builders. The collector translates a flat event stream into a tree and is the only
layer that knows rcrewai's event shape — if that vocabulary changes, nothing else moves.

Tree construction uses a stack keyed by `(agent, iteration)`, available on every event via
`Events::BASE_ATTRS`:

| Event | Action |
|---|---|
| `IterationStart` | Open an `llm_call` span, child of the current agent span |
| `IterationEnd` | Close it, recording `finish_reason` |
| `ToolCallStart` | Open a `tool_call` span |
| `ToolCallResult` / `ToolCallError` | Close the matching span, correlated by `call_id` |
| `Usage` | Attach tokens and cost to the enclosing `llm_call`; bump execution rollups |
| `Error` | Mark the current span errored |
| `TextDelta` | Accumulate in memory; broadcast live. Never one row per delta. |
| `TextDone` / `Thinking` | Persist final text onto the enclosing `llm_call` span |

Correlation uses `call_id` rather than event ordering, which stays correct when tool calls
interleave.

`agent` and `task` spans have no corresponding events — there is no `AgentStart`. The engine opens
those itself around its own task dispatch, where the `Task` record is in hand. They become the
parents that `llm_call` and `tool_call` spans nest under.

**Resilience.** Observation must never break execution. `Events.fan_out` already rescues per sink;
the collector applies the same rule internally. A failed span write is logged and dropped, never
raised.

**Concurrency.** `Crew#execute_tasks_async` runs agents on threads, so the collector must be
thread-safe and deliberate about ActiveRecord connection handling from a long-running job. This is
the likeliest source of subtle bugs and needs explicit attention during implementation.

### 2. Storage

**`rcrewai_spans`** — the trace tree:

| Column | Notes |
|---|---|
| `execution_id`, `parent_span_id`, `trace_id` | Tree structure |
| `kind` | `crew` / `agent` / `task` / `llm_call` / `tool_call` |
| `name`, `status` | `status`: `running` / `ok` / `error` |
| `started_at`, `ended_at`, `duration_ms` | Timing |
| `prompt_tokens`, `completion_tokens`, `total_tokens`, `cost_usd` | Nullable; `llm_call` only |
| `attributes` (JSON) | Kind-specific: model, tool args, prompts, error details |
| `sequence` | Monotonic per execution — timestamps collide at sub-ms resolution |

**`rcrewai_span_events`** — point-in-time occurrences inside a span that are not themselves spans:
retries, guardrail rejections, log lines. Current `ExecutionLog` semantics survive here.

The fixed-`kind` / open-`attributes` split is deliberate: five kinds keep queries fast and the UI
predictable, while `attributes` absorbs future rcrewai additions without a migration. Columns for
what you aggregate on; JSON for what you display.

**`ExecutionLog` is deprecated, not removed**, for one minor version. It is a public surface in a
released gem and `execution.log(...)` is called in `CrewExecutionJob` today.

### 3. Read models

Walking the span tree per dashboard load will not survive real traffic. `Execution` carries
denormalized `total_cost_usd`, `total_tokens`, `span_count`, and `error_count`, updated as spans
close. The tree is the source of truth; rollups are a cache with a rebuild path.

## Presentation

Three surfaces in the existing engine dashboard, following current controller and view conventions.

- **Trace view** (goal 1) — waterfall for one execution. Nested spans indented by depth, each with
  duration bar, status, and tokens/cost. Expanding a span reveals `attributes`: prompt, tool args,
  backtrace. The primary debugging surface and the one worth design effort.
- **Cost and performance** (goal 2) — trends across executions: cost per run, tokens by model,
  slowest agents, tool error rates. Reads rollups only; never walks the span tree.
- **Live view** (goal 3) — the trace view with a Turbo Stream subscription. Spans appear as they
  open and fill in as they close, with `TextDelta` streaming into the active `llm_call`. The **same
  component** as the trace view, not a parallel implementation, so the two cannot drift.

## Configuration

Added to the existing `Configuration` object. Defaults are safe and cheap.

| Setting | Default | Purpose |
|---|---|---|
| `observation.enabled` | `true` | Master switch; off means no spans written, zero overhead |
| `observation.capture_prompts` | `:truncated` | `:none` / `:truncated` / `:full` — the PII and size lever |
| `observation.prompt_max_bytes` | (cap) | Truncation limit |
| `observation.flush_mode` | `:batched` | `:batched` or `:immediate` for live-first |
| `observation.retention_days` | (set) | Paired with a `rcrewai:observation:prune` rake task |

**Write strategy.** One DB write per event means hundreds of tiny inserts on the execution's
critical path. Batched buffering is the default; `:immediate` favours liveness. A hard crash loses
the buffer tail — acceptable for telemetry, and the tree self-heals because unclosed spans remain
visibly `running`.

**Prompt storage.** Full prompts make debugging useful and are unbounded and often contain PII.
Truncated by default; full capture is opt-in.

**Retention.** A busy crew produces thousands of spans per run. Without pruning this becomes the
largest table in the host application's database.

## Upstream change (`rcrewAI`)

`Crew` must thread `@stream_sink` down to `Agent#execute_task`, including through
`execute_tasks_async`. Small change, but goals 1 and 3 are unreachable without it.

The gem is checked out locally at `/Users/gkosmo/code/gkosmo/rcrewAI` as a path dependency, so this
is not a blocked external dependency. It requires an upstream release, since published 0.7.0 lacks
the fix. **This is step one of implementation**; the Rails work builds on it.

## Testing

The layering is what makes this tractable — each layer tests without the others.

- **Collector** (heaviest coverage) — pure unit tests feeding synthetic `RCrewAI::Events` structs
  and asserting the resulting tree. No LLM, no network. Must cover malformed sequences: a
  `ToolCallResult` with no matching start, an execution dying mid-span, interleaved tool calls,
  concurrent agents.
- **Storage** — model specs for rollup math and pruning.
- **Upstream** — a spec in `rcrewAI` asserting a sink passed to `crew.execute` receives agent-level
  events. This is the regression test for the wiring bug.
- **Views** — request specs against a seeded span tree.

Existing suite is RSpec with factory_bot; this follows it.

## Risks

| Risk | Mitigation |
|---|---|
| Thread-safety and AR connections under `execute_tasks_async` | Explicit design during implementation; concurrency tests in collector suite |
| Span table growth | Retention config plus prune task, shipped in v1 |
| Write overhead on the execution path | Batched flushing by default |
| Prompt capture leaking PII | Truncated by default, full is opt-in |
| Upstream and engine versions drifting | Engine degrades to crew-level spans when agent events are absent |
