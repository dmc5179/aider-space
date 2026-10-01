#!/bin/bash
set -euo pipefail

# If VLLM_ENDPOINT is set (e.g. from DevWorkspace env or podman -e),
# use it to override OPENAI_API_BASE
if [[ -n "${VLLM_ENDPOINT:-}" ]]; then
    VLLM_ENDPOINT="${VLLM_ENDPOINT%/}"
    export OPENAI_API_BASE="${VLLM_ENDPOINT}/v1"
fi

# If VLLM_MODEL is set, create the aider-vllm alias
if [[ -n "${VLLM_MODEL:-}" ]]; then
    alias aider-vllm="aider --model openai/${VLLM_MODEL}"
    echo "alias aider-vllm='aider --model openai/${VLLM_MODEL}'" >> "${HOME}/.bashrc" 2>/dev/null || true
fi

# Probe the vLLM endpoint for available models (best-effort)
if curl -sf --connect-timeout 3 "${OPENAI_API_BASE}/models" >/dev/null 2>&1; then
    MODELS=$(curl -sf "${OPENAI_API_BASE}/models" | jq -r '.data[].id' 2>/dev/null || true)
    if [[ -n "${MODELS}" ]]; then
        echo "Connected to vLLM at ${OPENAI_API_BASE}"
        echo "Available models:"
        echo "${MODELS}" | sed 's/^/  - /'
        echo ""

        if [[ -z "${VLLM_MODEL:-}" ]]; then
            MODEL_COUNT=$(echo "${MODELS}" | wc -l)
            if [[ "${MODEL_COUNT}" -eq 1 ]]; then
                export VLLM_MODEL="${MODELS}"
                alias aider-vllm="aider --model openai/${VLLM_MODEL}"
                echo "alias aider-vllm='aider --model openai/${VLLM_MODEL}'" >> "${HOME}/.bashrc" 2>/dev/null || true
                echo "Auto-selected model: ${VLLM_MODEL}"
            else
                echo "Set VLLM_MODEL to one of the above, or run:"
                echo "  aider --model openai/<model-name>"
            fi
        fi

        echo "Quick start:  aider-vllm"
        echo ""
    fi
else
    echo "WARNING: Cannot reach vLLM at ${OPENAI_API_BASE}"
    echo "Set VLLM_ENDPOINT or OPENAI_API_BASE to the correct URL."
    echo ""
fi

exec "$@"
