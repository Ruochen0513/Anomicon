#!/usr/bin/env python3
"""Batch-inspect local or GitHub GLB candidates for the archive catalog.

The command deliberately stops at a review report.  It does not edit the
product manifest or copy bytes into the application.  This keeps provenance,
license, object-class and per-item warning text as an explicit human review
step while removing the repetitive binary inspection work.

Examples:

  # Inspect every GLB below a fixed public GitHub revision.
  python3 tools/archive3d/inspect_archive_batch.py \
    --repo Yni-Viar/scp-assets \
    --ref 1265487d1978b60398ab71f366bc5a1ba4ce1d0d \
    --prefix GFX \
    --output /tmp/scp-assets-candidates.json

  # Re-check files that have already been downloaded locally.
  python3 tools/archive3d/inspect_archive_batch.py \
    --source-dir /tmp/archive-source \
    --output /tmp/archive-source-candidates.json
"""

from __future__ import annotations

import argparse
import base64
import binascii
import hashlib
import importlib.util
import json
import re
import shutil
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any, Iterable, NoReturn
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen


PREPARER_PATH = Path(__file__).with_name("prepare_archive_glb.py")
PREPARER_SPEC = importlib.util.spec_from_file_location(
    "anomicon_archive_glb_preparer", PREPARER_PATH
)
if PREPARER_SPEC is None or PREPARER_SPEC.loader is None:
    raise RuntimeError(f"无法加载 GLB 解析器：{PREPARER_PATH}")
PREPARER = importlib.util.module_from_spec(PREPARER_SPEC)
PREPARER_SPEC.loader.exec_module(PREPARER)


GITHUB_API = "https://api.github.com"
GITHUB_ACCEPT = "application/vnd.github+json"
GITHUB_USER_AGENT = "Anomicon-archive3d-inspector/1.0"
GLB_SUFFIX = ".glb"
DEFAULT_MAX_BYTES = 64 * 1024 * 1024
DEFAULT_MAX_TRIANGLES = 50_000
DEFAULT_MAX_TEXTURE = 1024


def fail(message: str) -> NoReturn:
    raise ValueError(message)


def normalized_prefix(value: str) -> str:
    prefix = value.strip().strip("/")
    if prefix in {"", "."}:
        return ""
    return prefix + "/"


def path_matches_prefix(path: str, prefixes: list[str]) -> bool:
    return not prefixes or any(path.startswith(prefix) for prefix in prefixes)


