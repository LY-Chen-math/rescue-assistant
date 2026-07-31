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
