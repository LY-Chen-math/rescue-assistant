# ============================================================
# ROOT FILES
# ============================================================

cat > README.md << 'README_EOF'
# Intelligent Rescue Dispatch Assistant

## Problem Statement
In emergency rescue scenarios, dispatchers must make rapid resource allocation decisions under high pressure. This system reduces the incident-to-dispatch process from an average of **3-5 minutes to under 30 seconds** using AI assistance.

## Technology Stack
- **Model**: Gemma 4 12B (GGUF) via llama.cpp
- **Agent Framework**: LangGraph
- **API**: FastAPI
- **Containerization**: Docker + docker-compose
- **CI/CD**: GitHub Actions
- **Cloud Platforms**: Alibaba Cloud → AWS (cross-cloud migration)

## Quick Start
```bash
make install
make run
make test
make eval
```

## Architecture
```
User Input → FastAPI → LangGraph Agent → Gemma 4 → Dispatch Decision
                              ↓
                        Memory / Skills
```

## Business Alignment
This project addresses The AA's "van of the future" strategy by providing a data-driven, AI-powered dispatch layer that sits on top of their connectivity infrastructure.

## License
MIT
README_EOF

cat > Makefile << 'MAKEFILE_EOF'
.PHONY: install test eval run test-api docker-up deploy-aliyun deploy-aws optimize

install:
	pip install -r requirements.txt

test:
	pytest tests/ -v --cov=src --cov-report=html

eval:
	python evals/merge_sources.py
	python evals/runner.py

run:
	uvicorn src.api.routes:app --reload --host 0.0.0.0 --port 8000

test-api:
	curl -X POST http://localhost:8000/dispatch \
	  -H "Content-Type: application/json" \
	  -d '{"incident": "Zone A, car accident", "location": "Zone A"}'

docker-up:
	docker-compose up -d

deploy-aliyun:
	@echo "Deploying to Alibaba Cloud..."
	scp -r . aliyun-ecs:~/rescue-assistant/
	ssh aliyun-ecs "cd ~/rescue-assistant && docker-compose up -d"

deploy-aws:
	@echo "Deploying to AWS..."
	terraform apply -auto-approve

optimize:
	python -c "from src.self_optimization.optimizer import optimizer; optimizer._optimize_once()"
MAKEFILE_EOF

cat > requirements.txt << 'REQ_EOF'
fastapi==0.115.0
uvicorn==0.30.0
langchain==0.3.0
langgraph==0.2.0
langchain-ollama==0.1.0
pytest==8.0.0
pytest-cov==5.0.0
httpx==0.27.0
pydantic==2.5.0
python-dotenv==1.0.0
sentence-transformers==2.2.2
pandas==2.0.0
REQ_EOF

cat > .env.example << 'ENV_EOF'
ENV=development
MODEL_ENDPOINT=http://localhost:18080
LOG_LEVEL=INFO
ENV_EOF

cat > Dockerfile << 'DOCKER_EOF'
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
DOCKER_EOF

cat > docker-compose.yml << 'COMPOSE_EOF'
version: '3.8'
services:
  api:
    build: .
    ports:
      - "8000:8000"
    environment:
      - ENV=production
      - MODEL_ENDPOINT=http://gemma4:18080
    volumes:
      - ./logs:/app/logs
      - ./data:/app/data
    depends_on:
      - gemma4

  gemma4:
    image: ghcr.io/ggml-org/llama.cpp:server
    command:
      - --hf-repo unsloth/gemma-4-12b-it-GGUF
      - --hf-file gemma-4-12b-it-Q8_0.gguf
      - --host 0.0.0.0
      - --port 18080
      - --ctx-size 131072
    ports:
      - "18080:18080"
    volumes:
      - ./models:/models
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
COMPOSE_EOF

# ============================================================
# src/agent/
# ============================================================

cat > src/agent/__init__.py << 'AGENT_INIT_EOF'
from .graph import app_workflow
from .state import AgentState

__all__ = ["app_workflow", "AgentState"]
AGENT_INIT_EOF

cat > src/agent/state.py << 'STATE_EOF'
from typing import TypedDict, Optional, List, Dict

class TokenUsage(TypedDict):
    prompt_tokens: int
    completion_tokens: int
    total_tokens: int
    estimated_cost: float

