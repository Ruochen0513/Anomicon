#!/usr/bin/env python3
"""Prepare a reviewed glTF 2.0 binary for the Anomicon mobile archive.

The archive viewer consumes static, self-contained GLB files.  This utility is
the reproducible build-time boundary between an upstream animated asset and
that runtime format:

* sample one animation clip at a deterministic time and bake its TRS values;
* remove animation objects and accessors that become unreachable;
* resize embedded images (PNG/JPEG/etc.) to a mobile-safe maximum;
* repack the remaining buffer views into one aligned BIN chunk; and
* add ``AnomiconModelOffset`` and ``AnomiconInteractivePivot`` scene roots.

No runtime compression extension is added.  In particular, Draco, Meshopt and
KTX/BasisU assets are rejected because the native ArkGraphics3D loader used by
the app is intentionally kept on the conservative core glTF 2.0 path.

This script only changes a destination file.  Source files and product
resources are never modified in place.
"""

from __future__ import annotations

import argparse
import base64
import binascii
import bisect
import hashlib
import io
import json
import math
import struct
import sys
import urllib.parse
from pathlib import Path
from typing import Any, Iterable, NoReturn, Sequence


GLB_MAGIC = 0x46546C67  # ``glTF`` little endian
GLB_VERSION = 2
JSON_CHUNK_TYPE = 0x4E4F534A  # ``JSON`` little endian
BIN_CHUNK_TYPE = 0x004E4942  # ``BIN\0`` little endian

ARCHIVE_OFFSET_NAME = "AnomiconModelOffset"
ARCHIVE_PIVOT_NAME = "AnomiconInteractivePivot"
ASSET_PLACEMENT_NAME = "AnomiconAssetPlacement"
FORBIDDEN_EXTENSIONS = {
    "KHR_draco_mesh_compression",
    "EXT_meshopt_compression",
    "KHR_texture_basisu",
}

COMPONENT_INFO: dict[int, tuple[str, int, bool]] = {
    # struct format, byte width, signed integer flag
    5120: ("b", 1, True),
    5121: ("B", 1, False),
    5122: ("h", 2, True),
    5123: ("H", 2, False),
    5125: ("I", 4, False),
    5126: ("f", 4, True),
}
TYPE_COMPONENT_COUNT: dict[str, int] = {
    "SCALAR": 1,
    "VEC2": 2,
    "VEC3": 3,
    "VEC4": 4,
    "MAT2": 4,
    "MAT3": 9,
    "MAT4": 16,
}


Number = int | float
Vector = list[float]


def align4(value: int) -> int:
    """Return the next four-byte aligned offset."""

    return (value + 3) & ~3


def _fail(message: str) -> NoReturn:
    raise ValueError(message)


def read_glb(path: Path) -> tuple[dict[str, Any], bytes]:
    """Read and validate a GLB 2.0 file, returning JSON and its BIN payload."""

    payload = path.read_bytes()
    if len(payload) < 20:
        _fail(f"{path} is too small to be a GLB 2.0 file")
    magic, version, declared_length = struct.unpack_from("<III", payload, 0)
    if magic != GLB_MAGIC or version != GLB_VERSION:
        _fail(f"{path} is not a glTF 2.0 binary")
    if declared_length != len(payload):
        _fail(
            f"{path} has an invalid declared length "
            f"({declared_length}, actual {len(payload)})"
        )

    cursor = 12
    document: dict[str, Any] | None = None
    binary = b""
    while cursor + 8 <= len(payload):
        chunk_length, chunk_type = struct.unpack_from("<II", payload, cursor)
        cursor += 8
        end = cursor + chunk_length
        if end > len(payload):
            _fail(f"{path} contains a truncated GLB chunk")
        chunk = payload[cursor:end]
        cursor = end
        if chunk_type == JSON_CHUNK_TYPE:
            if document is not None:
                _fail(f"{path} contains more than one JSON chunk")
            try:
                document = json.loads(chunk.decode("utf-8").rstrip(" \0"))
            except (UnicodeDecodeError, json.JSONDecodeError) as error:
                _fail(f"{path} contains invalid GLB JSON: {error}")
        elif chunk_type == BIN_CHUNK_TYPE:
            if binary:
                _fail(f"{path} contains more than one BIN chunk")
            binary = chunk
        # Unknown chunks are intentionally ignored on output.  They are not
        # part of the core scene data and may contain exporter-specific state.

    if document is None:
        _fail(f"{path} is missing its JSON chunk")
    if not isinstance(document, dict):
        _fail(f"{path} JSON root is not an object")
    asset = document.get("asset")
    if not isinstance(asset, dict) or str(asset.get("version", "")).split(".")[0] != "2":
        _fail(f"{path} does not declare glTF asset version 2.x")
    if not binary:
        # A valid empty BIN is legal for a scene containing no geometry.  Keep
        # the distinction from a missing chunk by checking chunk presence.
        has_bin = any(
            struct.unpack_from("<II", payload, offset)[1] == BIN_CHUNK_TYPE
            for offset in _chunk_offsets(payload)
        )
        if not has_bin:
            _fail(f"{path} is missing its BIN chunk")
    return document, binary


def _chunk_offsets(payload: bytes) -> Iterable[int]:
    cursor = 12
    while cursor + 8 <= len(payload):
        yield cursor
        length = struct.unpack_from("<I", payload, cursor)[0]
        cursor += 8 + length


def write_glb(path: Path, document: dict[str, Any], binary: bytes) -> None:
    """Write a canonical JSON + BIN GLB 2.0 file."""

    json_bytes = json.dumps(
        document,
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")
    json_bytes += b" " * (align4(len(json_bytes)) - len(json_bytes))
    padded_binary = binary + b"\0" * (align4(len(binary)) - len(binary))
    total_length = 12 + 8 + len(json_bytes) + 8 + len(padded_binary)
    payload = bytearray(struct.pack("<III", GLB_MAGIC, GLB_VERSION, total_length))
    payload.extend(struct.pack("<II", len(json_bytes), JSON_CHUNK_TYPE))
    payload.extend(json_bytes)
    payload.extend(struct.pack("<II", len(padded_binary), BIN_CHUNK_TYPE))
    payload.extend(padded_binary)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)


