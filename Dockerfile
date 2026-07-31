FROM python:3.11-slim as builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --user -r requirements.txt

FROM python:3.11-slim
WORKDIR /app
COPY --from=builder /root/.local /root/.local
COPY src/ src/
COPY evals/ evals/
COPY data/ data/
COPY logs/ logs/
ENV PATH=/root/.local/bin:$PATH

HEALTHCHECK --interval=30s --timeout=3s \
  CMD curl -f http://localhost:8000/health || exit 1

CMD ["uvicorn", "src.api.routes:app", "--host", "0.0.0.0", "--port", "8000"]
