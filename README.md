# Intelligent Rescue Dispatch Assistant

## Problem Statement
In emergency rescue scenarios, dispatchers must make rapid resource allocation decisions under high pressure. This system reduces the incident-to-dispatch process from an average of **3-5 minutes to under 30 seconds** using AI assistance.

## Technology Stack
- **Model**: Gemma 4 12B (GGUF) via llama.cpp
- **Agent Framework**: LangGraph
- **API**: FastAPI
- **Containerization**: Docker + docker-compose
- **CI/CD**: GitHub Actions
- **Cloud Platforms**: Alibaba Cloud → AWS (cross-cloud migration)

## Quick Start
```bash
make install
make run
make test
make eval
```

## Architecture
```
User Input → FastAPI → LangGraph Agent → Gemma 4 → Dispatch Decision
                              ↓
                        Memory / Skills
```

## Business Alignment
This project addresses The AA's "van of the future" strategy by providing a data-driven, AI-powered dispatch layer that sits on top of their connectivity infrastructure.

## License
MIT
