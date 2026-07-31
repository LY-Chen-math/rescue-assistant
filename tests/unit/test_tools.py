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
