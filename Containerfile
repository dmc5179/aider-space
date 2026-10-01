## ------------------------------------------------------------------
## Stage 1 — build: compile aider and its C-extension dependencies
## ------------------------------------------------------------------
FROM registry.access.redhat.com/ubi9/ubi:latest AS builder

ARG PYTHON_VERSION=3.12

RUN dnf install -y --nodocs --setopt=install_weak_deps=False \
        python${PYTHON_VERSION} \
        python${PYTHON_VERSION}-pip \
        python${PYTHON_VERSION}-devel \
        gcc \
        gcc-c++ \
    && dnf clean all \
    && rm -rf /var/cache/dnf

RUN python${PYTHON_VERSION} -m venv /opt/aider-venv \
    && /opt/aider-venv/bin/pip install --no-cache-dir --upgrade pip \
    && /opt/aider-venv/bin/pip install --no-cache-dir aider-chat

## ------------------------------------------------------------------
## Stage 2 — runtime: minimal image with only what's needed to run
## ------------------------------------------------------------------
FROM registry.access.redhat.com/ubi9/ubi-minimal:latest

LABEL name="aider-vllm" \
      summary="Aider AI coding assistant pre-configured for vLLM endpoints" \
      description="UBI 9-based image with Aider installed, ready to connect \
to a self-hosted vLLM model for interactive code refactoring." \
      io.k8s.display-name="Aider + vLLM CLI" \
      maintainer="danclark@redhat.com"

ARG PYTHON_VERSION=3.12

RUN microdnf install -y --nodocs --setopt=install_weak_deps=False \
        python${PYTHON_VERSION} \
        python${PYTHON_VERSION}-libs \
        git-core \
        jq \
        curl-minimal \
        shadow-utils \
        findutils \
    && microdnf clean all \
    && rm -rf /var/cache/yum

COPY --from=builder /opt/aider-venv /opt/aider-venv

ENV PATH="/opt/aider-venv/bin:${PATH}" \
    OPENAI_API_BASE="http://localhost:8000/v1" \
    OPENAI_API_KEY="not-needed" \
    AIDER_EDIT_FORMAT="diff" \
    AIDER_AUTO_COMMITS="true" \
    AIDER_MAP_TOKENS="1024"

WORKDIR /work

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

RUN useradd -m -u 1000 aider \
    && chown -R 1000:0 /opt/aider-venv \
    && chmod -R g=u /opt/aider-venv
USER 1000

ENTRYPOINT ["entrypoint.sh"]
CMD ["bash"]
