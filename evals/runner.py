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