def _extension_names(document: dict[str, Any]) -> set[str]:
    """Collect declared and nested extension names without guessing semantics."""

    names = set(str(name) for name in document.get("extensionsUsed", []))
    names.update(str(name) for name in document.get("extensionsRequired", []))

    def walk(value: Any) -> None:
        if isinstance(value, dict):
            extensions = value.get("extensions")
            if isinstance(extensions, dict):
                names.update(str(name) for name in extensions)
            for child in value.values():
                walk(child)
        elif isinstance(value, list):
            for child in value:
                walk(child)

    walk(document)
    return names


def validate_supported_extensions(document: dict[str, Any]) -> None:
    forbidden = sorted(_extension_names(document) & FORBIDDEN_EXTENSIONS)
    if forbidden:
        joined = ", ".join(forbidden)
        raise ValueError(
            f"asset uses unsupported compression/texture extension(s): {joined}; "
            "export an uncompressed GLB before preparing it"
        )


def validate_self_contained(document: dict[str, Any]) -> None:
    """Reject external payloads that cannot be copied into a single GLB.

    The runtime archive deliberately has no network/file-URI resolver. A
    source GLB with an external buffer or image would otherwise look valid
    after repacking while silently losing those bytes.
    """

    for index, buffer in enumerate(document.get("buffers", [])):
        if isinstance(buffer, dict) and buffer.get("uri"):
            _fail(
                f"buffer {index} has an external URI; provide a self-contained GLB"
            )
    for index, image in enumerate(document.get("images", [])):
        if not isinstance(image, dict):
            continue
        uri = image.get("uri")
        if isinstance(uri, str) and uri and not uri.startswith("data:"):
            _fail(
                f"image {index} has an external URI; embed it before preparation"
            )


def _component_format(component_type: int) -> tuple[str, int, bool]:
    try:
        return COMPONENT_INFO[component_type]
    except KeyError:
        _fail(f"unsupported glTF accessor componentType {component_type}")


def _normalize_component(value: Number, component_type: int, normalized: bool) -> float:
    if not normalized or component_type == 5126:
        return float(value)
    if component_type == 5120:
        return max(float(value) / 127.0, -1.0)
    if component_type == 5121:
        return float(value) / 255.0
    if component_type == 5122:
        return max(float(value) / 32767.0, -1.0)
    if component_type == 5123:
        return float(value) / 65535.0
    if component_type == 5125:
        return float(value) / 4294967295.0
    return float(value)


def decode_accessor(
    document: dict[str, Any],
    binary: bytes,
    accessor_index: int,
    _stack: set[int] | None = None,
) -> list[list[float]]:
    """Decode a glTF accessor into vectors, including sparse overlays.

    Animation data is normally float VEC3/VEC4, but accepting all core scalar
    component types makes the utility useful for unusual exporters and lets us
    fail with a clear message instead of silently producing a wrong pose.
    """

    accessors = document.get("accessors", [])
    if not isinstance(accessor_index, int) or not 0 <= accessor_index < len(accessors):
        _fail(f"accessor index {accessor_index!r} is out of range")
    accessor = accessors[accessor_index]
    if not isinstance(accessor, dict):
        _fail(f"accessor {accessor_index} is not an object")
    component_type = int(accessor.get("componentType", 0))
    fmt, component_size, _ = _component_format(component_type)
    accessor_type = str(accessor.get("type", ""))
    component_count = TYPE_COMPONENT_COUNT.get(accessor_type)
    if component_count is None:
        _fail(f"accessor {accessor_index} has unsupported type {accessor_type!r}")
    count = int(accessor.get("count", 0))
    if count < 0:
        _fail(f"accessor {accessor_index} has a negative count")

    values: list[list[float]] = [
        [0.0] * component_count for _ in range(count)
    ]
    view_index = accessor.get("bufferView")
    if view_index is not None:
        views = document.get("bufferViews", [])
        if not isinstance(view_index, int) or not 0 <= view_index < len(views):
            _fail(f"accessor {accessor_index} references an invalid bufferView")
        view = views[view_index]
        if not isinstance(view, dict):
            _fail(f"bufferView {view_index} is not an object")
        view_start = int(view.get("byteOffset", 0))
        view_length = int(view.get("byteLength", 0))
        accessor_offset = int(accessor.get("byteOffset", 0))
        element_size = component_count * component_size
        stride = int(view.get("byteStride", element_size))
        if stride < element_size:
            _fail(f"bufferView {view_index} byteStride is smaller than its element")
        base = view_start + accessor_offset
        if base < 0 or view_start + view_length > len(binary):
            _fail(f"accessor {accessor_index} points outside the GLB BIN chunk")
        unpack = struct.Struct("<" + fmt)
        for row in range(count):
            row_start = base + row * stride
            row_end = row_start + element_size
            if row_end > view_start + view_length or row_end > len(binary):
                _fail(f"accessor {accessor_index} element {row} exceeds its bufferView")
            values[row] = [
                _normalize_component(
                    unpack.unpack_from(binary, row_start + component * component_size)[0],
                    component_type,
                    bool(accessor.get("normalized", False)),
                )
                for component in range(component_count)
            ]

    sparse = accessor.get("sparse")
    if sparse:
        if _stack is None:
            _stack = set()
        if accessor_index in _stack:
            _fail(f"accessor {accessor_index} has a cyclic sparse definition")
        _stack.add(accessor_index)
        try:
            sparse_count = int(sparse.get("count", 0))
            indices_info = sparse.get("indices", {})
            values_info = sparse.get("values", {})
            if not isinstance(indices_info, dict) or not isinstance(values_info, dict):
                _fail(f"accessor {accessor_index} has malformed sparse data")
            index_component_type = int(indices_info.get("componentType", 0))
            index_fmt, index_size, _ = _component_format(index_component_type)
            if index_component_type not in (5121, 5123, 5125):
                _fail("sparse accessor indices must use an unsigned integer type")
            views = document.get("bufferViews", [])
            index_view_index = indices_info.get("bufferView")
            value_view_index = values_info.get("bufferView")
            if not isinstance(index_view_index, int) or not isinstance(value_view_index, int):
                _fail("sparse accessor is missing its bufferView references")
            index_view = views[index_view_index]
            value_view = views[value_view_index]
            index_base = int(index_view.get("byteOffset", 0)) + int(
                indices_info.get("byteOffset", 0)
            )
            value_base = int(value_view.get("byteOffset", 0)) + int(
                values_info.get("byteOffset", 0)
            )
            index_unpack = struct.Struct("<" + index_fmt)
            value_unpack = struct.Struct("<" + fmt)
            for sparse_row in range(sparse_count):
                index_at = index_base + sparse_row * index_size
                target = index_unpack.unpack_from(binary, index_at)[0]
                if not 0 <= target < count:
                    _fail(f"sparse accessor {accessor_index} targets row {target} out of range")
                row_start = value_base + sparse_row * component_count * component_size
                values[target] = [
                    _normalize_component(
                        value_unpack.unpack_from(binary, row_start + component * component_size)[0],
                        component_type,
                        bool(accessor.get("normalized", False)),
                    )
                    for component in range(component_count)
                ]
        finally:
            _stack.remove(accessor_index)
    return values