class AgentState(TypedDict):
    # Input
    incident: str
    location: str

    # Processing
    severity: Optional[str]
    incident_type: Optional[str]
    extracted_entities: Optional[Dict]

    # Decision
    dispatch_decision: Optional[Dict]
    candidate_resources: Optional[List]
    selected_resource: Optional[str]

    # Output
    response: Optional[str]
    confidence: Optional[float]

    # Observability
    token_usage: Optional[TokenUsage]
    latency_ms: Optional[int]
    error: Optional[str]

    # Self-optimization
    session_id: Optional[str]
    feedback: Optional[Dict]
STATE_EOF

cat > src/agent/graph.py << 'GRAPH_EOF'
import logging
from typing import Literal
from langchain_ollama import ChatOllama
from langgraph.graph import StateGraph, END

from .state import AgentState
from .nodes import analyze_incident, plan_dispatch, execute_dispatch, generate_response
from ..tools.dispatch import get_available_resources, dispatch_resource, get_traffic_status

logger = logging.getLogger(__name__)

llm = ChatOllama(
    model="unsloth/gemma-4-12b-it-GGUF",
    temperature=0,
    base_url="http://localhost:18080",
    model_kwargs={"options": {"enable_thinking": True}}
)

tools = [get_available_resources, dispatch_resource, get_traffic_status]
llm_with_tools = llm.bind_tools(tools)

def should_continue(state: AgentState) -> Literal["execute", "respond"]:
    if state.get("error") or state.get("confidence", 1.0) < 0.3:
        return "respond"
    if state.get("dispatch_decision", {}).get("needs_dispatch"):
        return "execute"
    return "respond"

workflow = StateGraph(AgentState)
workflow.add_node("analyze", analyze_incident)
workflow.add_node("plan", plan_dispatch)
workflow.add_node("execute", execute_dispatch)
workflow.add_node("respond", generate_response)

workflow.set_entry_point("analyze")
workflow.add_edge("analyze", "plan")
workflow.add_conditional_edges("plan", should_continue, {
    "execute": "execute",
    "respond": "respond"
})
workflow.add_edge("execute", "respond")
workflow.add_edge("respond", END)

app_workflow = workflow.compile()
GRAPH_EOF

cat > src/agent/nodes.py << 'NODES_EOF'
import logging
import time
import json
from .state import AgentState
from ..tools.dispatch import get_available_resources, dispatch_resource
from ..self_optimization.memory import get_memory

logger = logging.getLogger(__name__)

def analyze_incident(state: AgentState):
    start_time = time.time()
    prompt = f"""You are a highway emergency dispatch agent. Analyze:

User report: {state['incident']}
Location: {state['location']}

Output JSON:
{{
    "severity": "low/medium/high/emergency",
    "incident_type": "accident/flat_tire/fire/out_of_gas/other",
    "confidence": 0-1
}}
"""
    try:
        from .graph import llm_with_tools
        memory = get_memory()
        similar = memory.find_similar(state['incident'], limit=3)
        if similar:
            prompt = f"Reference similar cases:\n{json.dumps(similar)}\n" + prompt

        response = llm_with_tools.invoke(prompt)
        analysis = json.loads(response.content)
        state["severity"] = analysis.get("severity", "medium")
        state["incident_type"] = analysis.get("incident_type", "other")
        state["confidence"] = analysis.get("confidence", 0.7)
        state["latency_ms"] = int((time.time() - start_time) * 1000)
    except Exception as e:
        logger.error(f"Analysis failed: {e}")
        state["error"] = str(e)
        state["severity"] = "medium"
        state["confidence"] = 0.3
    return state

def plan_dispatch(state: AgentState):
    severity = state.get("severity", "medium")
    needs = {"emergency": ["ambulance", "fire_truck", "tow_truck"],
             "high": ["ambulance", "tow_truck"],
             "medium": ["tow_truck"],
             "low": []}
    required = needs.get(severity, [])
    available = []
    for rt in required:
        available.extend(get_available_resources(state['location'], rt))
    if not available and required:
        state["error"] = f"No resources in {state['location']}"
        state["dispatch_decision"] = {"needs_dispatch": False}
    else:
        state["dispatch_decision"] = {"needs_dispatch": len(available) > 0,
                                      "required_types": required,
                                      "available_resources": available}
        state["candidate_resources"] = available
    return state

