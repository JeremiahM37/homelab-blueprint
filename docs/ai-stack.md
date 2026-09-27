# AI / ML Stack

Local inference, service tools, shared context and coding-agent workspaces.
The interactive Homelab API and proactive Homelab Agent are separate services.

## Placement

| Component | Where | Purpose |
|-----------|-------|---------|
| Ollama + Open WebUI | LXC 102 | GPU-accelerated local models and chat |
| Homelab API | AIServer, 9105 | Tool loop, React PWA, service integrations |
| Homelab Agent | LXC 100, 9106 | Monitoring, repair and failure memory |
| Doc RAG | AIServer, 9103 | Retrieval over documents, services and configuration |
| Grimoire | AIServer, 9111 | Notes, shared context, memory and credential grants |
| Lectern | AIServer, 9110 / TLS 8443 | Coding-agent sessions, tasks, reviews and workshop |
| Agent Desk | LXC 107 | Persistent shared Chromium and virtual desktop |
| Research workspace | LXC 105 | ROCm/PyTorch and inference experiments |

The Radeon 8060S is shared through `/dev/dri` and `/dev/kfd`. Its unified-memory
GTT is useful for models larger than dedicated VRAM. LXC RAM limits remain hard
caps; allocation to one guest affects the memory available to others.

## Interactive agent

```text
PWA / Homepage / restricted Discord surface
  → Homelab API
  → select relevant tools
  → local model tool call
  → service API result
  → repeat within budget
  → response or a real coding-agent handoff
```

Tools cover media, books, downloads, documents, recipes, inventory, photos,
monitoring, notes and diagnostics. Per-surface allowlists keep personal notes
and administrative actions off shared surfaces.

The public `homelab-ai` package is a generalization. It is not the private
Homelab Agent binary/service running in LXC 100.

### Context and tool selection

Client `num_ctx` overrides Ollama's server default. The earlier 4,096-token
window was largely occupied before the user spoke: system instructions and
tool schemas crowded out results and conversation. Interactive context is now
centralized rather than copied into each call site.

Tool selection prioritizes required delegation, specific keyword matches and
semantic similarity before generic core tools. Adding every schema is not a
substitute for giving the model the right tools within its context budget.

Compact JSON results reduce overhead. Empty-field pruning and table conversion
are optional modes; a single noisy eval run cannot establish a small quality
change. Descriptions remain readable because tool choice depends on them.

### Tool-call recovery and delegation

Some local model responses contain textual function syntax instead of structured
tool calls. The API recovers calls only for tools actually offered in that turn.
Untrusted retrieved text is fenced and function-like syntax defanged so it
cannot be mistaken for an authorized call.

An action promise must correspond to an actual dispatch. The API's delegation
fallback creates the real session and uses its returned link; prompting the
model to invent a better-looking answer is not sufficient. Use dry-run mode
when testing delegation without spawning work.

### Memory, observability and sandboxing

- Episodic summaries provide relevant conversation context across sessions.
- LLM traces record latency, tokens, tool calls and errors.
- The code sandbox uses filesystem/network isolation and resource/time limits.
- Grimoire supplies note search, retrieval, explicitly recorded memory and exact
  facts. Fact recall and whole-vault search are different operations.

## Local models

The deployed configuration uses a small Qwen model for intent/fast tools, a
larger Qwen MoE for interactive tools and repair, Gemma for chat, and an embedding
model for retrieval. September's configured family is `qwen3.5:4b`,
`qwen3.6:35b-a3b`, `gemma4:e4b` and `nomic-embed-text`.

Confirm with `ollama list` and the service environment before choosing a model
or quoting a version. Model residency has a power cost as well as a memory cost:
keep-alive is five minutes in the operational configuration, not an hour.

Ollama is deliberately pinned to the tested 0.20.x line. Later versions tested
here regressed tool calling with `think: false`, even when a tiny smoke test
passed. Compare the real tool prompt and outcome suite before upgrading.
The tested MTP model loaded prediction tensors without using them, so its name
was not evidence of acceleration.

## Proactive monitoring and repair

The seven-module Homelab Agent in LXC 100 scans on a five-minute cycle.
Failures escalate through:

1. Small-model calls to bounded repair tools.
2. A larger fixer with file backups, command tools and an audit log.
3. Coding-agent review of unresolved failures and earlier changes.

The second tier's proposed fix is checked independently. Failed validation
must not be reported as successful repair. Failure memory and notification
deduplication prevent retry/alert loops.

## Grimoire and Doc RAG

**Grimoire** owns the Markdown vault, note UI, retrieval, shared agent context
and credential grants. It replaced SilverBullet in August. The notes vault
syncs to mobile; credential values are not written into notes. Exact facts,
explicit memories and retrieved passages have different provenance.

**Doc RAG** indexes Paperless, git, Compose, homelab documentation, service
catalogs, Proxmox, project metadata, notes and inventory. It uses embeddings,
keyword retrieval and reranking with source visibility tiers. Its browser Q&A
page is `/chat` on port 9103; the root is API metadata.

`/api/status` returns `docs` and `chunks`. Those values change as indexing runs;
widgets must read the actual schema rather than embed a dated count. Discord
retrieval is restricted to public-tier sources.

## Coding agents and shared browser

Lectern coordinates sessions, review and approvals. Its direct TLS listener
uses Tailscale identity and distinguishes the user's device from local agent
processes; agents cannot approve their own work. The autonomous workshop has a
separate daily record and usage/storage limits.

Agent Desk gives agents one persistent browser with the user's sessions and a
visible desktop. Agents open their own tabs, preserve the user's tabs, and hand
back logins or interactive approval steps when needed.

## Evaluation

Old “10/10” scores came from a small historical prompt set, not a general
reliability guarantee. The capability harness runs the real agent against a
simulated homelab and grades resulting state, effects and answer facts.

- Report safety violations separately from task success.
- Compare models/profiles over at least three repeated runs.
- Do not change a scenario because a model failed it; record genuine premise or
  grading corrections.
- Avoid the old evaluator that wrote synthetic prompts into production memory.
- Hold the shared GPU research lease for timed model comparisons.

No benchmark is run as part of a dashboard refresh. Browser/link checks and
model capability tests answer different questions.

## Mobile frontend

The PWA is React/TypeScript under `homelab-api/frontend/src/`. Its Home,
Services, Files, Media, Books, AI, Feed, Work, Jobs, System and Term views share
existing APIs. Publishing from `frontend/` stamps the service-worker cache.
A root-scoped service worker and trusted HTTPS origin are required for install
and the multipart share target.

See [Dashboard](dashboard.md), [Networking](networking.md), and
[Monitoring](monitoring.md) for browser and operational details.
