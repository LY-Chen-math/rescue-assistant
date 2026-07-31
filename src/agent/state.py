from typing import TypedDict, Optional, List, Dict

class TokenUsage(TypedDict):
    prompt_tokens: int
    completion_tokens: int
    total_tokens: int
    estimated_cost: float

class AgentState(TypedDict):
    # Input
    incident: str
    location: str

    # Processing
    severity: Optional[str]
    incident_type: Optional[str]
    extracted_entities: Optional[Dict]

    # Decision
    dispatch_decision: Optional[Dict]
    candidate_resources: Optional[List]
    selected_resource: Optional[str]

    # Output
    response: Optional[str]
    confidence: Optional[float]

    # Observability
    token_usage: Optional[TokenUsage]
    latency_ms: Optional[int]
    error: Optional[str]

    # Self-optimization
    session_id: Optional[str]
    feedback: Optional[Dict]