def execute_dispatch(state: AgentState):
    if not state.get("dispatch_decision", {}).get("needs_dispatch"):
        return state
    candidates = state.get("candidate_resources", [])
    if not candidates:
        return state
    best = sorted(candidates, key=lambda x: x["eta"])[0]
    result = dispatch_resource(state['location'], best["id"], state['location'])
    state["selected_resource"] = best["id"]
    state["dispatch_result"] = result
    return state

def generate_response(state: AgentState):
    if state.get("error"):
        state["response"] = f"Error: {state['error']}. Please escalate."
    elif state.get("dispatch_result", {}).get("success"):
        state["response"] = state["dispatch_result"]["message"]
    elif state.get("dispatch_decision", {}).get("needs_dispatch") is False:
        state["response"] = f"No dispatch needed for {state['location']}."
    else:
        state["response"] = "Dispatching..."
    return state
NODES_EOF

cat > src/agent/memory.py << 'MEMORY_EOF'
import json
import hashlib
from typing import List, Dict
from datetime import datetime

class DispatchMemory:
    def __init__(self, path: str = "data/memory.json"):
        self.path = path
        self.success_cases = []
        self.failure_cases = []
        self._load()

    def _load(self):
        try:
            with open(self.path) as f:
                d = json.load(f)
                self.success_cases = d.get("success", [])
                self.failure_cases = d.get("failure", [])
        except:
            pass

    def _save(self):
        with open(self.path, "w") as f:
            json.dump({"success": self.success_cases, "failure": self.failure_cases}, f, indent=2)

    def record(self, incident: str, decision: Dict, result: Dict, feedback: Dict, success: bool):
        entry = {
            "id": hashlib.md5(f"{incident}{datetime.utcnow().isoformat()}".encode()).hexdigest()[:8],
            "timestamp": datetime.utcnow().isoformat(),
            "incident": incident,
            "decision": decision,
            "result": result,
            "feedback": feedback
        }
        if success:
            self.success_cases.append(entry)
            if len(self.success_cases) > 200:
                self.success_cases = self.success_cases[-200:]
        else:
            self.failure_cases.append(entry)
            if len(self.failure_cases) > 100:
                self.failure_cases = self.failure_cases[-100:]
        self._save()

    def find_similar(self, incident: str, limit: int = 3) -> List[Dict]:
        words = set(incident.lower().split())
        scored = []
        for case in self.success_cases:
            cw = set(case["incident"].lower().split())
            score = len(words & cw) / len(words | cw) if words else 0
            scored.append((score, case))
        scored.sort(key=lambda x: x[0], reverse=True)
        return [case for _, case in scored[:limit]]

    def analyze_failure_patterns(self) -> List[Dict]:
        patterns = {}
        for case in self.failure_cases:
            key = case.get("decision", {}).get("severity", "unknown")
            patterns[key] = patterns.get(key, 0) + 1
        return [{"pattern": k, "count": v, "percentage": v / len(self.failure_cases)} for k, v in patterns.items()] if self.failure_cases else []

_memory = None

def get_memory() -> DispatchMemory:
    global _memory
    if _memory is None:
        _memory = DispatchMemory()
    return _memory
MEMORY_EOF

# ============================================================
# src/tools/
# ============================================================

cat > src/tools/__init__.py << 'TOOLS_INIT_EOF'
from .dispatch import get_available_resources, dispatch_resource, get_traffic_status

__all__ = ["get_available_resources", "dispatch_resource", "get_traffic_status"]
TOOLS_INIT_EOF

cat > src/tools/dispatch.py << 'DISPATCH_EOF'
import random
from typing import List, Dict

