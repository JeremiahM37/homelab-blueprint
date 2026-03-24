# AI / ML Stack

Multiple dedicated LXC containers on a 128 GB RAM node for running local LLMs, ML research, AI experiments, and AI-powered automation.

---

## Architecture

```
AIServer (128 GB RAM, 32 cores, Ryzen AI MAX+ 395, Radeon 8060S iGPU)
│
├── LXC 102 — "openclaw" (28 GB — LLM Chat)
│   ├── Ollama (model serving, 2min idle timeout)
│   │   ├── qwen3.5:35b-a3b (23 GB, chat)
│   │   ├── qwen3:1.7b (1.4 GB, Discord bot intent parsing)
│   │   ├── nomic-embed-text (275 MB, document RAG embeddings)
│   │   └── qwen3:4b, qwen3:0.6b (available, not active)
│   ├── Open-WebUI (chat interface, port 8080)
│   └── MCP tools proxy (Proxmox management from chat)
│
├── LXC 105 — "research-env" (16 GB — ML Research)
│   ├── GPU passthrough (Radeon 8060S via ROCm)
│   ├── PyTorch 2.9.1 + ROCm 7.12 (native gfx1151)
│   └── Full scientific Python stack
│
├── LXC 106 — "ai-detector" (12 GB — AI Detection)
│   ├── GPU passthrough (shared iGPU)
│   └── DeBERTa fine-tuning for AI text detection
│
├── LXC 100 — "media-monitor" (8 GB — Health Agent)
│   ├── Ollama qwen2.5:7b (local reasoning)
│   └── Automated health check + auto-fix + torrent recovery
│
├── Host services:
│   ├── Homelab API (port 9105) — unified FastAPI aggregating all services
│   ├── Document RAG (port 9103) — vector search over Paperless docs
│   ├── Terraform status (port 9104) — IaC state API
│   └── Temp API (port 9101) — hardware sensor data
│
└── Discord Bot AI (runs on LXC 200, calls Ollama on LXC 102)
    └── *ai command — 30+ actions, sub-second intent parsing
```

### GPU Note (AMD 8060S iGPU)
- Only **2 GB VRAM** — models don't fit, weights stay in system RAM
- GPU used for compute (matrix ops), not weight storage
- System RAM used for weights **counts against LXC memory limit**
- VRAM is separate and **bypasses** container limits
- Shared across LXCs 102, 105, 106 via /dev/dri + /dev/kfd
- Not exclusive like RTX 2070 on pve (fully owned by VM 103)

---

## Local LLM Chat (LXC 102)

### Ollama

- Serves large language models locally
- Current model: `qwen3.5:35b-a3b` (23 GB, Q4_K_M quantization)
- API endpoint: `http://<lxc-ip>:11434`
- Runs as a systemd service (auto-start on boot)

### Open-WebUI

- ChatGPT-like web interface for Ollama
- Port 8080 (pip-installed, not Docker)
- Data stored at `/var/lib/open-webui/`
- Runs as a systemd service

### MCP Tools Proxy

Bridges Proxmox management tools into the chat interface:

```
Open-WebUI → mcpo proxy (port 8100 on AIServer host) → MCP Proxmox server → pvesh
```

This lets you manage VMs/containers from the chat UI ("start VM 103", "show cluster status").

### Memory Gotcha

Large models (35B+) need significant free RAM. Ollama checks `MemFree`, not `MemAvailable`. If you get "model requires more system memory":

```bash
# Drop filesystem caches to free RAM
sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'
# Then restart Ollama
sudo systemctl restart ollama
```

---

## ML Research (LXC 105)

### GPU Passthrough (AMD)

The Radeon 8060S (Strix Halo, gfx1151) is passed through to this container via `/dev/dri` and `/dev/kfd`.

- **ROCm**: SDK 7.12 (nightly, for gfx1151 support)
- **PyTorch**: Nightly build with native gfx1151 kernels
- **No HSA override needed** — native support in nightly wheels

```bash
# Install PyTorch with ROCm for gfx1151
pip install torch --index-url https://rocm.nightlies.amd.com/v2/gfx1151/
```

### Stack

- Python 3.11 with full scientific stack (numpy, scipy, pandas, matplotlib, scikit-learn)
- PyTorch 2.9+ with ROCm 7.12
- Triton 3.5+ for kernel compilation
- 48 GB RAM, 32 vCPUs

---

---

## Media Monitor Agent (LXC 100)

An autonomous health monitoring agent that:

1. Runs periodic health checks on all Docker services (every 5 minutes)
2. Uses a small local LLM to reason about failures and suggest fixes
3. Executes safe remediation actions (restart containers, fix permissions)
4. Logs all actions to a SQLite audit database
5. Sends Discord notifications for significant events

### Architecture

```
systemd timer (5min)
  └── monitor.py
        ├── HTTP probes (all services)
        ├── Docker health checks (via SSH to LXC 200)
        ├── Rule-based pre-LLM fixes (known patterns)
        ├── LLM reasoning (for unknown failures)
        └── Action execution + audit log
```

### Optimizations

- Only sends failing checks to the LLM (not all 59 probes)
- `num_ctx=8192` for sufficient context
- Fallback summary mode if LLM is unavailable
- Rule-based fixes for known issues (e.g., dead network namespace → restart gluetun)
