# CLI Coding Agent to Self-Hosted vLLM

Goal: Install a terminal-based AI coding assistant on RHEL 9 that points at a
self-hosted model running in a vLLM container, then use it to refactor existing
Argo code from GitLab for RHOAI.

---

## TL;DR — Recommended Stack

| Layer | Choice | Why |
|-------|--------|-----|
| Model server | vLLM container (already running) | OpenAI-compatible `/v1` API out of the box |
| CLI agent | **Aider** | Git-native, proven vLLM integration, atomic commits |
| Runner-up | **OpenCode** | More stars, provider-agnostic, Claude Code-like UX |
| Python | 3.12 from AppStream | Aider requires >= 3.9; 3.12 is safest |

---

## 1. Prerequisites on RHEL 9

### Python 3.12

RHEL 9 ships Python 3.9 by default. Aider works on 3.9+ but 3.12 is
recommended for the best dependency compatibility.

```bash
# Install Python 3.12 from AppStream
sudo dnf install python3.12 python3.12-pip python3.12-devel

# Verify
python3.12 --version
```

### Git (required — Aider treats git as the system of record)

```bash
sudo dnf install git
git --version   # RHEL 9 ships 2.39+, which is fine
```

---

## 2. Confirm vLLM Endpoint

Your vLLM container should already expose an OpenAI-compatible API. Verify:

```bash
# Replace with your actual vLLM host:port
export VLLM_HOST="http://your-vllm-host:8000"

# List available models
curl -s ${VLLM_HOST}/v1/models | python3.12 -m json.tool

# Quick smoke test (replace MODEL_NAME with what /v1/models returned)
curl -s ${VLLM_HOST}/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "MODEL_NAME",
    "messages": [{"role": "user", "content": "Say hello"}],
    "max_tokens": 50
  }' | python3.12 -m json.tool
```

Take note of the model name returned — you'll need it below.

### Critical: Enable tool calling for agent workflows

If you plan to use an agent-style CLI (OpenCode, OpenHands) that relies on
function/tool calling, vLLM must be started with these flags:

```bash
# Without these, tool-call syntax comes back as plain text and the agent
# loop never advances
vllm serve YOUR_MODEL \
  --enable-auto-tool-choice \
  --tool-call-parser hermes    # or: qwen3_coder, mistral, llama3_json
```

The `--tool-call-parser` value depends on the model family. Common mappings:

| Model family | Parser value |
|-------------|-------------|
| Qwen 2.5/3 Coder | `qwen3_coder` |
| Hermes-format models | `hermes` |
| Mistral/Devstral | `mistral` |
| Llama 3.x | `llama3_json` |

Aider does **not** need tool calling — it parses model output as text diffs.
OpenCode and OpenHands **do** need it.

---

## 3. Install Aider

```bash
# Create a virtualenv so we don't pollute the system Python
python3.12 -m venv ~/aider-venv
source ~/aider-venv/bin/activate

# Install aider
pip install aider-chat

# Verify
aider --version
```

### Optional: make it available everywhere

```bash
# Symlink into ~/.local/bin (already on PATH for most RHEL 9 users)
mkdir -p ~/.local/bin
ln -sf ~/aider-venv/bin/aider ~/.local/bin/aider
```

---

## 4. Configure Aider to Talk to vLLM

### Environment variables (simplest)

Add to `~/.bashrc` or a project `.env` file:

```bash
# Point at your vLLM endpoint
export OPENAI_API_BASE="http://your-vllm-host:8000/v1"

# vLLM doesn't require a real key but the client library insists on one
export OPENAI_API_KEY="not-needed"
```

### Per-project config: `.aider.conf.yml`

Drop this in your repo root for project-specific defaults:

