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
