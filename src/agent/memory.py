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
