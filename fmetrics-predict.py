#!/usr/bin/env python3
"""
fmetrics-predict.py — k-NN regression for fsuite runtime prediction.

Pure stdlib (no numpy/scipy needed). Queries historical telemetry from SQLite,
normalizes features, finds k nearest neighbors, and predicts runtime.

Usage:
    python3 fmetrics-predict.py --db ~/.fsuite/telemetry.db \
        --items 500 --bytes 10000000 --depth 3 --output json
"""

import argparse
import json
import math
import sqlite3
import sys
from typing import Dict, List, Optional, Tuple

VERSION = "1.0.0"
DEFAULT_K = 5
MIN_SAMPLES = 5


def connect_db(db_path: str) -> sqlite3.Connection:
    """Connect to the telemetry database."""
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    return conn


def get_tool_data(conn: sqlite3.Connection, tool: str) -> List[dict]:
    """Fetch successful historical runs for a given tool."""
    cursor = conn.execute(
        "SELECT duration_ms, items_scanned, bytes_scanned, depth "
        "FROM telemetry WHERE tool = ? AND exit_code = 0 "
        "AND items_scanned >= 0",
        (tool,)
    )
    return [dict(row) for row in cursor.fetchall()]


def compute_stats(values: List[float]) -> Tuple[float, float]:
    """Compute mean and std deviation."""
    if not values:
        return 0.0, 0.0
    n = len(values)
    mean = sum(values) / n
    if n < 2:
        return mean, 0.0
    variance = sum((x - mean) ** 2 for x in values) / (n - 1)
    return mean, math.sqrt(variance)


def z_score_normalize(value: float, mean: float, std: float) -> float:
    """Z-score normalize a value. Returns 0 if std is 0."""
    if std == 0:
        return 0.0
    return (value - mean) / std


def euclidean_distance(a: List[float], b: List[float]) -> float:
    """Compute Euclidean distance between two feature vectors."""
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