def request_json(url: str) -> dict[str, Any]:
    request = Request(
        url,
        headers={
            "Accept": GITHUB_ACCEPT,
            "User-Agent": GITHUB_USER_AGENT,
        },
    )
    try:
        with urlopen(request, timeout=30) as response:
            payload = response.read(8 * 1024 * 1024 + 1)
    except (HTTPError, URLError, TimeoutError) as error:
        fail(f"GitHub Trees API 请求失败：{url} ({error})")
    if len(payload) > 8 * 1024 * 1024:
        fail(f"GitHub Trees API 响应过大：{url}")
    try:
        value = json.loads(payload.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        fail(f"GitHub Trees API 返回了无效 JSON：{url} ({error})")
    if not isinstance(value, dict):
        fail(f"GitHub Trees API 根对象不是 JSON object：{url}")
    return value


def github_tree_entries(repo: str, ref: str) -> list[dict[str, Any]]:
    """List blobs at a fixed commit, with a non-recursive fallback.

    GitHub limits recursive tree responses by both entry count and response
    size.  When that response is truncated, walking each subtree preserves the
    complete result instead of silently dropping models.
    """

    encoded_ref = quote(ref, safe="")
    root_url = f"{GITHUB_API}/repos/{repo}/git/trees/{encoded_ref}?recursive=1"
    root = request_json(root_url)
    entries = root.get("tree")
    if not isinstance(entries, list):
        fail(f"GitHub Trees API 缺少 tree 数组：{root_url}")
    if not bool(root.get("truncated", False)):
        return [entry for entry in entries if isinstance(entry, dict)]

    # The recursive endpoint was truncated.  Use the root tree SHA and walk
    # child tree objects one by one.  A visited set protects against malformed
    # API data while a generous bound prevents an accidental unbounded crawl.
    root_sha = str(root.get("sha", "")).strip()
    if not re.fullmatch(r"[0-9a-fA-F]{40}", root_sha):
        fail("GitHub Trees API 被截断，但没有返回可递归的根 tree SHA")
    pending: list[tuple[str, str]] = [("", root_sha)]
    visited: set[str] = set()
    complete: list[dict[str, Any]] = []
    while pending:
        base_path, tree_sha = pending.pop()
        if tree_sha in visited:
            continue
        visited.add(tree_sha)
        if len(visited) > 20_000:
            fail("GitHub tree 子树数量超过安全上限；请缩小 --prefix")
        subtree_url = f"{GITHUB_API}/repos/{repo}/git/trees/{quote(tree_sha, safe='')}"
        subtree = request_json(subtree_url)
        children = subtree.get("tree")
        if not isinstance(children, list):
            fail(f"GitHub 子树响应缺少 tree 数组：{subtree_url}")
        for child in children:
            if not isinstance(child, dict):
                continue
            child_path = str(child.get("path", ""))
            full_path = f"{base_path}/{child_path}".strip("/")
            child_type = str(child.get("type", ""))
            if child_type == "tree":
                child_sha = str(child.get("sha", ""))
                if re.fullmatch(r"[0-9a-fA-F]{40}", child_sha):
                    pending.append((full_path, child_sha))
            else:
                copied = dict(child)
                copied["path"] = full_path
                complete.append(copied)
    return complete


def github_sources(
    repo: str,
    ref: str,
    prefixes: list[str],
    max_files: int,
) -> list[dict[str, Any]]:
    entries = github_tree_entries(repo, ref)
    candidates: list[dict[str, Any]] = []
    for entry in entries:
        path = str(entry.get("path", ""))
        if str(entry.get("type", "")) != "blob" or not path.lower().endswith(GLB_SUFFIX):
            continue
        if not path_matches_prefix(path, prefixes):
            continue
        candidates.append(
            {
                "path": path,
                "treeByteLength": int(entry.get("size", 0) or 0),
                "sourceUrl": (
                    f"https://github.com/{repo}/blob/{ref}/"
                    f"{quote(path, safe='/')}"
                ),
                "downloadUrl": (
                    f"https://raw.githubusercontent.com/{repo}/{ref}/"
                    f"{quote(path, safe='/') }"
                ),
            }
        )
    candidates.sort(key=lambda item: str(item["path"]).casefold())
    return candidates[:max_files]


def local_sources(source_dir: Path, prefixes: list[str], max_files: int) -> list[dict[str, Any]]:
    if not source_dir.is_dir():
        fail(f"--source-dir 不是目录：{source_dir}")
    candidates: list[dict[str, Any]] = []
    for path in sorted(source_dir.rglob("*")):
        if not path.is_file() or path.suffix.lower() != GLB_SUFFIX:
            continue
        relative = path.relative_to(source_dir).as_posix()
        if not path_matches_prefix(relative, prefixes):
            continue
        candidates.append(
            {
                "path": relative,
                "localPath": str(path),
                "treeByteLength": path.stat().st_size,
                "sourceUrl": "",
                "downloadUrl": "",
            }
        )
    return candidates[:max_files]


def copy_remote(url: str, destination: Path, maximum: int) -> None:
    request = Request(url, headers={"User-Agent": GITHUB_USER_AGENT})
    try:
        with urlopen(request, timeout=90) as response:
            declared = response.headers.get("Content-Length")
            if declared is not None and int(declared) > maximum:
                fail(f"远程 GLB 超过大小上限（{declared} bytes）")
            written = 0
            with destination.open("wb") as output:
                while True:
                    chunk = response.read(1024 * 1024)
                    if not chunk:
                        break
                    written += len(chunk)
                    if written > maximum:
                        fail(f"远程 GLB 超过大小上限（>{maximum} bytes）")
                    output.write(chunk)
    except (HTTPError, URLError, TimeoutError, OSError, ValueError) as error:
        fail(f"远程 GLB 下载失败：{url} ({error})")


def image_dimensions(payload: bytes, mime_type: str) -> tuple[int, int] | None:
    """Read common embedded image dimensions without requiring Pillow."""

    if payload.startswith(b"\x89PNG\r\n\x1a\n") and len(payload) >= 24:
        width = int.from_bytes(payload[16:20], "big")
        height = int.from_bytes(payload[20:24], "big")
        return (width, height) if width > 0 and height > 0 else None
    if payload.startswith(b"\xff\xd8"):
        cursor = 2
        while cursor + 9 <= len(payload):
            if payload[cursor] != 0xFF:
                cursor += 1
                continue
            marker = payload[cursor + 1]
            cursor += 2
            if marker in {0xD8, 0xD9}:
                continue
            if cursor + 2 > len(payload):
                break
            segment_length = int.from_bytes(payload[cursor:cursor + 2], "big")
            if segment_length < 2 or cursor + segment_length > len(payload):
                break
            if marker in set(range(0xC0, 0xC4)) | set(range(0xC5, 0xC8)) | \
                set(range(0xC9, 0xCC)) | set(range(0xCD, 0xD0)):
                if segment_length >= 7:
                    height = int.from_bytes(payload[cursor + 3:cursor + 5], "big")
                    width = int.from_bytes(payload[cursor + 5:cursor + 7], "big")
                    return (width, height) if width > 0 and height > 0 else None
            cursor += segment_length
    # Keep MIME type in the report even when a less common image codec has no
    # cheap standard-library header parser.
    return None


def embedded_image_payload(
    document: dict[str, Any], binary: bytes, image: dict[str, Any]
) -> bytes | None:
    uri = image.get("uri")
    if isinstance(uri, str) and uri.startswith("data:"):
        try:
            encoded = uri.split(",", 1)[1]
            return base64.b64decode(encoded, validate=True)
        except (IndexError, binascii.Error):
            return None
    view_index = image.get("bufferView")
    views = document.get("bufferViews", [])
    if not isinstance(view_index, int) or not 0 <= view_index < len(views):
        return None
    view = views[view_index]
    if not isinstance(view, dict):
        return None
    start = int(view.get("byteOffset", 0) or 0)
    length = int(view.get("byteLength", 0) or 0)
    if start < 0 or length < 0 or start + length > len(binary):
        return None
    return binary[start:start + length]


def position_bounds(document: dict[str, Any], binary: bytes) -> tuple[list[float], list[float]] | None:
    minimum = [float("inf"), float("inf"), float("inf")]
    maximum = [float("-inf"), float("-inf"), float("-inf")]
    found = False
    accessors = document.get("accessors", [])
    for mesh in document.get("meshes", []):
        if not isinstance(mesh, dict):
            continue
        for primitive in mesh.get("primitives", []):
            if not isinstance(primitive, dict):
                continue
            attributes = primitive.get("attributes", {})
            if not isinstance(attributes, dict) or not isinstance(attributes.get("POSITION"), int):
                continue
            accessor_index = attributes["POSITION"]
            if not 0 <= accessor_index < len(accessors):
                continue
            accessor = accessors[accessor_index]
            if not isinstance(accessor, dict):
                continue
            lower = accessor.get("min")
            upper = accessor.get("max")
            if not isinstance(lower, list) or not isinstance(upper, list) or len(lower) < 3 or len(upper) < 3:
                try:
                    values = PREPARER.decode_accessor(document, binary, accessor_index)
                except (ValueError, IndexError, TypeError):
                    continue
                if not values:
                    continue
                lower = [min(row[index] for row in values) for index in range(3)]
                upper = [max(row[index] for row in values) for index in range(3)]
            for index in range(3):
                minimum[index] = min(minimum[index], float(lower[index]))
                maximum[index] = max(maximum[index], float(upper[index]))
            found = True
    return (minimum, maximum) if found else None


def triangle_count(document: dict[str, Any]) -> int:
    accessors = document.get("accessors", [])
    total = 0
    for mesh in document.get("meshes", []):
        if not isinstance(mesh, dict):
            continue
        for primitive in mesh.get("primitives", []):
            if not isinstance(primitive, dict):
                continue
            mode = int(primitive.get("mode", 4) or 4)
            indices = primitive.get("indices")
            count = 0
            if isinstance(indices, int) and 0 <= indices < len(accessors):
                accessor = accessors[indices]
                if isinstance(accessor, dict):
                    count = int(accessor.get("count", 0) or 0)
            if count == 0:
                attributes = primitive.get("attributes", {})
                position = attributes.get("POSITION") if isinstance(attributes, dict) else None
                if isinstance(position, int) and 0 <= position < len(accessors):
                    accessor = accessors[position]
                    if isinstance(accessor, dict):
                        count = int(accessor.get("count", 0) or 0)
            if mode == 4:  # TRIANGLES
                total += count // 3
            elif mode in {5, 6}:  # TRIANGLE_STRIP / TRIANGLE_FAN
                total += max(0, count - 2)
    return total


def inferred_content_id(path: str) -> str:
    # Keep variant suffixes out of the canonical object id.  For example both
    # ``Scp178-1.glb`` and ``Scp178.glb`` map to ``scp-178`` and can be
    # disambiguated later with the suggested asset id/hash.
    match = re.search(r"scp[_-]?([0-9]{3,5})", path.casefold())
    return f"scp-{match.group(1)}" if match else ""


def inspect_file(
    source: dict[str, Any],
    path: Path,
    maximum_triangles: int,
    maximum_texture: int,
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "path": source["path"],
        "sourceUrl": source.get("sourceUrl", ""),
        "downloadUrl": source.get("downloadUrl", ""),
        "treeByteLength": source.get("treeByteLength", 0),
        "inferredContentId": inferred_content_id(str(source["path"])),
        "status": "error",
    }
    try:
        payload = path.read_bytes()
        result["byteLength"] = len(payload)
        result["sha256"] = hashlib.sha256(payload).hexdigest()
        declared_size = int(source.get("treeByteLength", 0) or 0)
        result["treeSizeMatches"] = declared_size <= 0 or declared_size == len(payload)
        if not result["treeSizeMatches"]:
            result["sizeError"] = (
                f"上游树条目声明 {declared_size} bytes，实际下载 {len(payload)} bytes"
            )
        document, binary = PREPARER.read_glb(path)
        PREPARER.validate_self_contained(document)
        result["glbVersion"] = 2
        result["meshCount"] = len(document.get("meshes", []))
        result["nodeCount"] = len(document.get("nodes", []))
        result["materialCount"] = len(document.get("materials", []))
        result["estimatedTriangleCount"] = triangle_count(document)
        result["extensionsUsed"] = sorted(PREPARER._extension_names(document))
        try:
            PREPARER.validate_supported_extensions(document)
            result["unsupportedExtensions"] = []
        except ValueError as error:
            result["unsupportedExtensions"] = sorted(
                set(result["extensionsUsed"]) & PREPARER.FORBIDDEN_EXTENSIONS
            )
            result["extensionError"] = str(error)
        external: list[str] = []
        for index, buffer in enumerate(document.get("buffers", [])):
            if isinstance(buffer, dict) and buffer.get("uri"):
                external.append(f"buffer[{index}]")
        for index, image in enumerate(document.get("images", [])):
            if isinstance(image, dict):
                uri = image.get("uri")
                if isinstance(uri, str) and uri and not uri.startswith("data:"):
                    external.append(f"image[{index}]")
        result["externalDependencies"] = external
        result["hasExternalDependencies"] = len(external) > 0
        result["animations"] = []
        for index, animation in enumerate(document.get("animations", [])):
            if not isinstance(animation, dict):
                continue
            try:
                start, end = PREPARER.animation_bounds(document, binary, animation)
            except (ValueError, IndexError, TypeError):
                start, end = 0.0, 0.0
            result["animations"].append(
                {
                    "name": str(animation.get("name", "")) or f"animation-{index}",
                    "startSeconds": start,
                    "endSeconds": end,
                    "durationSeconds": max(0.0, end - start),
                }
            )
        result["embeddedImages"] = []
        for index, image in enumerate(document.get("images", [])):
            if not isinstance(image, dict):
                continue
            mime_type = str(image.get("mimeType", ""))
            image_payload = embedded_image_payload(document, binary, image)
            dimensions = image_dimensions(image_payload or b"", mime_type)
            item: dict[str, Any] = {
                "index": index,
                "mimeType": mime_type,
                "byteLength": len(image_payload) if image_payload is not None else 0,
                "embedded": image_payload is not None,
            }
            if dimensions is not None:
                item["width"], item["height"] = dimensions
            result["embeddedImages"].append(item)
        bounds = position_bounds(document, binary)
        if bounds is not None:
            result["positionBounds"] = {"min": bounds[0], "max": bounds[1]}
            result["positionBoundsSize"] = [
                bounds[1][index] - bounds[0][index] for index in range(3)
            ]
        result["reviewHints"] = {
            "assetIdSuggestion": (
                f"{result['inferredContentId']}-candidate-{result['sha256'][:8]}"
                if result["inferredContentId"]
                else f"candidate-{result['sha256'][:8]}"
            ),
            "sourceLabelSuggestion": source.get("sourceUrl", "") or str(source["path"]),
            "requiresExplicitPoseReview": len(result["animations"]) > 0,
            "exceedsTriangleBudget": result["estimatedTriangleCount"] > maximum_triangles,
            "exceedsTextureBudget": any(
                max(int(image.get("width", 0)), int(image.get("height", 0))) > maximum_texture
                for image in result["embeddedImages"]
            ),
        }
        if not result["treeSizeMatches"]:
            result["status"] = "reject_size_mismatch"
        elif result["hasExternalDependencies"]:
            result["status"] = "reject_external_dependencies"
        elif result["unsupportedExtensions"]:
            result["status"] = "reject_unsupported_extension"
        elif result["reviewHints"]["requiresExplicitPoseReview"]:
            result["status"] = "needs_pose_review"
        elif result["reviewHints"]["exceedsTriangleBudget"] or result["reviewHints"]["exceedsTextureBudget"]:
            result["status"] = "needs_budget_review"
        else:
            result["status"] = "eligible_candidate"
    except Exception as error:  # report one bad candidate without aborting the batch
        result["error"] = str(error)
    return result


def inspect_one(
    source: dict[str, Any],
    temporary_root: Path,
    maximum_bytes: int,
    maximum_triangles: int,
    maximum_texture: int,
) -> dict[str, Any]:
    tree_size = int(source.get("treeByteLength", 0) or 0)
    if tree_size > maximum_bytes:
        return {
            "path": source["path"],
            "sourceUrl": source.get("sourceUrl", ""),
            "downloadUrl": source.get("downloadUrl", ""),
            "treeByteLength": tree_size,
            "inferredContentId": inferred_content_id(str(source["path"])),
            "status": "skipped_size_limit",
            "error": f"上游声明大小 {tree_size} bytes，超过 {maximum_bytes} bytes 上限",
        }
    local_path = source.get("localPath")
    if local_path:
        return inspect_file(source, Path(str(local_path)), maximum_triangles, maximum_texture)
    destination = temporary_root / hashlib.sha256(str(source["path"]).encode()).hexdigest()[:16]
    try:
        copy_remote(str(source["downloadUrl"]), destination, maximum_bytes)
        return inspect_file(source, destination, maximum_triangles, maximum_texture)
    except Exception as error:
        return {
            "path": source["path"],
            "sourceUrl": source.get("sourceUrl", ""),
            "downloadUrl": source.get("downloadUrl", ""),
            "treeByteLength": tree_size,
            "inferredContentId": inferred_content_id(str(source["path"])),
            "status": "download_error",
            "error": str(error),
        }


def parse_args(argv: Iterable[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="批量检查 Anomicon 三维档案 GLB 候选")
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--repo", help="公开 GitHub 仓库，例如 Yni-Viar/scp-assets")
    source.add_argument("--source-dir", type=Path, help="本地 GLB 目录（递归扫描）")
    parser.add_argument(
        "--ref",
        help="GitHub 固定 commit SHA（远程模式必填，必须为 40 位十六进制）",
    )
    parser.add_argument("--prefix", action="append", default=[], help="只扫描指定目录，可重复")
    parser.add_argument("--max-files", type=int, default=128)
    parser.add_argument("--max-bytes", type=int, default=DEFAULT_MAX_BYTES)
    parser.add_argument("--max-triangles", type=int, default=DEFAULT_MAX_TRIANGLES)
    parser.add_argument("--max-texture", type=int, default=DEFAULT_MAX_TEXTURE)
    parser.add_argument("--workers", type=int, default=6)
    parser.add_argument("--output", type=Path, help="JSON 报告输出路径；省略则输出到 stdout")
    args = parser.parse_args(argv)
    if args.repo and not re.fullmatch(r"[^/\s]+/[^/\s]+", args.repo):
        parser.error("--repo 必须为 owner/repository")
    if args.repo and not re.fullmatch(r"[0-9a-fA-F]{40}", str(args.ref or "")):
        parser.error("远程扫描必须使用固定的 40 位 commit SHA，不能使用 moving branch")
    if args.max_files <= 0 or args.max_bytes <= 0 or args.max_triangles <= 0 or args.max_texture < 64:
        parser.error("大小、数量和预算参数必须为正数，--max-texture 至少为 64")
    if args.workers <= 0 or args.workers > 16:
        parser.error("--workers 必须在 1..16 之间")
    args.prefix = [normalized_prefix(value) for value in args.prefix]
    return args


def main(argv: Iterable[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        sources = (
            github_sources(args.repo, args.ref, args.prefix, args.max_files)
            if args.repo
            else local_sources(args.source_dir.resolve(), args.prefix, args.max_files)
        )
        report: dict[str, Any] = {
            "schemaVersion": 1,
            "tool": "tools/archive3d/inspect_archive_batch.py",
            "source": {
                "repository": args.repo or "",
                "ref": args.ref or "",
                "prefixes": args.prefix,
                "localDirectory": str(args.source_dir.resolve()) if args.source_dir else "",
            },
            "limits": {
                "maxBytes": args.max_bytes,
                "maxTriangles": args.max_triangles,
                "maxTexture": args.max_texture,
            },
            "candidates": [],
        }
        with tempfile.TemporaryDirectory(prefix="anomicon-archive-scan-") as temporary:
            temporary_root = Path(temporary)
            with ThreadPoolExecutor(max_workers=args.workers) as executor:
                futures = [
                    executor.submit(
                        inspect_one,
                        source,
                        temporary_root,
                        args.max_bytes,
                        args.max_triangles,
                        args.max_texture,
                    )
                    for source in sources
                ]
                for future in as_completed(futures):
                    report["candidates"].append(future.result())
        report["candidates"].sort(key=lambda item: str(item.get("path", "")).casefold())
        report["summary"] = {
            "discovered": len(sources),
            "eligible": sum(item.get("status") == "eligible_candidate" for item in report["candidates"]),
            "needsReview": sum(str(item.get("status", "")).startswith("needs_") for item in report["candidates"]),
            "rejectedOrSkipped": sum(
                str(item.get("status", "")).startswith("reject_") or
                str(item.get("status", "")).startswith("skip") or
                str(item.get("status", "")).endswith("error")
                for item in report["candidates"]
            ),
        }
        encoded = json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(encoded, encoding="utf-8")
            print(f"wrote {args.output} ({len(report['candidates'])} candidates)")
        else:
            print(encoded, end="")
        return 0
    except (OSError, ValueError, RuntimeError) as error:
        print(f"inspect_archive_batch: error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
