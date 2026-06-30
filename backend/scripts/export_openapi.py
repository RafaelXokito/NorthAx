"""Export the live OpenAPI spec to docs/openapi.{json,yaml}.

Run from the backend/ directory:

    python -m scripts.export_openapi

This imports the FastAPI app and serialises `app.openapi()`, so the committed
spec always matches the code. No database or network connection is made.
"""
from __future__ import annotations

import json
import pathlib

from app.main import app

OUT_DIR = pathlib.Path(__file__).resolve().parent.parent / "docs"


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    spec = app.openapi()

    json_path = OUT_DIR / "openapi.json"
    json_path.write_text(json.dumps(spec, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {json_path.relative_to(OUT_DIR.parent)}")

    try:
        import yaml
    except ImportError:
        print("pyyaml not installed — skipped openapi.yaml (pip install pyyaml)")
        return
    yaml_path = OUT_DIR / "openapi.yaml"
    yaml_path.write_text(
        yaml.safe_dump(spec, sort_keys=False, allow_unicode=True), encoding="utf-8"
    )
    print(f"wrote {yaml_path.relative_to(OUT_DIR.parent)}")


if __name__ == "__main__":
    main()