```yaml
# .aider.conf.yml
openai-api-base: http://your-vllm-host:8000/v1
openai-api-key: not-needed

# Use the model name from /v1/models
model: openai/YOUR_MODEL_NAME

# For code refactoring, the "diff" edit format often works better
# with open-weight models than the default "whole" format
edit-format: diff

# Auto-commit each change (Aider's killer feature for safe refactoring)
auto-commits: true
```

### Model name format

Aider uses the prefix `openai/` to route through the OpenAI-compatible
provider. So if vLLM serves a model called `Qwen/Qwen2.5-Coder-32B-Instruct`,
you tell Aider:

```
--model openai/Qwen/Qwen2.5-Coder-32B-Instruct
```

---

## 5. Clone the Argo Code and Start Refactoring

```bash
# Clone from GitLab
git clone https://gitlab.example.com/your-org/argo-project.git
cd argo-project

# Launch Aider with the vLLM model
aider \
  --openai-api-base http://your-vllm-host:8000/v1 \
  --openai-api-key not-needed \
  --model openai/YOUR_MODEL_NAME

# Or if you set up .aider.conf.yml above, just:
aider
```

### Common refactoring workflows

```
# Add specific files to the chat context
> /add src/controllers/workflow.go src/controllers/dag.go

# Ask for a refactoring
> Refactor the DAG execution logic to support the new RHOAI reconciler
> interface. Keep the existing Argo workflow CRD contract intact.

# Review what changed (Aider auto-commits, so you can always diff)
> /diff

# Undo the last change if it's wrong
> /undo

# Add more files as needed
> /add src/api/types.go

# Run tests to verify
> /run make test
```

### Tips for working with self-hosted models

- **Keep context small**: Add 1-3 files at a time, not the whole repo.
  Open-weight models have smaller effective context than frontier models.
- **Use `diff` edit format**: Set `edit-format: diff` in config. The
  `whole` format (rewriting entire files) burns tokens and increases
  error rates on smaller models.
- **Be specific**: "Change function X to accept parameter Y and update
  all callers in this file" works better than vague instructions.
- **Iterate in small steps**: One refactoring per prompt. Review, commit,
  then move to the next change.

---

## 6. Recommended Models for Code Refactoring

These are the best open-weight coding models to serve via vLLM as of late 2026:

| Model | Size | Min GPU RAM | Notes |
|-------|------|-------------|-------|
| Qwen2.5-Coder-32B-Instruct | 32B | ~40 GB | Best open-weight coding model for its size |
| DeepSeek-Coder-V2-Instruct | 236B (MoE) | ~80 GB | Strong but heavy |
| Devstral-Small-24B | 24B | ~24 GB | Good balance of quality/speed |
| CodeLlama-34B-Instruct | 34B | ~40 GB | Older but well-tested |

For refactoring Argo/Go code specifically, Qwen2.5-Coder-32B is the strongest
option that fits on a single GPU.

---

## 7. Alternative CLI Tools

If Aider doesn't fit your workflow, these also support vLLM's
OpenAI-compatible API:

### OpenCode (Recommended if you want a Claude Code-like experience)

OpenCode is a terminal-first coding agent — not just a chat wrapper. It calls
tools (file reads, writes, shell commands, search), making it the closest
open-source equivalent to Claude Code.

```bash
# Install via npm (requires Node.js 18+)
npm install -g opencode

# Or via brew
brew install opencode

# Or via Go
go install github.com/opencode-ai/opencode@latest
```

Configure via `opencode.json` in your project root:

```json
{
  "provider": {
    "vllm": {
      "id": "vllm",
      "name": "vLLM Local",
      "type": "openai-compatible",
      "baseURL": "http://your-vllm-host:8000/v1",
      "apiKey": "sk-local",
      "models": {
        "YOUR_MODEL_NAME": {
          "id": "YOUR_MODEL_NAME",
          "name": "Local Coder",
          "limit": {
            "context": 32000,
            "output": 8000
          }
        }
      }
    }
  },
  "model": {
    "model": "YOUR_MODEL_NAME",
    "small_model": "YOUR_MODEL_NAME"
  }
}
```

