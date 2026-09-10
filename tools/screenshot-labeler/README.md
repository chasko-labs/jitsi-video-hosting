# screenshot-labeler

classify mac mini desktop screenshots as jitsi video-meetup captures using amazon
nova 2 multimodal embeddings. cross-modal: embed reference anchor phrases and each
image, then cosine-compare image against positive vs negative anchors.

## what it does

- text anchors embedded with `embeddingPurpose=GENERIC_RETRIEVAL`
- images embedded with `embeddingPurpose=GENERIC_INDEX` (3072-dim vectors)
- `jitsi_score` = best positive-anchor cosine
- `confidence` = best positive cosine minus best negative cosine (positive margin => jitsi-positive)
- `top_label` = the meetup mapped from the winning positive anchor (`clouddelnorte` / `ne3d`), or `not_jitsi` when a negative anchor wins

model: `amazon.nova-2-multimodal-embeddings-v1:0`, region `us-east-1`, account 946179428633
(profile `bryanchasko-kiro`). originals are never modified — the labeler reads local
working copies rsynced from macmini.

## anchor phrases

positive:

- jitsi_generic: a jitsi video conference call showing a grid of participant video tiles
- clouddelnorte_meeting: a web browser showing a video meeting at clouddelnorte.org or quantum.clouddelnorte.org
- ne3d_meeting: a web browser showing a video meeting at ne3d.org
- video_grid: a video conferencing screen with multiple webcam feeds and a toolbar of call controls

negative: board_game, moodle, code_editor, desktop, web_article, spreadsheet
(see `anchors.json` for exact strings)

## run

creds come from the working SSO CLI session via `aws configure export-credentials`
(the python profile path fails on a root-owned SSO cache file, so env-var injection
is required). `run.sh` handles it.

```
# rsync working copies first (originals untouched):
rsync -a --delete macmini:/Users/bryanchasko/Desktop/desktop2026/cloudelnorte-screenshots/ \
  /tmp/jitsi-shots/clouddelnorte/
rsync -a macmini:'/Users/bryanchasko/Desktop/desktop2026/Screenshot\ 2026-08-*.png' \
  /tmp/jitsi-shots/ne3d/

# backgrounded run:
nohup ./run.sh \
  --images /tmp/jitsi-shots/clouddelnorte /tmp/jitsi-shots/ne3d \
  --meetups clouddelnorte ne3d \
  --out ./jitsi-screenshot-manifest.json \
  > ./labeler.log 2>&1 &
echo $! > labeler.pid
```

check progress: `tail -f labeler.log`. the manifest is checkpointed every 10 images
and the run is resumable (re-invoking skips already-scored paths).

## output

`jitsi-screenshot-manifest.json`: `{model, results:[{path, meetup_dir, top_label,
jitsi_score, confidence, best_positive_anchor, best_negative}]}` sorted by
`jitsi_score` desc.

on completion a one-line per-meetup positive count is written to valkey hash
`jitsi:cost-blog:screenshots`.
