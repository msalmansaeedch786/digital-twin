#!/usr/bin/env python3
"""Diff two capture runs and report regressions.

  python scripts/eval/compare.py before-s3vectors after-s3vectors

Exit status is 1 if anything regressed, so it can gate a migration step.
A changed wording is NOT a regression - the LLM is non-deterministic. What counts
is a grounded fact going missing, a negative test starting to assert a falsehood,
or docs_retrieved falling.
"""
import json, sys
from pathlib import Path

RUNS = Path(__file__).resolve().parent / "runs"


def load(label):
    p = RUNS / f"{label}.json"
    if not p.exists():
        sys.exit(f"no such run: {p}")
    return json.loads(p.read_text())


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    before, after = load(sys.argv[1]), load(sys.argv[2])
    bi = {(r["id"], r["lang"]): r for r in before["results"]}
    ai = {(r["id"], r["lang"]): r for r in after["results"]}

    regressions, improvements, reworded = [], [], 0

    for key in sorted(bi.keys() | ai.keys()):
        b, a = bi.get(key), ai.get(key)
        name = f"{key[0]}/{key[1]}"
        if b is None:
            improvements.append(f"{name}: new question"); continue
        if a is None:
            regressions.append(f"{name}: MISSING from the later run"); continue
        if not a["ok"]:
            regressions.append(f"{name}: transport failure (HTTP {a['status']})"); continue

        bs, as_ = b["score"]["matched"], a["score"]["matched"]
        # For negatives the falsehood line below says it better, so don't say it twice.
        if as_ < bs and a["kind"] == "grounded":
            lost = set(a["score"].get("missing", [])) - set(b["score"].get("missing", []))
            regressions.append(f"{name}: grounding {bs}->{as_}" +
                               (f" (lost: {', '.join(sorted(lost))})" if lost else ""))
        elif as_ > bs:
            improvements.append(f"{name}: grounding {bs}->{as_}")
        if a["score"].get("asserted_falsehood") and not b["score"].get("asserted_falsehood"):
            regressions.append(f"{name}: NOW ASSERTS A FALSEHOOD: {a['score']['asserted_falsehood']}")
        if b["reply"].strip() != a["reply"].strip() and as_ == bs:
            reworded += 1

    def mget(run, k):
        return (run.get("log_metrics") or {}).get(k)

    print(f"{sys.argv[1]} ({before.get('git_sha')})  ->  {sys.argv[2]} ({after.get('git_sha')})\n")
    print(f"grounded   {before['grounded_score']}/{before['grounded_total']}"
          f"  ->  {after['grounded_score']}/{after['grounded_total']}")
    print(f"negative   {before['negative_pass']}/{before['negative_total']}"
          f"  ->  {after['negative_pass']}/{after['negative_total']}")
    print(f"median ms  {before.get('median_ms')}  ->  {after.get('median_ms')}")
    bz, az = mget(before, "docs_retrieved_zero"), mget(after, "docs_retrieved_zero")
    if bz is not None or az is not None:
        print(f"docs=0     {bz}  ->  {az}   (zero means an empty knowledge base)")
        print(f"docs mean  {mget(before,'docs_retrieved_mean')}  ->  {mget(after,'docs_retrieved_mean')}")
    bs_, as_ = mget(before, "stage_medians_ms") or {}, mget(after, "stage_medians_ms") or {}
    for stage in sorted(bs_.keys() | as_.keys()):
        print(f"  {stage:<12} {bs_.get(stage, '-'):>8}  ->  {as_.get(stage, '-'):>8}")

    if az:
        regressions.append(f"docs_retrieved was 0 on {az} request(s) - knowledge base not populated")

    print(f"\nreworded but equivalent: {reworded}  (expected; the LLM is not deterministic)")
    if improvements:
        print("\nimprovements:")
        for i in improvements:
            print(f"  + {i}")
    if regressions:
        print("\nREGRESSIONS:")
        for r in regressions:
            print(f"  - {r}")
        return 1
    print("\nno regressions")
    return 0


if __name__ == "__main__":
    sys.exit(main())
