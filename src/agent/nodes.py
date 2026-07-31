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