def _vector(values: Sequence[Number], size: int) -> Vector:
    if len(values) != size:
        _fail(f"animation value has {len(values)} components; expected {size}")
    return [float(value) for value in values]


def _lerp(a: Sequence[Number], b: Sequence[Number], amount: float) -> Vector:
    return [float(x) + (float(y) - float(x)) * amount for x, y in zip(a, b)]


def _normalize_quaternion(value: Sequence[Number]) -> Vector:
    q = _vector(value, 4)
    length = math.sqrt(sum(component * component for component in q))
    if length < 1e-12:
        return [0.0, 0.0, 0.0, 1.0]
    return [component / length for component in q]


def _slerp(a: Sequence[Number], b: Sequence[Number], amount: float) -> Vector:
    first = _normalize_quaternion(a)
    second = _normalize_quaternion(b)
    dot = sum(x * y for x, y in zip(first, second))
    if dot < 0.0:
        second = [-component for component in second]
        dot = -dot
    if dot > 0.9995:
        return _normalize_quaternion(_lerp(first, second, amount))
    dot = max(-1.0, min(1.0, dot))
    angle = math.acos(dot)
    sine = math.sin(angle)
    if abs(sine) < 1e-12:
        return first
    first_weight = math.sin((1.0 - amount) * angle) / sine
    second_weight = math.sin(amount * angle) / sine
    return _normalize_quaternion([
        first_weight * x + second_weight * y
        for x, y in zip(first, second)
    ])


def _hermite(
    value0: Sequence[Number],
    outgoing_tangent: Sequence[Number],
    value1: Sequence[Number],
    incoming_tangent: Sequence[Number],
    amount: float,
    duration: float,
) -> Vector:
    t = amount
    t2 = t * t
    t3 = t2 * t
    h00 = 2.0 * t3 - 3.0 * t2 + 1.0
    h10 = t3 - 2.0 * t2 + t
    h01 = -2.0 * t3 + 3.0 * t2
    h11 = t3 - t2
    return [
        h00 * float(v0)
        + h10 * duration * float(t0)
        + h01 * float(v1)
        + h11 * duration * float(t1)
        for v0, t0, v1, t1 in zip(
            value0, outgoing_tangent, value1, incoming_tangent
        )
    ]


def _sample_channel(
    document: dict[str, Any],
    binary: bytes,
    sampler: dict[str, Any],
    sample_time: float,
    path: str,
) -> Vector:
    input_index = sampler.get("input")
    output_index = sampler.get("output")
    if not isinstance(input_index, int) or not isinstance(output_index, int):
        _fail("animation sampler is missing input/output accessors")
    time_rows = decode_accessor(document, binary, input_index)
    output_rows = decode_accessor(document, binary, output_index)
    times = [row[0] for row in time_rows]
    if not times:
        _fail("animation sampler has no keyframes")
    if any(times[index] > times[index + 1] for index in range(len(times) - 1)):
        _fail("animation sampler keyframe times are not sorted")
    interpolation = str(sampler.get("interpolation", "LINEAR")).upper()
    if interpolation not in {"STEP", "LINEAR", "CUBICSPLINE"}:
        _fail(f"unsupported animation interpolation {interpolation!r}")
    component_count = {"translation": 3, "scale": 3, "rotation": 4}.get(path)
    if component_count is None:
        _fail(f"animation path {path!r} is not a TRS property")

    key_count = len(times)
    if interpolation == "CUBICSPLINE":
        if len(output_rows) != key_count * 3:
            _fail("CUBICSPLINE output count must be three times the input count")
        rows = [
            (
                _vector(output_rows[index * 3], component_count),
                _vector(output_rows[index * 3 + 1], component_count),
                _vector(output_rows[index * 3 + 2], component_count),
            )
            for index in range(key_count)
        ]
    else:
        if len(output_rows) != key_count:
            _fail("animation output count does not match input count")
        rows = [(_vector(row, component_count),) for row in output_rows]

    if sample_time <= times[0]:
        result = rows[0][1] if interpolation == "CUBICSPLINE" else rows[0][0]
    elif sample_time >= times[-1]:
        result = rows[-1][1] if interpolation == "CUBICSPLINE" else rows[-1][0]
    elif interpolation == "STEP":
        # STEP holds the most recent key, including when the sample lands
        # exactly on a later key. ``bisect_right`` is important here: using a
        # ``>=`` search would incorrectly keep the previous value at a key
        # boundary.
        key = bisect.bisect_right(times, sample_time) - 1
        result = rows[max(0, key)][0]
    else:
        right = bisect.bisect_right(times, sample_time)
        left = max(0, right - 1)
        span = times[right] - times[left]
        amount = 0.0 if span <= 1e-12 else (sample_time - times[left]) / span
        if interpolation == "LINEAR":
            if path == "rotation":
                result = _slerp(rows[left][0], rows[right][0], amount)
            else:
                result = _lerp(rows[left][0], rows[right][0], amount)
        else:
            result = _hermite(
                rows[left][1],
                rows[left][2],
                rows[right][1],
                rows[right][0],
                amount,
                span,
            )
            if path == "rotation":
                result = _normalize_quaternion(result)
    if path == "rotation":
        result = _normalize_quaternion(result)
    return result