RESOURCES_DB = {
    "Zone A": [
        {"id": "V101", "type": "ambulance", "status": "idle", "eta": 5},
        {"id": "V102", "type": "ambulance", "status": "busy", "eta": 20},
        {"id": "T201", "type": "tow_truck", "status": "idle", "eta": 8},
        {"id": "T202", "type": "tow_truck", "status": "idle", "eta": 12},
    ],
    "Zone B": [
        {"id": "V103", "type": "ambulance", "status": "idle", "eta": 3},
        {"id": "T203", "type": "tow_truck", "status": "busy", "eta": 25},
        {"id": "F301", "type": "fire_truck", "status": "idle", "eta": 10},
    ],
    "Zone C": [
        {"id": "V104", "type": "ambulance", "status": "idle", "eta": 7},
        {"id": "T204", "type": "tow_truck", "status": "idle", "eta": 4},
        {"id": "T205", "type": "tow_truck", "status": "idle", "eta": 9},
        {"id": "F302", "type": "fire_truck", "status": "idle", "eta": 15},
    ]
}

def get_available_resources(zone: str, resource_type: str = None) -> List[Dict]:
    resources = RESOURCES_DB.get(zone, [])
    available = [r for r in resources if r["status"] == "idle"]
    if resource_type:
        available = [r for r in available if r["type"] == resource_type]
    return available

def dispatch_resource(zone: str, resource_id: str, location: str) -> Dict:
    resources = RESOURCES_DB.get(zone, [])
    resource = next((r for r in resources if r["id"] == resource_id), None)
    if not resource:
        return {"success": False, "error": f"Resource {resource_id} not found"}
    if resource["status"] != "idle":
        return {"success": False, "error": f"Resource {resource_id} unavailable"}
    resource["status"] = "busy"
    return {
        "success": True,
        "resource_id": resource_id,
        "resource_type": resource["type"],
        "location": location,
        "eta": resource["eta"],
        "message": f"Dispatched {resource['type']} {resource_id} to {location}, ETA {resource['eta']}min"
    }

def get_traffic_status(road: str) -> Dict:
    statuses = ["clear", "light_congestion", "moderate_congestion", "heavy_congestion"]
    return {"road": road, "status": random.choice(statuses), "timestamp": "2026-07-30T10:00:00Z"}
DISPATCH_EOF

# ============================================================
# src/api/
# ============================================================

cat > src/api/__init__.py << 'API_INIT_EOF'
from .routes import app

__all__ = ["app"]
API_INIT_EOF

cat > src/api/routes.py << 'ROUTES_EOF'
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
ROUTES_EOF

# ============================================================
# src/self_optimization/
# ============================================================

cat > src/self_optimization/__init__.py << 'SELF_INIT_EOF'
from .memory import get_memory, DispatchMemory
from .reflector import run_reflection_cycle
from .skills import SkillCrystallizer
from .optimizer import AutoOptimizer, optimizer, start_optimization

__all__ = ["get_memory", "DispatchMemory", "run_reflection_cycle", "SkillCrystallizer", "AutoOptimizer", "optimizer", "start_optimization"]
SELF_INIT_EOF

cat > src/self_optimization/memory.py << 'SELF_MEMORY_EOF'
import json
import hashlib
from typing import List, Dict
from datetime import datetime

class DispatchMemory:
    def __init__(self, path: str = "data/memory.json"):
        self.path = path
        self.success_cases = []
        self.failure_cases = []
        self._load()

    def _load(self):
        try:
            with open(self.path) as f:
                d = json.load(f)
                self.success_cases = d.get("success", [])
                self.failure_cases = d.get("failure", [])
        except:
            pass

    def _save(self):
        with open(self.path, "w") as f:
            json.dump({"success": self.success_cases, "failure": self.failure_cases}, f, indent=2)

    def record(self, incident: str, decision: Dict, result: Dict, feedback: Dict, success: bool):
        entry = {
            "id": hashlib.md5(f"{incident}{datetime.utcnow().isoformat()}".encode()).hexdigest()[:8],
            "timestamp": datetime.utcnow().isoformat(),
            "incident": incident,
            "decision": decision,
            "result": result,
            "feedback": feedback
        }
        if success:
            self.success_cases.append(entry)
            if len(self.success_cases) > 200:
                self.success_cases = self.success_cases[-200:]
        else:
            self.failure_cases.append(entry)
            if len(self.failure_cases) > 100:
                self.failure_cases = self.failure_cases[-100:]
        self._save()

    def find_similar(self, incident: str, limit: int = 3) -> List[Dict]:
        words = set(incident.lower().split())
        scored = []
        for case in self.success_cases:
            cw = set(case["incident"].lower().split())
            score = len(words & cw) / len(words | cw) if words else 0
            scored.append((score, case))
        scored.sort(key=lambda x: x[0], reverse=True)
        return [case for _, case in scored[:limit]]

    def analyze_failure_patterns(self) -> List[Dict]:
        patterns = {}
        for case in self.failure_cases:
            key = case.get("decision", {}).get("severity", "unknown")
            patterns[key] = patterns.get(key, 0) + 1
        return [{"pattern": k, "count": v, "percentage": v / len(self.failure_cases)} for k, v in patterns.items()] if self.failure_cases else []

