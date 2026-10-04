#!/usr/bin/env python3
"""Capture the twin's answers to a fixed question set, in every locale.

This is a CHANGE DETECTOR, not a grader. The scores are crude on purpose; the
thing of value is the saved replies, which you diff across a run before and a
run after an infrastructure change (vector store swap, embedding model change,
knowledge-base restructure).

  python scripts/eval/capture.py --label before-s3vectors
  python scripts/eval/capture.py --label after-s3vectors
  python scripts/eval/compare.py before-s3vectors after-s3vectors
"""
import argparse, json, os, ssl, subprocess, sys, time, urllib.error, urllib.request
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
RUNS = HERE / "runs"
DEFAULT_API = "https://ke1cezzlq1.execute-api.eu-central-1.amazonaws.com"
LOCALES = ("en", "de")


def ask(base_url, message, lang, timeout, attempts=4):
    """POST /chat. Retries 429 (the circuit breaker / throttle) and 5xx."""
    body = json.dumps({"message": message, "history": [], "lang": lang}).encode()
    last = None
    for attempt in range(attempts):
        req = urllib.request.Request(
            f"{base_url.rstrip('/')}/chat", data=body,
            headers={"Content-Type": "application/json"}, method="POST")
        started = time.monotonic()
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                elapsed = round((time.monotonic() - started) * 1000)
                payload = json.loads(resp.read())
                return {"ok": True, "status": resp.status,
                        "reply": payload.get("reply", ""), "ms": elapsed}
        except urllib.error.HTTPError as e:
            last = {"ok": False, "status": e.code, "reply": "",
                    "ms": round((time.monotonic() - started) * 1000),
                    "error": e.read().decode(errors="replace")[:300]}
            if e.code not in (429, 500, 502, 503, 504):
                return last
        except Exception as e:                                  # noqa: BLE001
            last = {"ok": False, "status": 0, "reply": "",
                    "ms": round((time.monotonic() - started) * 1000),
                    "error": f"{type(e).__name__}: {e}"[:300]}
        if attempt < attempts - 1:
            # 429 here is a 20-req/MINUTE window, so seconds of backoff never clears it.
            time.sleep(25 * (attempt + 1) if last and last.get("status") == 429 else 2 ** attempt)
    return last


def score(question, reply):
    """Grounded: share of expected fact-groups present. Negative: no false claim."""
    low = reply.lower()
    if question["kind"] == "grounded":
        groups = question["expect"]
        hits = [any(alt.lower() in low for alt in grp) for grp in groups]
        missed = [grp[0] for grp, hit in zip(groups, hits) if not hit]
        return {"matched": sum(hits), "total": len(groups), "missing": missed}
    bad = [p for p in question["forbid"] if p.lower() in low]
    return {"matched": 0 if bad else 1, "total": 1, "asserted_falsehood": bad}


def preflight(base_url, timeout):
    """Fail fast and loudly rather than burning the whole suite on one broken thing.

    The python.org macOS build ships with no CA bundle, so every HTTPS call dies
    with CERTIFICATE_VERIFY_FAILED even though curl works. Point SSL_CERT_FILE at
    a real bundle instead of disabling verification.
    """
    url = f"{base_url.rstrip('/')}/health"
    try:
        with urllib.request.urlopen(url, timeout=timeout) as resp:
            health = json.loads(resp.read())
        if not health.get("ai_loaded"):
            sys.exit(f"preflight: /health says ai_loaded={health.get('ai_loaded')!r} - engine not ready")
        print(f"preflight: {health.get('status')}, ai_loaded={health.get('ai_loaded')}")
    except urllib.error.HTTPError as e:     # subclass of URLError, so it comes first
        if e.code == 429:
            sys.exit("preflight: 429 at /health - the circuit breaker is engaged. Check:\n"
                     "  aws apigatewayv2 get-stage --api-id <id> --stage-name '$default' "
                     "--query DefaultRouteSettings")
        sys.exit(f"preflight: HTTP {e.code} at {url}")
    except urllib.error.URLError as e:
        # urllib wraps the real cause in .reason, so the SSL error is not catchable directly.
        if isinstance(e.reason, ssl.SSLCertVerificationError):
            sys.exit(
                "preflight: TLS verification failed - this interpreter has no CA bundle.\n"
                "  Point SSL_CERT_FILE at a real one rather than disabling verification:\n"
                "    SSL_CERT_FILE=/opt/homebrew/etc/openssl@3/cert.pem python3 "
                + " ".join(sys.argv) + "\n"
                "  (/opt/homebrew/bin/python3 is already configured, if you have it)")
        sys.exit(f"preflight: cannot reach {url} - {e.reason}")
    except Exception as e:                                      # noqa: BLE001
        sys.exit(f"preflight: cannot reach {url} - {type(e).__name__}: {e}")