def _quaternion_from_matrix(matrix: Sequence[float]) -> Vector:
    # Matrix values in glTF are column-major.  We receive the upper-left 3x3
    # after removing scale, represented as row-major values below.
    m00, m01, m02, m10, m11, m12, m20, m21, m22 = matrix
    trace = m00 + m11 + m22
    if trace > 0.0:
        factor = math.sqrt(trace + 1.0) * 2.0
        return _normalize_quaternion([
            (m21 - m12) / factor,
            (m02 - m20) / factor,
            (m10 - m01) / factor,
            0.25 * factor,
        ])
    if m00 > m11 and m00 > m22:
        factor = math.sqrt(max(1e-12, 1.0 + m00 - m11 - m22)) * 2.0
        return _normalize_quaternion([
            0.25 * factor,
            (m01 + m10) / factor,
            (m02 + m20) / factor,
            (m21 - m12) / factor,
        ])
    if m11 > m22:
        factor = math.sqrt(max(1e-12, 1.0 + m11 - m00 - m22)) * 2.0
        return _normalize_quaternion([
            (m01 + m10) / factor,
            0.25 * factor,
            (m12 + m21) / factor,
            (m02 - m20) / factor,
        ])
    factor = math.sqrt(max(1e-12, 1.0 + m22 - m00 - m11)) * 2.0
    return _normalize_quaternion([
        (m02 + m20) / factor,
        (m12 + m21) / factor,
        0.25 * factor,
        (m10 - m01) / factor,
    ])


def _decompose_matrix(matrix: Sequence[Number]) -> tuple[Vector, Vector, Vector]:
    if len(matrix) != 16:
        _fail("node matrix must contain 16 values")
    values = [float(value) for value in matrix]
    translation = [values[12], values[13], values[14]]
    columns = [
        [values[0], values[1], values[2]],
        [values[4], values[5], values[6]],
        [values[8], values[9], values[10]],
    ]
    scales = [math.sqrt(sum(component * component for component in column)) for column in columns]
    if any(scale < 1e-12 for scale in scales):
        _fail("cannot decompose a node matrix with a zero scale")
    normalized = [
        [component / scales[index] for component in column]
        for index, column in enumerate(columns)
    ]
    determinant = (
        normalized[0][0] * (normalized[1][1] * normalized[2][2] - normalized[1][2] * normalized[2][1])
        - normalized[1][0] * (normalized[0][1] * normalized[2][2] - normalized[0][2] * normalized[2][1])
        + normalized[2][0] * (normalized[0][1] * normalized[1][2] - normalized[0][2] * normalized[1][1])
    )
    if determinant < 0.0:
        scales[0] = -scales[0]
        normalized[0] = [-component for component in normalized[0]]
    # Convert column vectors to a row-major rotation matrix.
    rotation_matrix = [
        normalized[0][0], normalized[1][0], normalized[2][0],
        normalized[0][1], normalized[1][1], normalized[2][1],
        normalized[0][2], normalized[1][2], normalized[2][2],
    ]
    return translation, _quaternion_from_matrix(rotation_matrix), scales


def _ensure_node_trs(node: dict[str, Any]) -> None:
    """Convert a matrix node to explicit TRS before applying an animation."""

    if "matrix" not in node:
        return
    translation, rotation, scale = _decompose_matrix(node["matrix"])
    node.pop("matrix", None)
    node.setdefault("translation", translation)
    node.setdefault("rotation", rotation)
    node.setdefault("scale", scale)


def animation_bounds(
    document: dict[str, Any], binary: bytes, animation: dict[str, Any]
) -> tuple[float, float]:
    start = math.inf
    end = -math.inf
    for sampler in animation.get("samplers", []):
        if not isinstance(sampler, dict):
            continue
        input_index = sampler.get("input")
        if isinstance(input_index, int):
            times = decode_accessor(document, binary, input_index)
            for row in times:
                start = min(start, row[0])
                end = max(end, row[0])
    if not math.isfinite(start) or not math.isfinite(end):
        return 0.0, 0.0
    return start, end


def choose_animation(
    document: dict[str, Any], requested_name: str | None
) -> tuple[int, dict[str, Any]] | None:
    animations = document.get("animations", [])
    if not animations:
        return None
    if requested_name:
        exact = [
            (index, animation)
            for index, animation in enumerate(animations)
            if isinstance(animation, dict) and str(animation.get("name", "")) == requested_name
        ]
        if exact:
            return exact[0]
        folded = requested_name.casefold()
        insensitive = [
            (index, animation)
            for index, animation in enumerate(animations)
            if isinstance(animation, dict) and str(animation.get("name", "")).casefold() == folded
        ]
        if insensitive:
            return insensitive[0]
        available = ", ".join(str(animation.get("name", index)) for index, animation in enumerate(animations))
        _fail(f"animation {requested_name!r} was not found (available: {available})")
    available = ", ".join(
        str(animation.get("name", index))
        for index, animation in enumerate(animations)
        if isinstance(animation, dict)
    )
    _fail(
        "animated sources require an explicit --animation-name so an attack "
        f"or T-pose clip is never selected by accident (available: {available})"
    )


