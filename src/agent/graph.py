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