_memory = None

def get_memory() -> DispatchMemory:
    global _memory
    if _memory is None:
        _memory = DispatchMemory()
    return _memory
SELF_MEMORY_EOF

cat > src/self_optimization/reflector.py << 'REFLECTOR_EOF'
import json
import time
from datetime import datetime
from langchain_ollama import ChatOllama
from .memory import get_memory

llm = ChatOllama(
    model="unsloth/gemma-4-12b-it-GGUF",
    temperature=0.3,
    base_url="http://localhost:18080"
)

def run_reflection_cycle() -> Dict:
    memory = get_memory()
    failures = memory.failure_cases[-20:]
    if len(failures) < 5:
        return {"status": "skipped", "reason": "Insufficient failures"}

    summary = "\n".join([f"- {f['incident']} | severity: {f.get('decision',{}).get('severity')}" for f in failures])
    prompt = f"""Analyze these dispatch failures and output JSON:
    Failures: {summary}
    Output: {{"patterns": [...], "root_causes": [...], "improvement_suggestions": [...]}}
    """
    try:
        response = llm.invoke(prompt)
        analysis = json.loads(response.content)
        analysis["timestamp"] = datetime.utcnow().isoformat()
        analysis["failures_analyzed"] = len(failures)
        return analysis
    except Exception as e:
        return {"status": "error", "error": str(e)}
REFLECTOR_EOF

cat > src/self_optimization/skills.py << 'SKILLS_EOF'
import json
import hashlib
from typing import List, Dict
from datetime import datetime

class SkillCrystallizer:
    def __init__(self, storage_path: str = "data/skills.json"):
        self.path = storage_path
        self.skills = self._load()

    def _load(self) -> List[Dict]:
        try:
            with open(self.path) as f:
                return json.load(f)
        except:
            return []

    def _save(self):
        with open(self.path, "w") as f:
            json.dump(self.skills, f, indent=2)

    def crystallize(self, cases: List[Dict]) -> List[Dict]:
        groups = {}
        for case in cases:
            itype = case.get("decision", {}).get("incident_type", "other")
            groups.setdefault(itype, []).append(case)

        new_skills = []
        for itype, group in groups.items():
            if len(group) < 3:
                continue
            resources = {}
            for case in group:
                for r in case.get("decision", {}).get("required_types", []):
                    resources[r] = resources.get(r, 0) + 1
            skill = {
                "id": hashlib.md5(f"{itype}{datetime.utcnow().isoformat()}".encode()).hexdigest()[:8],
                "name": f"{itype} dispatch template",
                "incident_type": itype,
                "required_resources": [r for r, c in resources.items() if c >= len(group) * 0.6],
                "success_rate": len([g for g in group if g.get("feedback", {}).get("success", True)]) / len(group),
                "usage_count": 0,
                "created_at": datetime.utcnow().isoformat()
            }
            new_skills.append(skill)
        self.skills.extend(new_skills)
        self._save()
        return new_skills
SKILLS_EOF

cat > src/self_optimization/optimizer.py << 'OPTIMIZER_EOF'
import json
import time
import threading
from .memory import get_memory
from .reflector import run_reflection_cycle
from .skills import SkillCrystallizer