def bake_animation(
    document: dict[str, Any],
    binary: bytes,
    animation_name: str | None,
    seconds: float | None,
    ratio: float,
) -> tuple[str | None, float, float]:
    """Bake one clip and return ``(name, sample_time, duration)``."""

    chosen = choose_animation(document, animation_name)
    if chosen is None:
        if animation_name:
            _fail(
                f"animation {animation_name!r} was requested, but the source has no animations"
            )
        return None, 0.0, 0.0
    _, animation = chosen
    start_time, end_time = animation_bounds(document, binary, animation)
    duration = max(0.0, end_time - start_time)
    if seconds is not None:
        sample_time = max(start_time, min(float(seconds), end_time))
    else:
        sample_time = start_time + max(0.0, min(float(ratio), 1.0)) * duration
    nodes = document.get("nodes", [])
    samplers = animation.get("samplers", [])
    for channel in animation.get("channels", []):
        if not isinstance(channel, dict):
            continue
        target = channel.get("target", {})
        if not isinstance(target, dict):
            continue
        path = str(target.get("path", ""))
        if path not in {"translation", "rotation", "scale"}:
            # Morph weights and extension-specific paths are not TRS.  They
            # cannot be represented by a static node transform, so retain the
            # authored default and make the omission explicit in the report.
            continue
        node_index = target.get("node")
        sampler_index = channel.get("sampler")
        if not isinstance(node_index, int) or not 0 <= node_index < len(nodes):
            _fail("animation channel targets an invalid node")
        if not isinstance(sampler_index, int) or not 0 <= sampler_index < len(samplers):
            _fail("animation channel references an invalid sampler")
        node = nodes[node_index]
        if not isinstance(node, dict):
            _fail(f"animation target node {node_index} is not an object")
        _ensure_node_trs(node)
        node[path] = _sample_channel(
            document,
            binary,
            samplers[sampler_index],
            sample_time,
            path,
        )
    name = str(animation.get("name", "")) or f"animation-{chosen[0]}"
    document.pop("animations", None)
    return name, sample_time, duration


def _collect_accessor_references(document: dict[str, Any]) -> set[int]:
    """Collect accessors needed by geometry, skins, and core extensions."""

    retained: set[int] = set()
    accessors = document.get("accessors", [])

    def add(value: Any) -> None:
        if isinstance(value, int) and 0 <= value < len(accessors):
            retained.add(value)

    for mesh in document.get("meshes", []):
        if not isinstance(mesh, dict):
            continue
        for primitive in mesh.get("primitives", []):
            if not isinstance(primitive, dict):
                continue
            add(primitive.get("indices"))
            attributes = primitive.get("attributes", {})
            if isinstance(attributes, dict):
                for value in attributes.values():
                    add(value)
            for target in primitive.get("targets", []):
                if isinstance(target, dict):
                    for value in target.values():
                        add(value)
    for skin in document.get("skins", []):
        if isinstance(skin, dict):
            add(skin.get("inverseBindMatrices"))

    # Preserve accessor references used by standard/commonly deployed core
    # extensions (for example EXT_mesh_gpu_instancing).  Animation objects have
    # already been deleted, so an accessor left here is genuinely render data.
    def walk(value: Any, key: str = "") -> None:
        if isinstance(value, dict):
            for child_key, child in value.items():
                if child_key in {"accessor", "indices", "inverseBindMatrices"}:
                    add(child)
                elif child_key == "attributes" and isinstance(child, dict):
                    for attribute_value in child.values():
                        add(attribute_value)
                walk(child, child_key)
        elif isinstance(value, list):
            for child in value:
                walk(child, key)

    for node in document.get("nodes", []):
        if isinstance(node, dict):
            walk(node.get("extensions", {}), "extensions")
    return retained


def _collect_buffer_view_references(
    document: dict[str, Any], accessor_ids: set[int]
) -> set[int]:
    views = document.get("bufferViews", [])
    retained: set[int] = set()
    accessors = document.get("accessors", [])
    for index in accessor_ids:
        accessor = accessors[index]
        if not isinstance(accessor, dict):
            continue
        view_index = accessor.get("bufferView")
        if isinstance(view_index, int) and 0 <= view_index < len(views):
            retained.add(view_index)
        sparse = accessor.get("sparse")
        if isinstance(sparse, dict):
            for key in ("indices", "values"):
                info = sparse.get(key)
                if isinstance(info, dict):
                    sparse_view = info.get("bufferView")
                    if isinstance(sparse_view, int) and 0 <= sparse_view < len(views):
                        retained.add(sparse_view)
    # Images are not accessors, but embedded textures live in buffer views.
    for image in document.get("images", []):
        if isinstance(image, dict):
            view_index = image.get("bufferView")
            if isinstance(view_index, int) and 0 <= view_index < len(views):
                retained.add(view_index)

    def walk(value: Any) -> None:
        if isinstance(value, dict):
            for key, child in value.items():
                if key == "bufferView" and isinstance(child, int) and 0 <= child < len(views):
                    retained.add(child)
                walk(child)
        elif isinstance(value, list):
            for child in value:
                walk(child)

    # Keep non-animation extension payloads that point directly to a view.
    walk(document.get("extensions", {}))
    return retained


def _replace_accessor_indices(document: dict[str, Any], mapping: dict[int, int]) -> None:
    for mesh in document.get("meshes", []):
        if not isinstance(mesh, dict):
            continue
        for primitive in mesh.get("primitives", []):
            if not isinstance(primitive, dict):
                continue
            if isinstance(primitive.get("indices"), int):
                primitive["indices"] = mapping[primitive["indices"]]
            attributes = primitive.get("attributes", {})
            if isinstance(attributes, dict):
                for key, value in list(attributes.items()):
                    if isinstance(value, int):
                        attributes[key] = mapping[value]
            for target in primitive.get("targets", []):
                if isinstance(target, dict):
                    for key, value in list(target.items()):
                        if isinstance(value, int):
                            target[key] = mapping[value]
    for skin in document.get("skins", []):
        if isinstance(skin, dict) and isinstance(skin.get("inverseBindMatrices"), int):
            skin["inverseBindMatrices"] = mapping[skin["inverseBindMatrices"]]

    def walk(value: Any) -> None:
        if isinstance(value, dict):
            for key, child in list(value.items()):
                if key in {"accessor", "indices", "inverseBindMatrices"} and isinstance(child, int):
                    if child in mapping:
                        value[key] = mapping[child]
                elif key == "attributes" and isinstance(child, dict):
                    for attribute_key, attribute_value in list(child.items()):
                        if isinstance(attribute_value, int) and attribute_value in mapping:
                            child[attribute_key] = mapping[attribute_value]
                walk(value[key])
        elif isinstance(value, list):
            for child in value:
                walk(child)

    for node in document.get("nodes", []):
        if isinstance(node, dict):
            walk(node.get("extensions", {}))