**Important notes for OpenCode + vLLM:**

- vLLM must be started with `--enable-auto-tool-choice` and the matching
  `--tool-call-parser` (see section 2 above). Without these, tool calls
  come back as plain text and the agent loop stalls.
- Set `limit.context` conservatively — if you set the theoretical max, OpenCode
  will pack prompts the server then rejects mid-session.
- Give reasoning models a generous `limit.output`. Reasoning tokens count
  against max_tokens; a stingy limit causes truncation before the tool call
  is emitted.
- The model must reliably produce valid JSON tool calls. If it can't,
  OpenCode will error or hallucinate edits. Qwen3-Coder-30B+ models
  handle this well.

### Qwen Code

If you're running a Qwen model on vLLM, Qwen Code is optimized for it:

```bash
npm install -g qwen-code
# or
pip install qwen-code

# Point at vLLM
export OPENAI_API_BASE="http://your-vllm-host:8000/v1"
qwen-code
```

### OpenHands

More of a full agent platform (sandboxed execution, web browsing):

```bash
pip install openhands
# or
uvx openhands

# Configure via its web UI or config file to point at vLLM
```

Best for well-scoped tasks: "add test coverage," "migrate this function."

---

## 8. Troubleshooting

### "Connection refused" to vLLM

```bash
# Check the container is running
podman ps | grep vllm

# Check the port is exposed
ss -tuln | grep 8000

# If running in a pod, ensure port-forward or host network is set
```

### Model returns garbage / malformed diffs

- Try `edit-format: whole` instead of `diff` — some models don't follow
  diff format reliably
- Switch to a larger or code-specialized model
- Reduce context: fewer files in the chat

### Aider "model not found" error

The model name must match exactly what vLLM's `/v1/models` endpoint returns,
prefixed with `openai/`:

```bash
# Get the exact name
curl -s http://your-vllm-host:8000/v1/models | jq '.data[].id'

# Use it with the openai/ prefix
aider --model openai/$(curl -s http://your-vllm-host:8000/v1/models | jq -r '.data[0].id')
```

### Python / pip issues on RHEL 9

```bash
# If python3.12 isn't available, check AppStream
sudo dnf module list python3

# Alternative: use python3.11
sudo dnf install python3.11 python3.11-pip
python3.11 -m venv ~/aider-venv
```

---

## References

### CLI Tools
- [Aider — AI Pair Programming in Your Terminal](https://aider.chat/)
- [Aider: OpenAI-Compatible APIs docs](https://aider.chat/docs/llms/openai-compat.html)
- [OpenCode + vLLM end-to-end guide](https://cefboud.com/posts/coding-agent-self-hosted-llm-opencode-vllm/)
- [Configure Local LLM with OpenCode](https://dev.to/tobrun/configure-local-llm-with-opencode-1gdb)
- [Open Source CLI Coding Agents comparison (2026)](https://pinggy.io/blog/best_open_source_cli_coding_agents/)

### vLLM / Model Serving
- [vLLM Documentation](https://docs.vllm.ai/)
- [vLLM OpenAI-Compatible Server](https://docs.vllm.ai/en/latest/serving/openai_compatible_server/)
- [Self-Hosted OpenAI-Compatible API with vLLM](https://www.spheron.network/blog/openai-compatible-api-self-hosted/)

### Red Hat
- [Red Hat AI Inference Server — vLLM Server Arguments](https://access.redhat.com/documentation/en-us/red_hat_ai_inference_server/3.1/html-single/vllm_server_arguments/index)
- [Red Hat OpenShift AI — Configuring Model Serving](https://access.redhat.com/documentation/en-us/red_hat_openshift_ai_self-managed/3.5/html-single/configuring_your_model-serving_platform/index)

### RHEL 9 Python
- [Install multiple Python versions on RHEL](https://developers.redhat.com/blog/install-python3-rhel)