class AutoOptimizer:
    def __init__(self, interval_minutes: int = 60):
        self.interval = interval_minutes
        self.memory = get_memory()
        self.skill_crystallizer = SkillCrystallizer()
        self.is_running = False

    def start(self):
        self.is_running = True
        threading.Thread(target=self._run_loop, daemon=True).start()
        print(f"Auto-optimization started, interval {self.interval} minutes")

    def _run_loop(self):
        while self.is_running:
            try:
                self._optimize_once()
            except Exception as e:
                print(f"Optimization error: {e}")
            time.sleep(self.interval * 60)

    def _optimize_once(self):
        print(f"[{time.ctime()}] Starting optimization cycle...")
        reflection = run_reflection_cycle()
        if reflection.get("status") != "error" and reflection.get("status") != "skipped":
            with open("data/improvements.log", "a") as f:
                f.write(json.dumps({"timestamp": time.ctime(), "reflection": reflection}) + "\n")
        if len(self.memory.success_cases) > 20:
            self.skill_crystallizer.crystallize(self.memory.success_cases[-20:])
        report = {
            "timestamp": time.ctime(),
            "total_memory": len(self.memory.success_cases),
            "failure_count": len(self.memory.failure_cases),
            "skill_count": len(self.skill_crystallizer.skills)
        }
        with open("data/optimization_report.json", "w") as f:
            json.dump(report, f, indent=2)
        print(f"[{time.ctime()}] Optimization cycle complete")

optimizer = AutoOptimizer(interval_minutes=60)

def start_optimization():
    optimizer.start()
OPTIMIZER_EOF

# ============================================================
# tests/
# ============================================================

cat > tests/unit/__init__.py << 'TEST_UNIT_INIT_EOF'
# Unit tests
TEST_UNIT_INIT_EOF

cat > tests/unit/test_tools.py << 'TEST_TOOLS_EOF'
import pytest
from src.tools.dispatch import get_available_resources, dispatch_resource

def test_get_available_resources():
    resources = get_available_resources("Zone A")
    assert len(resources) > 0
    assert all(r["status"] == "idle" for r in resources)

def test_dispatch_resource_success():
    result = dispatch_resource("Zone A", "V101", "Zone A")
    assert result["success"] is True

def test_dispatch_resource_not_available():
    result = dispatch_resource("Zone A", "V102", "Zone A")
    assert result["success"] is False
TEST_TOOLS_EOF

cat > tests/integration/__init__.py << 'TEST_INT_INIT_EOF'
# Integration tests
TEST_INT_INIT_EOF

cat > tests/integration/test_agent.py << 'TEST_AGENT_EOF'
import pytest
from src.agent.graph import app_workflow

def test_full_dispatch_flow():
    result = app_workflow.invoke({
        "incident": "Zone A, car accident, two injured",
        "location": "Zone A"
    })
    assert result["response"] is not None
    assert "dispatch" in result["response"].lower() or "arrive" in result["response"].lower()

def test_low_severity_no_dispatch():
    result = app_workflow.invoke({
        "incident": "Is there a gas station nearby?",
        "location": "Zone A"
    })
    assert result.get("dispatch_decision", {}).get("needs_dispatch") is False
TEST_AGENT_EOF

# ============================================================
# evals/
# ============================================================

cat > evals/test_cases.json << 'EVAL_JSON_EOF'
[
    {
        "id": "eval_001",
        "category": "normal",
        "incident": "Zone A, serious car accident, two injured",
        "location": "Zone A",
        "expected": {
            "severity": "high",
            "needs_dispatch": true,
            "resource_type": "ambulance"
        }
    },
    {
        "id": "eval_002",
        "category": "normal",
        "incident": "My car has a flat tire on the highway",
        "location": "Zone B",
        "expected": {
            "severity": "medium",
            "needs_dispatch": true,
            "resource_type": "tow_truck"
        }
    },
    {
        "id": "eval_003",
        "category": "edge",
        "incident": "Vehicle on fire with smoke in Zone A",
        "location": "Zone A",
        "expected": {
            "severity": "emergency",
            "needs_dispatch": true,
            "resource_type": "fire_truck"
        }
    },
    {
        "id": "eval_004",
        "category": "out_of_scope",
        "incident": "Is there a gas station nearby?",
        "location": "Zone A",
        "expected": {
            "severity": "low",
            "needs_dispatch": false
        }
    }
]
EVAL_JSON_EOF

cat > evals/runner.py << 'EVAL_RUNNER_EOF'
import json
import time
from datetime import datetime
from typing import Dict