def _replace_buffer_view_indices(document: dict[str, Any], mapping: dict[int, int]) -> None:
    for accessor in document.get("accessors", []):
        if not isinstance(accessor, dict):
            continue
        if isinstance(accessor.get("bufferView"), int):
            accessor["bufferView"] = mapping[accessor["bufferView"]]
        sparse = accessor.get("sparse")
        if isinstance(sparse, dict):
            for key in ("indices", "values"):
                info = sparse.get(key)
                if isinstance(info, dict) and isinstance(info.get("bufferView"), int):
                    info["bufferView"] = mapping[info["bufferView"]]
    for image in document.get("images", []):
        if isinstance(image, dict) and isinstance(image.get("bufferView"), int):
            image["bufferView"] = mapping[image["bufferView"]]

    def walk(value: Any) -> None:
        if isinstance(value, dict):
            for key, child in list(value.items()):
                if key == "bufferView" and isinstance(child, int) and child in mapping:
                    value[key] = mapping[child]
                walk(value[key])
        elif isinstance(value, list):
            for child in value:
                walk(child)

    walk(document.get("extensions", {}))


def _resize_image(raw: bytes, maximum: int) -> tuple[bytes, str | None]:
    try:
        from PIL import Image
    except ModuleNotFoundError as error:
        raise RuntimeError(
            "Pillow is required when the GLB contains embedded images; "
            "install it in the asset-tool environment (for example: python3 -m pip install Pillow)."
        ) from error
    with Image.open(io.BytesIO(raw)) as source:
        source.load()
        width, height = source.size
        if max(width, height) <= maximum:
            # Keep original encoded bytes and MIME type when no resize is
            # needed; this avoids needless quality loss and keeps checksums
            # stable across repeated preparation runs.
            return raw, Image.MIME.get(source.format)
        ratio = maximum / max(width, height)
        size = (max(1, round(width * ratio)), max(1, round(height * ratio)))
        converted = source.resize(size, Image.Resampling.LANCZOS)
        output = io.BytesIO()
        # PNG is broadly supported by ArkGraphics3D and preserves alpha.  For
        # palette/CMYK images Pillow needs an explicit conversion first.
        if converted.mode not in {"1", "L", "LA", "RGB", "RGBA", "I", "I;16"}:
            converted = converted.convert("RGBA")
        converted.save(output, format="PNG", optimize=True, compress_level=9)
        return output.getvalue(), "image/png"


def _prepare_data_uri_images(document: dict[str, Any], maximum: int) -> None:
    """Resize images embedded as ``data:`` URIs as well as BIN views.

    GLB exporters normally use ``bufferView`` images, but the glTF 2.0
    specification also permits a data URI. Keeping this small path here makes
    the "embedded texture <= 1024" guarantee true for both encodings without
    introducing a second asset format.
    """

    for image in document.get("images", []):
        if not isinstance(image, dict):
            continue
        uri = image.get("uri")
        if not isinstance(uri, str) or not uri.startswith("data:"):
            continue
        try:
            header, encoded = uri.split(",", 1)
        except ValueError as error:
            raise ValueError("image data URI is missing its payload") from error
        metadata = header[5:].split(";")
        mime_type = metadata[0] or str(image.get("mimeType", "application/octet-stream"))
        try:
            if "base64" in metadata[1:]:
                raw = base64.b64decode(encoded, validate=True)
            else:
                raw = urllib.parse.unquote_to_bytes(encoded)
        except (ValueError, binascii.Error) as error:
            raise ValueError("image data URI has invalid base64/escaped bytes") from error
        prepared, prepared_mime = _resize_image(raw, maximum)
        if prepared != raw:
            output_mime = prepared_mime or "image/png"
            image["uri"] = (
                f"data:{output_mime};base64,{base64.b64encode(prepared).decode('ascii')}"
            )
            image["mimeType"] = output_mime
        elif not image.get("mimeType"):
            image["mimeType"] = mime_type