def git_sha():
    try:
        return subprocess.run(["git", "rev-parse", "--short", "HEAD"],
                              capture_output=True, text=True, check=True,
                              cwd=HERE).stdout.strip()
    except Exception:                                           # noqa: BLE001
        return "unknown"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--label", required=True, help="name for this run, e.g. before-s3vectors")
    ap.add_argument("--base-url", default=os.environ.get("TWIN_API_URL", DEFAULT_API))
    ap.add_argument("--timeout", type=float, default=60.0)
    # The binding limit is slowapi's @limiter.limit("20/minute") per IP in main.py,
    # NOT the API Gateway stage (5 rps / burst 10). At ~1.4s median latency, a 2.5s
    # gap lands around 15 req/min with headroom for a slow German answer.
    ap.add_argument("--delay", type=float, default=2.5,
                    help="seconds between calls (app limit is 20/min per IP)")
    args = ap.parse_args()

    preflight(args.base_url, args.timeout)

    suite = json.loads((HERE / "questions.json").read_text())["questions"]
    started = datetime.now(timezone.utc)
    results, failures = [], 0

    print(f"{len(suite)} questions x {len(LOCALES)} locales -> {args.base_url}\n")
    for q in suite:
        for lang in LOCALES:
            out = ask(args.base_url, q[f"q_{lang}"], lang, args.timeout)
            sc = score(q, out["reply"]) if out["ok"] else {"matched": 0, "total": 1}
            if not out["ok"]:
                failures += 1
            results.append({"id": q["id"], "kind": q["kind"], "lang": lang,
                            "question": q[f"q_{lang}"], **out, "score": sc})
            flag = "ok " if out["ok"] and sc["matched"] == sc["total"] else "FAIL" if not out["ok"] else "warn"
            detail = out.get("error", "") if not out["ok"] else \
                ("asserted: " + "; ".join(sc["asserted_falsehood"])) if sc.get("asserted_falsehood") else \
                ("missing: " + ", ".join(sc["missing"])) if sc.get("missing") else ""
            print(f"  [{flag}] {q['id']:<13} {lang}  {sc['matched']}/{sc['total']}  {out['ms']:>5}ms  {detail}")
            time.sleep(args.delay)

    RUNS.mkdir(exist_ok=True)
    oks = [r for r in results if r["ok"]]
    doc = {
        "label": args.label, "base_url": args.base_url, "git_sha": git_sha(),
        "started_utc": started.isoformat(), "ended_utc": datetime.now(timezone.utc).isoformat(),
        "transport_failures": failures,
        "grounded_score": sum(r["score"]["matched"] for r in results if r["kind"] == "grounded"),
        "grounded_total": sum(r["score"]["total"] for r in results if r["kind"] == "grounded"),
        "negative_pass": sum(r["score"]["matched"] for r in results if r["kind"] == "negative"),
        "negative_total": sum(r["score"]["total"] for r in results if r["kind"] == "negative"),
        "median_ms": sorted(r["ms"] for r in oks)[len(oks) // 2] if oks else None,
        "results": results,
    }
    path = RUNS / f"{args.label}.json"
    path.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n")

    print(f"\ngrounded   {doc['grounded_score']}/{doc['grounded_total']}")
    print(f"negative   {doc['negative_pass']}/{doc['negative_total']}  (false claims avoided)")
    print(f"median     {doc['median_ms']} ms")
    print(f"transport  {failures} failed request(s)")
    print(f"\nsaved {path.relative_to(HERE.parent.parent)}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
