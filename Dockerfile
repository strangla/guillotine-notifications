FROM ghcr.io/astral-sh/uv:python3.13-bookworm-slim
WORKDIR /app
COPY pyproject.toml ./
RUN uv sync --no-dev
COPY src ./src
COPY migrations ./migrations
COPY scripts ./scripts
ARG GIT_SHA=unknown
ENV PATH="/app/.venv/bin:$PATH" PYTHONPATH=/app/src SOURCE_SHA=$GIT_SHA
CMD ["uvicorn","notifications_service.main:app","--host","0.0.0.0","--port","8010"]