def repack_without_animation(
    document: dict[str, Any], binary: bytes, maximum_texture_size: int
) -> tuple[dict[str, Any], bytes]:
    """Drop unreachable animation payload and compact all retained views."""

    old_accessors = document.get("accessors", [])
    old_views = document.get("bufferViews", [])
    if not isinstance(old_accessors, list) or not isinstance(old_views, list):
        _fail("GLB accessors/bufferViews must be arrays")
    accessor_ids = sorted(_collect_accessor_references(document))
    accessor_mapping = {old: new for new, old in enumerate(accessor_ids)}
    retained_accessors = [old_accessors[index] for index in accessor_ids]
    view_ids = sorted(_collect_buffer_view_references(document, set(accessor_ids)))
    view_mapping = {old: new for new, old in enumerate(view_ids)}
    _prepare_data_uri_images(document, maximum_texture_size)

    image_by_view = {
        image.get("bufferView"): image
        for image in document.get("images", [])
        if isinstance(image, dict) and isinstance(image.get("bufferView"), int)
    }
    packed = bytearray()
    new_views: list[dict[str, Any]] = []
    for old_index in view_ids:
        old_view = old_views[old_index]
        if not isinstance(old_view, dict):
            _fail(f"bufferView {old_index} is not an object")
        start = int(old_view.get("byteOffset", 0))
        length = int(old_view.get("byteLength", 0))
        if start < 0 or length < 0 or start + length > len(binary):
            _fail(f"bufferView {old_index} points outside the GLB BIN chunk")
        raw = binary[start:start + length]
        image = image_by_view.get(old_index)
        if image is not None:
            raw, mime_type = _resize_image(raw, maximum_texture_size)
            if mime_type:
                image["mimeType"] = mime_type
        offset = align4(len(packed))
        packed.extend(b"\0" * (offset - len(packed)))
        packed.extend(raw)
        new_view = {
            key: value
            for key, value in old_view.items()
            if key not in {"buffer", "byteOffset", "byteLength"}
        }
        new_view["buffer"] = 0
        new_view["byteOffset"] = offset
        new_view["byteLength"] = len(raw)
        new_views.append(new_view)

    _replace_accessor_indices(document, accessor_mapping)
    # Install the retained accessor list before remapping buffer views.  If we
    # walked the old list here, animation-only accessors would still reference
    # views that are intentionally absent from ``view_mapping``.
    document["accessors"] = retained_accessors
    _replace_buffer_view_indices(document, view_mapping)
    document["bufferViews"] = new_views
    document["buffers"] = [{"byteLength": len(packed)}]
    document.setdefault("asset", {})["generator"] = "Anomicon archive GLB preparer"
    return document, bytes(packed)


def _position_bounds(document: dict[str, Any]) -> tuple[Vector, Vector]:
    minimums: list[Vector] = []
    maximums: list[Vector] = []
    accessors = document.get("accessors", [])
    for mesh in document.get("meshes", []):
        if not isinstance(mesh, dict):
            continue
        for primitive in mesh.get("primitives", []):
            if not isinstance(primitive, dict):
                continue
            position_index = primitive.get("attributes", {}).get("POSITION")
            if not isinstance(position_index, int) or not 0 <= position_index < len(accessors):
                continue
            accessor = accessors[position_index]
            if not isinstance(accessor, dict) or "min" not in accessor or "max" not in accessor:
                continue
            minimum = accessor["min"]
            maximum = accessor["max"]
            if isinstance(minimum, list) and isinstance(maximum, list) and len(minimum) >= 3 and len(maximum) >= 3:
                minimums.append([float(value) for value in minimum[:3]])
                maximums.append([float(value) for value in maximum[:3]])
    if not minimums:
        _fail("cannot add archive roots without POSITION min/max bounds")
    minimum = [min(row[axis] for row in minimums) for axis in range(3)]
    maximum = [max(row[axis] for row in maximums) for axis in range(3)]
    return minimum, maximum


def add_archive_roots(
    document: dict[str, Any],
    *,
    archive_scale: float = 1.0,
    archive_offset: Sequence[Number] | None = None,
    combine_scenes: bool = False,
) -> None:
    """Wrap the active scene in neutral offset and interaction nodes.

    ``archive_scale`` is deliberately applied by a wrapper *above* the offset
    node.  Scaling the wrapper scales both the model and the centering
    translation, which keeps the pivot stable for assets exported in unusual
    units.  The authored root transform is never changed.  When supplied,
    ``archive_offset`` is the final translation of ``AnomiconModelOffset`` and
    replaces the automatically computed ``-POSITION-bounds-center`` value.
    """

    if not math.isfinite(float(archive_scale)) or float(archive_scale) <= 0.0:
        _fail("archive scale must be a finite positive number")
    if archive_offset is not None:
        if len(archive_offset) != 3 or not all(math.isfinite(float(value)) for value in archive_offset):
            _fail("archive offset must contain three finite numbers")

    nodes = document.setdefault("nodes", [])
    if any(
        isinstance(node, dict)
        and node.get("name") in {ARCHIVE_OFFSET_NAME, ARCHIVE_PIVOT_NAME}
        for node in nodes
    ):
        _fail("asset already contains Anomicon archive transform nodes")
    scenes = document.get("scenes", [])
    if not scenes:
        _fail("cannot add archive roots to a GLB without a scene")
    scene_index = int(document.get("scene", 0))
    if not 0 <= scene_index < len(scenes) or not isinstance(scenes[scene_index], dict):
        _fail("active scene index is invalid")
    scene = scenes[scene_index]
    if combine_scenes:
        roots = []
        for scene_entry in scenes:
            if isinstance(scene_entry, dict):
                roots.extend(scene_entry.get("nodes", []))
    else:
        roots = list(scene.get("nodes", []))
    if not roots:
        _fail("active scene has no root nodes")
    minimum, maximum = _position_bounds(document)
    center = [(minimum[axis] + maximum[axis]) * 0.5 for axis in range(3)]
    translation = (
        [float(value) for value in archive_offset]
        if archive_offset is not None
        else [-center[0], -center[1], -center[2]]
    )
    offset_index = len(nodes)
    nodes.append({
        "name": ARCHIVE_OFFSET_NAME,
        "children": roots,
        "translation": translation,
    })
    child_index = offset_index
    if abs(float(archive_scale) - 1.0) > 1e-12:
        scale_index = len(nodes)
        nodes.append({
            "name": "AnomiconModelScale",
            "children": [offset_index],
            "scale": [float(archive_scale)] * 3,
        })
        child_index = scale_index
    pivot_index = len(nodes)
    nodes.append({
        "name": ARCHIVE_PIVOT_NAME,
        "children": [child_index],
    })
    scene["nodes"] = [pivot_index]
    if combine_scenes:
        # A merged GLB commonly contains one scene per input. Leaving the
        # former scenes in place would make their roots overlap with the new
        # wrapper and can trigger SCENE_NON_ROOT_NODE validation errors. The
        # explicit combine mode therefore canonicalizes the output to one
        # active scene containing every input root.
        document["scenes"] = [scene]
        document["scene"] = 0


