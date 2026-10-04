#!/usr/bin/env python3
"""Assert the built Lambda zips contain what the code imports, and not much else.

This exists because of two real production incidents:

  1. greenlet was silently dropped by the arm64 cross-build (pip evaluates
     environment markers against the HOST, not --platform), and BOTH Lambdas
     began failing at import. Nothing caught it until the site went down.
  2. The API zip reached 225 MB unzipped against Lambda's 250 MB hard limit,
     carrying ~65 MB that is never imported at runtime. Nothing warned about it.

A zip cannot be import-tested locally: the wheels are manylinux2014_aarch64, so
their compiled extensions will not load on a developer machine. Checking that the
expected top-level modules are present is the next best thing, and it catches the
whole class of "a transitive dependency vanished when we removed its parent".

  python scripts/check_lambda_bundles.py
"""
import sys, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Unzipped-size ceiling. Lambda's hard limit is 250 MB; stop well short so there
# is room to add a dependency without discovering the limit in production.
MAX_UNZIPPED_MB = 200

BUNDLES = {
    "lambdas/api/api_lambda.zip": {
        "required": [
            # imported directly by main.py
            "main.py", "s3_vector_store.py",
            "langchain_aws", "langchain_core", "langchain", "fastapi", "mangum",
            "slowapi", "pydantic", "pydantic_core", "boto3", "botocore",
            # langchain pulls SQLAlchemy, which needs greenlet at runtime. Neither
            # is imported by our code, and both are required for it to start.
            "sqlalchemy", "greenlet",
        ],
        "forbidden": [
            # Local-only: requirements-local.txt. Their presence means something
            # re-added them to requirements.txt and the artifact grew again.
            "langchain_postgres", "psycopg", "langchain_community",
        ],
        # Present but not wanted, and not removable from here: fastapi 0.111.0
        # hard-requires uvicorn[standard] (a plain Requires-Dist, not an extra),
        # which drags in uvloop at ~16 MB and python-dotenv. FastAPI split that
        # out in 0.112 — `fastapi` vs `fastapi[standard]` — so bumping FastAPI
        # would shed it. Not done here: upgrading the web framework does not
        # belong in a vector-store migration.
        "unavoidable": ["uvicorn", "uvloop", "dotenv"],
    },
    "lambdas/ingestion/lambda_function.zip": {
        "required": [
            "lambda_function.py", "s3_vector_store.py",
            "langchain_aws", "langchain_core", "langchain_text_splitters",
            "langchain_community", "pypdf", "boto3", "botocore",
            "sqlalchemy", "greenlet",
        ],
        "forbidden": ["langchain_postgres", "psycopg"],
    },
}


def top_level(zf):
    """Top-level module and package names present in the archive."""
    names = set()
    for entry in zf.namelist():
        head = entry.split("/")[0]
        if head.endswith(".dist-info") or head.endswith(".egg-info"):
            continue
        names.add(head)
    return names


def main():
    failures = []
    for rel, spec in BUNDLES.items():
        path = ROOT / rel
        if not path.exists():
            failures.append(f"{rel}: not built — run its build.sh first")
            continue
        with zipfile.ZipFile(path) as zf:
            present = top_level(zf)
            unzipped_mb = sum(i.file_size for i in zf.infolist()) / 1048576

        print(f"\n{rel}")
        print(f"  unzipped {unzipped_mb:.0f} MB (ceiling {MAX_UNZIPPED_MB} MB, "
              f"Lambda hard limit 250 MB)")
        if unzipped_mb > MAX_UNZIPPED_MB:
            failures.append(f"{rel}: {unzipped_mb:.0f} MB exceeds the {MAX_UNZIPPED_MB} MB ceiling")

        missing = [m for m in spec["required"] if m not in present]
        if missing:
            failures.append(f"{rel}: MISSING {', '.join(missing)}")
            print(f"  missing: {', '.join(missing)}")
        else:
            print(f"  all {len(spec['required'])} required modules present")

        riding_along = [m for m in spec.get("unavoidable", []) if m in present]
        if riding_along:
            print(f"  known passengers (see comment): {', '.join(riding_along)}")

        sneaked = [m for m in spec["forbidden"] if m in present]
        if sneaked:
            failures.append(f"{rel}: should not be bundled: {', '.join(sneaked)}")
            print(f"  unexpectedly present: {', '.join(sneaked)}")
        else:
            print(f"  none of the {len(spec['forbidden'])} local-only packages bundled")

    if failures:
        print("\nFAILED")
        for f in failures:
            print(f"  - {f}")
        return 1
    print("\nboth bundles look correct")
    return 0


if __name__ == "__main__":
    sys.exit(main())
