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
