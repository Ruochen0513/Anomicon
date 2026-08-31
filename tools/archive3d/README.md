# Archive 3D asset preparation

`prepare_archive_glb.py` turns an upstream glTF 2.0 binary into the static,
self-contained GLB consumed by Anomicon's ArkGraphics3D viewer. It is a
build-time tool; it never edits the source file or files under
`products/phone/src/main/resources` unless that path is explicitly supplied as
the destination.

## Requirements

* Python 3.10 or newer.
* [Pillow](https://pillow.readthedocs.io/) when the source contains embedded
  images:

  ```sh
  python3 -m pip install --user Pillow
  ```

The script uses only the Python standard library for GLB parsing and animation
sampling. It does not require Blender, Assimp, gltf-transform, or a GPU.

## Basic command

Run from the repository root and keep an untouched source copy outside the
product resource tree:

```sh
python3 tools/archive3d/prepare_archive_glb.py \
  /tmp/archive-source/Scp049.glb \
  /tmp/archive-prepared/scp-049.glb \
  --animation-name 049_Idle2 \
  --ratio 0.50
```

The selected clip is sampled once and its local translation, rotation and scale
channels are written as static node TRS. `--seconds 1.25` (an alias of
`--time`) can be used instead of `--ratio`; seconds are clamped to the clip's
authored keyframe range. Animated sources require an explicit
`--animation-name`, preventing an attack or T-pose clip from being selected by
file order. For a source with no animations, the geometry's authored pose is
retained.

The default sample ratio is `0.5`, which is usually a better neutral pose than
the first bind-pose frame. For each reviewed asset, record the exact clip and
ratio/seconds in the manifest or provenance note so the binary can be rebuilt.

## What the output guarantees

* GLB version 2 with one JSON chunk and one aligned BIN chunk.
* All animation objects are removed after the selected pose is baked. Accessors
  and buffer views that were used only by animation are dropped.
* Embedded PNG/JPEG/etc. images larger than `--max-texture` on either edge are
  resampled with Pillow (default 1024 px) and encoded as PNG. Existing images
  already within the limit keep their original bytes.
* The active scene is wrapped in `AnomiconInteractivePivot` →
  `AnomiconModelOffset`. The offset recenters the authored POSITION bounds so
  the runtime pivot can rotate the model without changing the mesh hierarchy.
  Use `--no-archive-roots` only for an intermediate artifact. For a source
  exported in a different unit system, `--archive-scale <factor>` adds an
  `AnomiconModelScale` wrapper above the offset; the authored root scale is not
  rewritten. Scaling that wrapper also scales the centering translation, so the
  pivot remains stable. `--archive-offset X Y Z` overrides automatic centering
  with a final offset (useful after checking a skinned asset in a viewer).
* No Draco, Meshopt, or KTX/BasisU extension is introduced. If one is present
  in the source, preparation stops with an actionable error; export an
  uncompressed GLB first.
* External buffer/image URIs are rejected rather than silently copied without
  their payload. Data-URI images are supported and resized in place. Archive
  entries must remain self-contained (`hasExternalDependencies` is `false`)
  before they are added to the app.

### Unit and skinned-root caveat

`POSITION` bounds describe mesh-local data. A skinned model can additionally
move geometry through joint transforms, and some Unity exports put a `0.01`
scale on the authored skeleton root (SCP-131 is an example). Automatic bounds
centering is still deterministic, but its visual framing must be checked. Use
an explicit, previewed correction such as `--archive-scale 12` (the factor is
asset-specific) and/or
`--archive-offset X Y Z`, then record those values with the asset provenance;
never edit the authored skeleton root just to make the archive camera fit.
When a clip is sampled, calculate the correction from the visible skinned mesh
after that pose is applied (not only from the raw accessor bounds); otherwise a
natural pose can move the model's optical center away from the camera target.

## Composite archives

For a multi-object entry such as SCP-131-A/B, prepare each source without an
archive pivot and place it with a neutral wrapper, merge the intermediates,
then prepare the merged static GLB once more. `--combine-scenes` is important
because `merge` emits one glTF scene per input. This leaves exactly one
`AnomiconInteractivePivot`, so rotating the archive always rotates the whole
composition:

```sh
python3 tools/archive3d/prepare_archive_glb.py orange.glb /tmp/131-a.glb \
  --animation-name 131_BodyN --seconds 0.0416667 --no-archive-roots \
  --placement-offset -0.11 0 0.015
python3 tools/archive3d/prepare_archive_glb.py yellow.glb /tmp/131-b.glb \
  --animation-name 131_BodyN --seconds 0.0416667 --no-archive-roots \
  --placement-offset 0.11 0 -0.015
npx --yes @gltf-transform/cli@4.4.2 merge \
  /tmp/131-a.glb /tmp/131-b.glb /tmp/131-pair.glb
python3 tools/archive3d/prepare_archive_glb.py \
  /tmp/131-pair.glb /tmp/scp-131.glb --archive-scale 12 --combine-scenes
```

The final scale is a reviewed framing correction for this particular Unity
export; it is not a claim about the objects' physical size.

## Review checklist

1. Keep the upstream URL, immutable commit/tag, license, attribution, source
   SHA-256, selected animation clip, sample time/ratio, and output SHA-256 in
   the archive manifest.
2. Inspect the command output with a GLB inspector and confirm `animations` is
   absent, the two Anomicon root names occur exactly once, and no forbidden
   extension is declared.
3. Check the generated file size and triangle/texture budgets before copying it
   into the product's rawfile directory. Do not commit an unreviewed source
   download.

## Delivery policy

The product manifest is intentionally split by delivery cost and provenance:

* Classic, reviewed SCP objects (currently 049, 106, 173 and 939) are shipped
  as processed rawfiles so their first view is available offline.
* Additional reviewed objects stay on demand. The app downloads a fixed HTTPS
  revision into its private content-addressed cache, verifies byte length,
  GLB header and SHA-256, and exposes removal only for that cache object. The
  current on-demand review set includes SCP-131-A, SCP-3199, SCP-650, SCP-079,
  SCP-178 and SCP-686. SCP-079 and SCP-178 are from the fixed
  `Yni-Viar/scp-assets@1265487d1978b60398ab71f366bc5a1ba4ce1d0d` SCP-CB
  revision; SCP-686 is from that revision's `By_Pop_Pop_Icard` collection.
  Each entry points to its corresponding CC BY-SA 3.0 notice file.
* A model is not added to the manifest until its binary, license and
  attribution have been reviewed. In particular, SCP-096 is deliberately
  omitted for now because no fixed, redistributable source has passed that
  review; the article menu must not advertise an unavailable model.

Do not turn a remote row into a bundled rawfile merely to make the gallery look
complete. If a classic asset is later approved, add it through the same
prepare/inspect/attribution process and record why its delivery class changed.

Example metadata inspection without an additional package:

```sh
python3 - <<'PY'
import json, struct
from pathlib import Path

p = Path('/tmp/archive-prepared/scp-049.glb')
payload = p.read_bytes()
json_length, _ = struct.unpack_from('<II', payload, 12)
doc = json.loads(payload[20:20 + json_length].rstrip(b' \0'))
print('animations:', len(doc.get('animations', [])))
print('archive roots:', [n.get('name') for n in doc.get('nodes', [])
                         if n.get('name', '').startswith('Anomicon')])
print('extensions:', sorted(set(doc.get('extensionsUsed', []))))
PY
```

For the current Yni-Viar Rigged-Ready review set, the following choices avoid
bind/T-pose frames and root drift (always preview before shipping):

```sh
# SCP-106: stable neutral look
python3 tools/archive3d/prepare_archive_glb.py Scp106.glb scp-106.glb \
  --animation-name 106_LookN --seconds 0

# SCP-131 variants: short neutral body clip
python3 tools/archive3d/prepare_archive_glb.py Scp131Orange.glb scp-131-orange.glb \
  --animation-name 131_BodyN --seconds 0.041667

# SCP-3199: first idle keyframe keeps the hips from sinking
python3 tools/archive3d/prepare_archive_glb.py Scp3199.glb scp-3199.glb \
  --animation-name 3199_Idle --seconds 0.041667
```

The app still owns runtime scene creation and teardown. This tool deliberately
does not add renderer-specific lights, cameras, or ArkTS metadata.
