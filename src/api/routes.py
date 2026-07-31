import logging
import json
import time
import uuid
import os
from datetime import datetime
from fastapi import FastAPI
from src.agent.graph import app_workflow

app = FastAPI(title="Intelligent Rescue Dispatch Assistant")
logger = logging.getLogger(__name__)

class RequestLogger:
    def __init__(self, log_file: str = "logs/requests.log"):
        self.log_file = log_file

    def log(self, request_id: str, req: dict, resp: dict, latency: float, tokens: int, cost: float):
        entry = {
            "timestamp": datetime.utcnow().isoformat(),
            "request_id": request_id,
            "request": req,
            "response": resp,
            "latency_ms": latency * 1000,
            "tokens": tokens,
            "estimated_cost": cost,
            "model": "gemma-4-12b",
            "environment": os.getenv("ENV", "development")
        }
        with open(self.log_file, "a") as f:
            f.write(json.dumps(entry) + "\n")

request_logger = RequestLogger()

@app.post("/dispatch")
async def handle_dispatch(incident: str, location: str):
    request_id = str(uuid.uuid4())[:8]
    start = time.time()
    try:
        result = app_workflow.invoke({"incident": incident, "location": location, "session_id": request_id})
        latency = time.time() - start
        request_logger.log(
            request_id,
            {"incident": incident, "location": location},
            result,
            latency,
            result.get("token_usage", {}).get("total_tokens", 0),
            result.get("token_usage", {}).get("estimated_cost", 0)
        )
        return {
            "request_id": request_id,
            "response": result["response"],
            "latency_ms": int(latency * 1000),
            "confidence": result.get("confidence", 0.7)
        }
    except Exception as e:
        logger.error(f"Request {request_id} failed: {e}")
        return {"error": str(e)}

@app.get("/health")
async def health():
    return {"status": "healthy"}

@app.get("/metrics")
async def metrics():
    try:
        with open("logs/requests.log", "r") as f:
            lines = f.readlines()[-100:]
        latency = [json.loads(line)["latency_ms"] for line in lines]
        return {
            "total_requests": len(lines),
            "avg_latency_ms": sum(latency) / len(latency) if latency else 0,
            "p95_latency_ms": sorted(latency)[int(len(latency) * 0.95)] if latency else 0
        }
    except:
        return {"total_requests": 0}
