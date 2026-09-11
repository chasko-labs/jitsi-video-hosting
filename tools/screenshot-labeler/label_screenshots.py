#!/usr/bin/env python3
"""Classify screenshots as jitsi meetup captures via Nova 2 Multimodal Embeddings.

cross-modal: embed anchor text phrases (GENERIC_RETRIEVAL) and each image
(GENERIC_INDEX), cosine-compare image vs positive/negative anchors.

credentials: env-var only (AWS_ACCESS_KEY_ID / SECRET / SESSION_TOKEN). the
run wrapper injects them via `aws configure export-credentials` so boto3 never
touches the (root-owned) SSO cache. do not pass profile_name here.
"""
import argparse
import base64
import json
import os
import sys
import time
from pathlib import Path

import boto3
import numpy as np
from botocore.config import Config
from botocore.exceptions import ClientError
from PIL import Image

MODEL_ID = "amazon.nova-2-multimodal-embeddings-v1:0"
REGION = "us-east-1"
# nova 2 accepts inline image bytes; keep the long edge bounded to stay well
# under the request-size ceiling and cut base64 payload / latency
MAX_EDGE = 1024
IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".gif"}


def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def client():
    cfg = Config(retries={"max_attempts": 6, "mode": "adaptive"})
    return boto3.client("bedrock-runtime", region_name=REGION, config=cfg)


def _extract(resp_bytes):
    out = json.loads(resp_bytes)
    embs = out.get("embeddings")
    if not embs:
        raise ValueError(f"no embeddings in response: {json.dumps(out)[:200]}")
    return np.asarray(embs[0]["embedding"], dtype=np.float32)


def embed_text(rt, text, purpose="GENERIC_RETRIEVAL"):
    body = {
        "taskType": "SINGLE_EMBEDDING",
        "singleEmbeddingParams": {
            "embeddingPurpose": purpose,
            "text": {"truncationMode": "END", "value": text},
        },
    }
    return _extract(_invoke(rt, body))


def embed_image(rt, path, purpose="GENERIC_INDEX"):
    with Image.open(path) as im:
        im = im.convert("RGB")
        if max(im.size) > MAX_EDGE:
            im.thumbnail((MAX_EDGE, MAX_EDGE))
        import io

        buf = io.BytesIO()
        im.save(buf, format="PNG")
    b64 = base64.b64encode(buf.getvalue()).decode()
    body = {
        "taskType": "SINGLE_EMBEDDING",
        "singleEmbeddingParams": {
            "embeddingPurpose": purpose,
            "image": {"format": "png", "source": {"bytes": b64}},
        },
    }
    return _extract(_invoke(rt, body))


def _invoke(rt, body, throttle=0.15):
    """single invoke with explicit throttle handling; adaptive retries cover
    transient throttles, this loop covers hard ThrottlingException surfaces."""
    delay = 1.0
    for attempt in range(6):
        try:
            r = rt.invoke_model(modelId=MODEL_ID, body=json.dumps(body))
            data = r["body"].read()
            time.sleep(throttle)
            return data
        except ClientError as e:
            code = e.response.get("Error", {}).get("Code", "")
            if code in ("ThrottlingException", "TooManyRequestsException") and attempt < 5:
                log(f"throttled, backoff {delay:.1f}s (attempt {attempt+1})")
                time.sleep(delay)
                delay = min(delay * 2, 30)
                continue
            raise
    raise RuntimeError("exhausted throttle retries")


def cosine(a, b):
    return float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-9))


def build_anchors(rt, anchors_path):
    spec = json.loads(Path(anchors_path).read_text())
    pos, neg = {}, {}
    for name, phrase in spec["positive"].items():
        pos[name] = embed_text(rt, phrase)
        log(f"anchor+ {name}")
    for name, phrase in spec["negative"].items():
        neg[name] = embed_text(rt, phrase)
        log(f"anchor- {name}")
    return pos, neg, spec["label_map"]


def list_images(root):
    root = Path(root)
    return sorted(
        p for p in root.iterdir()
        if p.is_file() and p.suffix.lower() in IMAGE_EXTS and not p.name.startswith(".")
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--images", nargs="+", required=True,
                    help="dir(s) of images; each dir tagged with --meetups in order")
    ap.add_argument("--meetups", nargs="+", required=True,
                    help="meetup tag per images dir (parallel lists)")
    ap.add_argument("--anchors", default=str(Path(__file__).with_name("anchors.json")))
    ap.add_argument("--out", required=True, help="manifest json output path")
    args = ap.parse_args()

    if len(args.images) != len(args.meetups):
        sys.exit("images and meetups lists must be same length")
    if not (os.environ.get("AWS_ACCESS_KEY_ID") and os.environ.get("AWS_SESSION_TOKEN")):
        sys.exit("no AWS env creds; run via run.sh which exports them")

    rt = client()
    log(f"model {MODEL_ID} region {REGION}")
    pos, neg, label_map = build_anchors(rt, args.anchors)

    # resume support: reload prior partial manifest
    out_path = Path(args.out)
    done = {}
    if out_path.exists():
        try:
            prior = json.loads(out_path.read_text())
            for row in prior.get("results", []):
                done[row["path"]] = row
            log(f"resuming: {len(done)} already scored")
        except Exception:
            pass

    results = list(done.values())
    total = 0
    for images_dir, meetup in zip(args.images, args.meetups):
        imgs = list_images(images_dir)
        log(f"dir {images_dir} meetup={meetup} count={len(imgs)}")
        for i, p in enumerate(imgs):
            key = str(p)
            if key in done:
                continue
            try:
                v = embed_image(rt, p)
            except Exception as e:
                log(f"SKIP {p.name}: {e}")
                results.append({"path": key, "meetup_dir": meetup, "top_label": "error",
                                "jitsi_score": 0.0, "confidence": 0.0, "error": str(e)[:160]})
                continue
            pos_scores = {n: cosine(v, a) for n, a in pos.items()}
            neg_scores = {n: cosine(v, a) for n, a in neg.items()}
            best_pos_name = max(pos_scores, key=pos_scores.get)
            best_pos = pos_scores[best_pos_name]
            best_neg = max(neg_scores.values())
            jitsi_score = best_pos
            confidence = best_pos - best_neg  # positive margin => jitsi-positive
            top_label = label_map.get(best_pos_name, best_pos_name) if confidence > 0 else "not_jitsi"
            results.append({
                "path": key,
                "meetup_dir": meetup,
                "top_label": top_label,
                "jitsi_score": round(jitsi_score, 5),
                "confidence": round(confidence, 5),
                "best_positive_anchor": best_pos_name,
                "best_negative": round(best_neg, 5),
            })
            total += 1
            if (i + 1) % 10 == 0:
                log(f"  {images_dir}: {i+1}/{len(imgs)}")
                out_path.write_text(json.dumps(
                    {"model": MODEL_ID, "results": sorted(results, key=lambda r: -r["jitsi_score"])},
                    indent=2))

    results.sort(key=lambda r: -r["jitsi_score"])
    out_path.write_text(json.dumps({"model": MODEL_ID, "results": results}, indent=2))
    log(f"DONE scored={total} manifest={out_path}")


if __name__ == "__main__":
    main()
