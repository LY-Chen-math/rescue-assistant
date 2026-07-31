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
