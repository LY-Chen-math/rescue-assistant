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