class Evaluator:
    def __init__(self, agent, test_cases_path: str = "evals/test_cases.json"):
        self.agent = agent
        with open(test_cases_path) as f:
            self.test_cases = json.load(f)

    def run(self) -> Dict:
        results = {"timestamp": datetime.utcnow().isoformat(), "total": len(self.test_cases),
                   "passed": 0, "failed": [], "by_category": {}, "latency": []}
        for case in self.test_cases:
            cat = case.get("category", "unknown")
            results["by_category"].setdefault(cat, {"passed": 0, "total": 0})
            results["by_category"][cat]["total"] += 1
            start = time.time()
            try:
                result = self.agent.invoke({"incident": case["incident"], "location": case["location"]})
                latency = time.time() - start
                results["latency"].append(latency)
                passed = self._verify(result, case["expected"])
                if passed:
                    results["passed"] += 1
                    results["by_category"][cat]["passed"] += 1
                else:
                    results["failed"].append({"id": case["id"], "reason": "Verification failed"})
            except Exception as e:
                results["failed"].append({"id": case["id"], "error": str(e)})
        return results

    def _verify(self, result: Dict, expected: Dict) -> bool:
        checks = []
        if "severity" in expected:
            checks.append(result.get("severity") == expected["severity"])
        if "needs_dispatch" in expected:
            checks.append(result.get("dispatch_decision", {}).get("needs_dispatch", False) == expected["needs_dispatch"])
        if "resource_type" in expected:
            checks.append(expected["resource_type"] in result.get("dispatch_decision", {}).get("required_types", []))
        return all(checks)

    def generate_report(self, results: Dict) -> str:
        report = f"\n{'='*40}\nIntelligent Rescue Dispatch - Evaluation Report\nTime: {results['timestamp']}\n{'='*40}\n"
        report += f"Total: {results['total']}\nPassed: {results['passed']}\nPass Rate: {results['passed']/results['total']:.1%}\n"
        for cat, data in results["by_category"].items():
            rate = data["passed"]/data["total"] if data["total"] else 0
            report += f"  - {cat}: {rate:.1%} ({data['passed']}/{data['total']})\n"
        if results["latency"]:
            report += f"Avg Latency: {sum(results['latency'])/len(results['latency'])*1000:.0f}ms\n"
        return report

if __name__ == "__main__":
    from src.agent.graph import app_workflow
    evaluator = Evaluator(app_workflow)
    results = evaluator.run()
    print(evaluator.generate_report(results))
    with open("evals/results/latest.json", "w") as f:
        json.dump(results, f, indent=2)
EVAL_RUNNER_EOF

cat > evals/merge_sources.py << 'MERGE_EOF'
import json
import glob

def merge_test_cases():
    all_cases = []
    for file in glob.glob("evals/*_test_cases.json"):
        with open(file) as f:
            all_cases.extend(json.load(f))
    seen = set()
    unique = []
    for case in all_cases:
        if case["id"] not in seen:
            seen.add(case["id"])
            unique.append(case)
    with open("evals/test_cases.json", "w") as f:
        json.dump(unique, f, indent=2)
    print(f"Merged {len(unique)} total test cases")

if __name__ == "__main__":
    merge_test_cases()
MERGE_EOF

# ============================================================
# .gitignore
# ============================================================

cat > .gitignore << 'GITIGNORE_EOF'
# Python
__pycache__/
*.pyc
*.pyo
venv/
.env
*.log

# Data
data/*.json
logs/*.log
models/

# IDE
.vscode/
.idea/
.DS_Store

# Eval results
evals/results/*.json
!evals/results/.gitkeep
GITIGNORE_EOF

touch evals/results/.gitkeep
touch data/.gitkeep
touch logs/.gitkeep

echo "✅ Project files generated successfully!"
echo "📂 Location: $(pwd)"
echo ""
echo "Next steps:"
echo "  cd $(pwd)"
echo "  make install"
echo "  make run"
EOF

# 3. 执行脚本
bash cat-code.sh

# 4. 验证
echo ""
echo "📁 Generated directory structure:"
find . -type f -name "*.py" | head -20
```

---

## 执行步骤（复制粘贴即可）

```bash
# === 一键执行 ===
mkdir -p ~/desktop/project/rescue-assistant
cd ~/desktop/project/rescue-assistant

# 创建脚本并执行
cat > cat-code.sh << 'EOF'
# ... 上面的完整脚本内容 ...
EOF