def add_scene_placement(
    document: dict[str, Any], placement_offset: Sequence[Number]
) -> None:
    """Place one prepared asset before it is merged into a composite scene.

    The wrapper leaves authored skeleton and mesh nodes untouched.  It is most
    useful with ``--no-archive-roots``: prepare each component, merge those
    intermediate GLBs, then run this tool once more to add the single archive
    pivot shared by the finished composition.
    """

    if len(placement_offset) != 3 or not all(
        math.isfinite(float(value)) for value in placement_offset
    ):
        _fail("placement offset must contain three finite numbers")
    scenes = document.get("scenes", [])
    scene_index = int(document.get("scene", 0))
    if not 0 <= scene_index < len(scenes) or not isinstance(scenes[scene_index], dict):
        _fail("active scene index is invalid")
    scene = scenes[scene_index]
    roots = list(scene.get("nodes", []))
    if not roots:
        _fail("active scene has no root nodes")
    nodes = document.setdefault("nodes", [])
    if any(
        isinstance(node, dict) and node.get("name") == ASSET_PLACEMENT_NAME
        for node in nodes
    ):
        _fail(f"asset already contains a node named {ASSET_PLACEMENT_NAME!r}")
    placement_index = len(nodes)
    nodes.append({
        "name": ASSET_PLACEMENT_NAME,
        "children": roots,
        "translation": [float(value) for value in placement_offset],
    })
    scene["nodes"] = [placement_index]


def prepare(
    source: Path,
    destination: Path,
    *,
    animation_name: str | None = None,
    seconds: float | None = None,
    ratio: float = 0.5,
    maximum_texture_size: int = 1024,
    archive_roots: bool = True,
    archive_scale: float = 1.0,
    archive_offset: Sequence[Number] | None = None,
    placement_offset: Sequence[Number] | None = None,
    combine_scenes: bool = False,
) -> tuple[str | None, float, float]:
    if maximum_texture_size < 64:
        _fail("--max-texture must be at least 64")
    if not 0.0 <= ratio <= 1.0:
        _fail("--ratio must be between 0 and 1")
    if seconds is not None and not math.isfinite(float(seconds)):
        _fail("--seconds must be a finite number")
    document, binary = read_glb(source)
    validate_supported_extensions(document)
    validate_self_contained(document)
    baked_name, sample_time, duration = bake_animation(
        document,
        binary,
        animation_name,
        seconds,
        ratio,
    )
    document, binary = repack_without_animation(document, binary, maximum_texture_size)
    if placement_offset is not None:
        add_scene_placement(document, placement_offset)
    if archive_roots:
        add_archive_roots(
            document,
            archive_scale=archive_scale,
            archive_offset=archive_offset,
            combine_scenes=combine_scenes,
        )
    write_glb(destination, document, binary)
    return baked_name, sample_time, duration


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Bake one animation pose and prepare an ArkGraphics3D-compatible static GLB.",
        epilog=(
            "Example: python3 tools/archive3d/prepare_archive_glb.py source.glb output.glb "
            "--animation-name 049_Idle2 --ratio 0.5"
        ),
    )
    parser.add_argument("source", type=Path, help="source GLB 2.0 (never modified)")
    parser.add_argument("destination", type=Path, help="prepared output GLB")
    parser.add_argument(
        "--animation-name",
        help="explicit clip to sample; required when the source contains animations",
    )
    sample_group = parser.add_mutually_exclusive_group()
    sample_group.add_argument(
        "--seconds",
        "--time",
        dest="seconds",
        type=float,
        help="sample time in seconds (clamped to the selected clip)",
    )
    sample_group.add_argument(
        "--ratio",
        "--sample-ratio",
        type=float,
        default=0.5,
        help="sample position in the clip, 0..1 (default: 0.5)",
    )
    parser.add_argument(
        "--max-texture",
        "--max-texture-size",
        type=int,
        default=1024,
        help="maximum embedded texture edge in pixels (default: 1024)",
    )
    parser.add_argument(
        "--no-archive-roots",
        action="store_true",
        help="do not add AnomiconModelOffset/AnomiconInteractivePivot",
    )
    parser.add_argument(
        "--archive-scale",
        type=float,
        default=1.0,
        help=(
            "optional unit correction applied on a wrapper above the archive "
            "offset; authored node scales are preserved (default: 1)"
        ),
    )
    parser.add_argument(
        "--archive-offset",
        type=float,
        nargs=3,
        metavar=("X", "Y", "Z"),
        help=(
            "explicit AnomiconModelOffset translation; overrides automatic "
            "POSITION-bounds centering"
        ),
    )
    parser.add_argument(
        "--placement-offset",
        type=float,
        nargs=3,
        metavar=("X", "Y", "Z"),
        help=(
            "optional scene-root placement for a component that will be merged "
            "into a composite GLB; normally used with --no-archive-roots"
        ),
    )
    parser.add_argument(
        "--combine-scenes",
        action="store_true",
        help=(
            "when adding archive roots, put roots from every glTF scene into "
            "the active interactive pivot (for merged composite assets)"
        ),
    )
    args = parser.parse_args(argv)
    try:
        name, sample_time, duration = prepare(
            args.source,
            args.destination,
            animation_name=args.animation_name,
            seconds=args.seconds,
            ratio=args.ratio,
            maximum_texture_size=args.max_texture,
            archive_roots=not args.no_archive_roots,
            archive_scale=args.archive_scale,
            archive_offset=args.archive_offset,
            placement_offset=args.placement_offset,
            combine_scenes=args.combine_scenes,
        )
    except (OSError, ValueError, RuntimeError) as error:
        print(f"prepare_archive_glb: error: {error}", file=sys.stderr)
        return 2
    if name is None:
        print("prepared static GLB (no animation clip found)")
    else:
        print(
            f"prepared static GLB: clip={name!r}, sample={sample_time:.4f}s, "
            f"duration={duration:.4f}s"
        )
    output_bytes = args.destination.read_bytes()
    print(
        f"output: {args.destination} ({len(output_bytes)} bytes, "
        f"sha256={hashlib.sha256(output_bytes).hexdigest()})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
