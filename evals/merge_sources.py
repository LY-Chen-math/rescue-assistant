import json
import glob

def merge_test_cases():
    all_cases = []
    for file in glob.glob("evals/*_test_cases.json"):
        with open(file) as f:
            all_cases.extend(json.load(f))
    seen = set()
    unique = []
    for case in all_cases:
        if case["id"] not in seen:
            seen.add(case["id"])
            unique.append(case)
    with open("evals/test_cases.json", "w") as f:
        json.dump(unique, f, indent=2)
    print(f"Merged {len(unique)} total test cases")

if __name__ == "__main__":
    merge_test_cases()
