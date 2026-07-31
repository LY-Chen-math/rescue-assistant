.PHONY: install test eval run test-api docker-up deploy-aliyun deploy-aws optimize

install:
	pip install -r requirements.txt

test:
	pytest tests/ -v --cov=src --cov-report=html

eval:
	python evals/merge_sources.py
	python evals/runner.py

run:
	uvicorn src.api.routes:app --reload --host 0.0.0.0 --port 8000

test-api:
	curl -X POST http://localhost:8000/dispatch \
	  -H "Content-Type: application/json" \
	  -d '{"incident": "Zone A, car accident", "location": "Zone A"}'

docker-up:
	docker-compose up -d

deploy-aliyun:
	@echo "Deploying to Alibaba Cloud..."
	scp -r . aliyun-ecs:~/rescue-assistant/
	ssh aliyun-ecs "cd ~/rescue-assistant && docker-compose up -d"

deploy-aws:
	@echo "Deploying to AWS..."
	terraform apply -auto-approve

optimize:
	python -c "from src.self_optimization.optimizer import optimizer; optimizer._optimize_once()"
