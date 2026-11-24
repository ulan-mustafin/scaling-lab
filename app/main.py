import hashlib
import os
import time

from fastapi import FastAPI, Query

app = FastAPI(title="Container Scaling Experiment")
INSTANCE_ID = os.getenv("HOSTNAME", "local")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "instance": INSTANCE_ID}


@app.get("/work")
def work(iterations: int = Query(default=50_000, ge=1_000, le=2_000_000)) -> dict[str, object]:
    started = time.perf_counter()
    value = b"scaling-experiment"
    for _ in range(iterations):
        value = hashlib.sha256(value).digest()

    return {
        "instance": INSTANCE_ID,
        "iterations": iterations,
        "digest": value.hex(),
        "processing_ms": round((time.perf_counter() - started) * 1_000, 2),
    }