def filter_outliers_iqr(data: List[dict], factor: float = 1.5) -> List[dict]:
    """Remove duration outliers using IQR method."""
    if len(data) < 4:
        return data
    durations = sorted(d["duration_ms"] for d in data)
    n = len(durations)
    q1 = durations[n // 4]
    q3 = durations[3 * n // 4]
    iqr = q3 - q1
    lower = q1 - factor * iqr
    upper = q3 + factor * iqr
    return [d for d in data if lower <= d["duration_ms"] <= upper]


def predict_for_tool(
    data: List[dict],
    target_items: int,
    target_bytes: int,
    target_depth: int,
    k: int = DEFAULT_K,
) -> Optional[dict]:
    """
    k-NN regression prediction for a single tool.

    Features: items_scanned, bytes_scanned, depth
    Target: duration_ms
    """
    if len(data) < MIN_SAMPLES:
        return None

    # Remove outliers before prediction
    data = filter_outliers_iqr(data)
    if len(data) < MIN_SAMPLES:
        return None

    # Extract feature columns
    items_vals = [float(d["items_scanned"]) for d in data]
    bytes_vals = [float(d["bytes_scanned"]) for d in data]
    depth_vals = [float(d["depth"]) for d in data]
    durations = [float(d["duration_ms"]) for d in data]

    # Compute normalization stats
    items_mean, items_std = compute_stats(items_vals)
    bytes_mean, bytes_std = compute_stats(bytes_vals)
    depth_mean, depth_std = compute_stats(depth_vals)

    # Normalize target
    target_features = [
        z_score_normalize(float(target_items), items_mean, items_std),
        z_score_normalize(float(target_bytes), bytes_mean, bytes_std),
        z_score_normalize(float(target_depth), depth_mean, depth_std),
    ]

    # Compute distances for all historical points
    distances = []
    for i, d in enumerate(data):
        point_features = [
            z_score_normalize(items_vals[i], items_mean, items_std),
            z_score_normalize(bytes_vals[i], bytes_mean, bytes_std),
            z_score_normalize(depth_vals[i], depth_mean, depth_std),
        ]
        dist = euclidean_distance(target_features, point_features)
        distances.append((dist, durations[i]))

    # Sort by distance, take k nearest
    distances.sort(key=lambda x: x[0])
    neighbors = distances[:k]

    if not neighbors:
        return None

    # Weighted average (inverse distance weighting)
    neighbor_durations = [d for _, d in neighbors]
    neighbor_distances = [dist for dist, _ in neighbors]

    # Inverse distance weighting with epsilon to prevent division by zero
    EPSILON = 1e-9
    weights = [1.0 / (d + EPSILON) for d in neighbor_distances]
    total_weight = sum(weights)
    predicted_ms = sum(w * d for w, d in zip(weights, neighbor_durations)) / total_weight

    # Confidence based on std dev of neighbors and distance spread
    pred_mean, pred_std = compute_stats(neighbor_durations)
    avg_dist = sum(neighbor_distances) / len(neighbor_distances)

    # Confidence heuristic
    if pred_std < pred_mean * 0.2 and avg_dist < 1.5:
        confidence = "high"
    elif pred_std < pred_mean * 0.5 and avg_dist < 3.0:
        confidence = "medium"
    else:
        confidence = "low"

    return {
        "tool": "",  # filled by caller
        "predicted_ms": int(round(predicted_ms)),
        "std_dev_ms": int(round(pred_std)),
        "confidence": confidence,
        "k_used": len(neighbors),
        "avg_neighbor_distance": round(avg_dist, 3),
        "neighbor_durations": [int(d) for d in neighbor_durations],
    }


def main():
    parser = argparse.ArgumentParser(description="k-NN runtime prediction for fsuite tools")
    parser.add_argument("--db", required=True, help="Path to telemetry.db")
    parser.add_argument("--items", type=int, required=True, help="Target items_scanned")
    parser.add_argument("--bytes", type=int, default=-1, help="Target bytes_scanned")
    parser.add_argument("--depth", type=int, default=3, help="Target depth")
    parser.add_argument("--k", type=int, default=DEFAULT_K, help="Number of neighbors")
    parser.add_argument("--output", choices=["json", "pretty"], default="json")
    parser.add_argument("--version", action="version", version=f"fmetrics-predict {VERSION}")
    args = parser.parse_args()

    try:
        conn = connect_db(args.db)
    except Exception as e:
        print(json.dumps({"error": f"Cannot open database: {e}"}))
        sys.exit(1)

    total_samples = conn.execute(
        "SELECT COUNT(*) FROM telemetry WHERE exit_code=0"
    ).fetchone()[0]

    tools = ["ftree", "fsearch", "fcontent"]
    predictions = []

    for tool in tools:
        data = get_tool_data(conn, tool)
        result = predict_for_tool(data, args.items, args.bytes, args.depth, args.k)
        if result:
            result["tool"] = tool
            result["samples"] = len(data)
            predictions.append(result)
        else:
            predictions.append({
                "tool": tool,
                "predicted_ms": -1,
                "confidence": "none",
                "samples": len(data),
                "error": f"insufficient data, need {MIN_SAMPLES} samples, have {len(data)}",
            })

    conn.close()

    output = {
        "tool": "fmetrics",
        "version": VERSION,
        "subcommand": "predict",
        "method": "knn_regression",
        "k": args.k,
        "target_features": {
            "items": args.items,
            "bytes": args.bytes,
            "depth": args.depth,
        },
        "predictions": predictions,
        "total_historical_samples": total_samples,
    }

    if args.output == "json":
        print(json.dumps(output))
    else:
        print(f"fmetrics predict -- k-NN Regression (k={args.k})")
        print("=" * 44)
        print(f"  Target: {args.items} items, {args.bytes} bytes, depth {args.depth}")
        print(f"  Historical samples: {total_samples}")
        print()
        for p in predictions:
            if p.get("predicted_ms", -1) >= 0:
                print(f"  {p['tool']:<12} ~{p['predicted_ms']}ms "
                      f"+/-{p.get('std_dev_ms', 0)}ms  "
                      f"[{p['confidence']}] ({p['samples']} samples)")
            else:
                print(f"  {p['tool']:<12} -- {p.get('error', 'no prediction')}")


if __name__ == "__main__":
    main()
