import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / "results"
rows = []

for summary_path in sorted(RESULTS.glob("**/k6-summary.json")):
    config_path = summary_path.parent / "config.json"
    if not config_path.exists():
        continue
    config = json.loads(config_path.read_text())
    metrics = json.loads(summary_path.read_text()).get("metrics", {})

    def value(metric, field, default=0):
        metric_data = metrics.get(metric, {})
        return metric_data.get("values", metric_data).get(field, default)

    def rounded(metric, field):
        observed = value(metric, field, None)
        return round(observed, 3) if observed is not None else ""

    rows.append({
        **config,
        "requests_per_second": rounded("http_reqs", "rate"),
        "mean_latency_ms": rounded("http_req_duration", "avg"),
        "p95_latency_ms": rounded("http_req_duration", "p(95)"),
        "p99_latency_ms": rounded("http_req_duration", "p(99)"),
        "error_rate_percent": round(value("http_req_failed", "rate") * 100, 3),
    })

if not rows:
    raise SystemExit("No k6 summaries found. Run an experiment first.")

fields = list(rows[0])
with (RESULTS / "summary.csv").open("w", newline="") as file:
    writer = csv.DictWriter(file, fieldnames=fields)
    writer.writeheader()
    writer.writerows(rows)

formal_candidates = [
    row for row in rows
    if row.get("vus") == 25
    and row.get("duration") == "60s"
    and row.get("iterations") == 50000
]
formal_groups = {}
for row in formal_candidates:
    formal_groups.setdefault((row["strategy"], row["level"]), []).append(row)

formal_rows = []
for group_rows in formal_groups.values():
    formal_rows.extend(sorted(group_rows, key=lambda row: row["timestamp_utc"])[-3:])
formal_rows.sort(key=lambda row: (row["strategy"], int(row["level"]), row["timestamp_utc"]))

with (RESULTS / "formal-summary.csv").open("w", newline="") as file:
    writer = csv.DictWriter(file, fieldnames=fields)
    writer.writeheader()
    writer.writerows(formal_rows)

try:
    import matplotlib.pyplot as plt
except ImportError:
    print("Created results/summary.csv. Install requirements-analysis.txt for charts.")
    raise SystemExit(0)

groups = {}
for row in formal_rows:
    key = f"{row['strategy'].title()} {row['level']}"
    groups.setdefault(key, []).append(row)

labels = list(groups)
throughput = [sum(float(r["requests_per_second"]) for r in groups[x]) / len(groups[x]) for x in labels]
p95 = [sum(float(r["p95_latency_ms"]) for r in groups[x]) / len(groups[x]) for x in labels]
charts = RESULTS / "charts"
charts.mkdir(exist_ok=True)
for title, values, ylabel, filename in [
    ("Average throughput", throughput, "Requests / second", "throughput.png"),
    ("Average p95 latency", p95, "Milliseconds", "p95-latency.png"),
]:
    plt.figure(figsize=(9, 5))
    plt.bar(labels, values)
    plt.title(title)
    plt.ylabel(ylabel)
    plt.tight_layout()
    plt.savefig(charts / filename, dpi=160)
    plt.close()
print("Created results/summary.csv, results/formal-summary.csv, and results/charts/.")
