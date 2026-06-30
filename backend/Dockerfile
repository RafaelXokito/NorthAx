FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY pyproject.toml ./
RUN pip install --upgrade pip && pip install .

COPY . .

# NOTE: the AI layer shells out to the Hermes agent CLI (`hermes -z`). For AI
# features in a container, install and authenticate the `hermes` CLI in this
# image and provide credentials at runtime (`hermes login`). Without it, AI
# calls degrade gracefully (deterministic results are returned without an
# aiExplanation, per §8.5).

EXPOSE 8080

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
