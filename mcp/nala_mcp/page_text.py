import hashlib
import json
import math
import os
import re
import selectors
import stat
import subprocess
import tempfile
import time
from dataclasses import dataclass
from decimal import Decimal
from functools import lru_cache
from pathlib import Path

from .assets import AssetError, AssetMissing, asset_bytes


_ASSET_ID = re.compile(r"[0-9a-f]{64}")
_PDF_TIMEOUT = 4.0
_PDF_MAX_TEXT = 128 * 1024
_PDF_MAX_DIAGNOSTICS = 16 * 1024


@dataclass(frozen=True)
class PageText:
    sections: tuple[tuple[str, str], ...]
    warnings: tuple[str, ...]


def page_text(page: dict, assets: Path) -> PageText:
    sections = []
    warnings = []
    inserted = _collect_text(page.get("objects"), {"text", "latex"})
    comments = _collect_text(page.get("comments"))
    if inserted:
        sections.append(("Texto insertado", inserted))
    if comments:
        sections.append(("Comentarios", comments))

    background = page.get("background")
    if isinstance(background, dict) and background.get("kind") == "pdf":
        original, warning = _pdf_text(assets, background.get("assetId"), background.get("pageNumber"))
        if original:
            sections.append(("Texto original del PDF", original))
        if warning:
            warnings.append(warning)

    recognized = page.get("recognizedText")
    if isinstance(recognized, str) and recognized.strip():
        fingerprint = page.get("recognitionFingerprint")
        if isinstance(fingerprint, str) and _ASSET_ID.fullmatch(fingerprint) and _fingerprint(page) == fingerprint:
            sections.append(("Texto reconocido", recognized.strip()))
        else:
            warnings.append("recognition_stale")
    return PageText(tuple(sections), tuple(warnings))


def _collect_text(items: object, kinds: set[str] | None = None) -> str:
    if not isinstance(items, list):
        return ""
    return "\n\n".join(
        value.strip()
        for item in items
        if isinstance(item, dict)
        and (kinds is None or isinstance(item.get("kind"), str) and item["kind"] in kinds)
        and isinstance(value := item.get("text"), str)
        and value.strip()
    )


def _pdf_text(assets: Path, asset_id: object, page_number: object) -> tuple[str, str | None]:
    if (
        not isinstance(asset_id, str) or not _ASSET_ID.fullmatch(asset_id)
        or type(page_number) is not int or not 1 <= page_number <= 2**31 - 1
    ):
        return "", "pdf_invalid"
    try:
        metadata = (assets / asset_id).lstat()
        if not stat.S_ISREG(metadata.st_mode):
            return "", "pdf_invalid"
        stamp = (metadata.st_dev, metadata.st_ino, metadata.st_size, metadata.st_mtime_ns, metadata.st_ctime_ns)
        return _read_pdf(assets, asset_id, page_number, stamp)
    except (AssetMissing, FileNotFoundError):
        return "", "pdf_missing"
    except (AssetError, OSError):
        return "", "pdf_invalid"


@lru_cache(maxsize=48)
def _read_pdf(assets: Path, asset_id: str, page_number: int, _stamp: tuple[int, ...]) -> tuple[str, str | None]:
    contents = asset_bytes(assets, asset_id)
    # Use a seekable, unnamed file for the securely opened bytes. Poppler never
    # reopens the catalog path or inherits unrelated descriptors.
    with tempfile.TemporaryFile() as original:
        original.write(contents)
        original.seek(0)
        number = str(page_number)
        try:
            process = subprocess.Popen(
                ["pdftotext", "-f", number, "-l", number, "-enc", "UTF-8", "-nopgbrk", "-", "-"],
                stdin=original, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                env={**os.environ, "LC_ALL": "C"},
            )
        except FileNotFoundError:
            return "", "pdf_unavailable"
        with process:
            try:
                stdout, stderr, truncated = _read_pdf_pipes(process)
            except (TimeoutError, subprocess.TimeoutExpired):
                process.kill()
                return "", "pdf_timeout"
            except OSError:
                process.kill()
                raise
    if process.returncode == 3 or b"password" in stderr.lower():
        return "", "pdf_protected"
    text = stdout.decode("utf-8", errors="replace").strip()
    if truncated == "stdout":
        return text, "pdf_truncated"
    if process.returncode or truncated:
        return "", "pdf_invalid"
    return (text, None) if text else ("", "pdf_textless")


def _read_pdf_pipes(process: subprocess.Popen) -> tuple[bytes, bytes, str | None]:
    deadline = time.monotonic() + _PDF_TIMEOUT
    buffers = {"stdout": bytearray(), "stderr": bytearray()}
    limits = {"stdout": _PDF_MAX_TEXT, "stderr": _PDF_MAX_DIAGNOSTICS}
    truncated = None
    with selectors.DefaultSelector() as selector:
        selector.register(process.stdout, selectors.EVENT_READ, "stdout")
        selector.register(process.stderr, selectors.EVENT_READ, "stderr")
        while selector.get_map() and truncated is None:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not (events := selector.select(remaining)):
                raise TimeoutError
            for key, _ in events:
                buffer = buffers[key.data]
                available = limits[key.data] - len(buffer)
                chunk = os.read(key.fd, min(32 * 1024, available + 1))
                if not chunk:
                    selector.unregister(key.fileobj)
                else:
                    buffer.extend(chunk[:available])
                    if len(chunk) > available:
                        truncated = key.data
                        process.kill()
                        break
    process.wait(timeout=max(0, deadline - time.monotonic()))
    return bytes(buffers["stdout"]), bytes(buffers["stderr"]), truncated


def _fingerprint(page: dict) -> str | None:
    # Match NotebookPage.fromJson and the toJson maps used by Nala's
    # pageRecognitionFingerprint. Older v1 optional defaults are omitted again.
    try:
        values = {
            "width": _double(page["width"]),
            "height": _double(page["height"]),
            "background": _canonical_background(page["background"]),
            "strokes": [_canonical_stroke(stroke) for stroke in _array(page["strokes"])],
            "objects": [_canonical_object(item) for item in _array(_default(page, "objects", []))],
        }
        return hashlib.sha256(_dart_json(values).encode("utf-8")).hexdigest()
    except (KeyError, TypeError, ValueError, OverflowError):
        return None


def _canonical_background(background: dict) -> dict:
    kind = background["kind"]
    if kind == "paper" and not {"assetId", "pageNumber"}.intersection(background):
        return {"kind": kind, "pattern": _choice(background["pattern"], "blank", "ruled", "grid", "dots", "cornell", "weekly")}
    if kind == "pdf" and "pattern" not in background:
        return {"kind": kind, "assetId": _asset(background["assetId"]), "pageNumber": _int(background["pageNumber"])}
    if kind == "image" and not {"pattern", "pageNumber"}.intersection(background):
        return {"kind": kind, "assetId": _asset(background["assetId"])}
    raise ValueError("invalid background")


def _canonical_stroke(stroke: dict) -> dict:
    result = {
        "id": _string(stroke["id"]),
        "tool": _choice(stroke["tool"], "pen", "highlighter"),
        "argb": _int(stroke["argb"]),
        "width": _double(stroke["width"]),
        "points": [
            {"x": _double(point["x"]), "y": _double(point["y"]), "pressure": _double(point["pressure"])}
            for point in _array(stroke["points"])
        ],
    }
    pressure = _choice(_default(stroke, "pressureCurve", "legacy"), "legacy", "expressive", "uniform")
    sensitivity = _double(_default(stroke, "sensitivity", 1))
    if pressure != "legacy":
        result["pressureCurve"] = pressure
    if sensitivity != 1:
        result["sensitivity"] = sensitivity
    if stroke.get("audioRecordingId") is not None:
        result["audioRecordingId"] = _string(stroke["audioRecordingId"])
    if stroke.get("audioOffsetMs") is not None:
        result["audioOffsetMs"] = _int(stroke["audioOffsetMs"])
    return result


def _canonical_object(item: dict) -> dict:
    kind = _choice(item["kind"], "text", "image", "latex")
    result = {
        "id": _string(item["id"]),
        "kind": kind,
        "x": _double(item["x"]),
        "y": _double(item["y"]),
        "width": _double(item["width"]),
        "height": _double(item["height"]),
    }
    rotation = _double(_default(item, "rotation", 0))
    if rotation != 0:
        result["rotation"] = rotation
    if kind != "image":
        result["text"] = _string(_default(item, "text", ""))
    argb = _int(_default(item, "argb", 0xff202020))
    font_size = _double(_default(item, "fontSize", 16))
    if argb != 0xff202020:
        result["argb"] = argb
    if font_size != 16:
        result["fontSize"] = font_size
    for key in ("assetId", "originalAssetId"):
        if item.get(key) is not None:
            result[key] = _asset(item[key])
    opacity = _double(_default(item, "opacity", 1))
    if opacity != 1:
        result["opacity"] = opacity
    locked = _default(item, "locked", False)
    if type(locked) is not bool:
        raise TypeError("invalid lock")
    if locked:
        result["locked"] = True
    if (link := item.get("link")) is not None:
        result["link"] = {"notebookId": _string(link["notebookId"]), "pageId": _string(link["pageId"])}
    return result


def _default(mapping: dict, key: str, default):
    value = mapping.get(key)
    return default if value is None else value


def _array(value: object) -> list:
    if not isinstance(value, list):
        raise TypeError("invalid list")
    return value


def _string(value: object) -> str:
    if not isinstance(value, str):
        raise TypeError("invalid string")
    return value


def _choice(value: object, *choices: str) -> str:
    value = _string(value)
    if value not in choices:
        raise ValueError("invalid enum")
    return value


def _asset(value: object) -> str:
    value = _string(value)
    if not _ASSET_ID.fullmatch(value):
        raise ValueError("invalid asset")
    return value


def _int(value: object) -> int:
    if type(value) is not int:
        raise TypeError("invalid integer")
    return value


def _double(value: object) -> float:
    if type(value) not in (float, int) or not math.isfinite(value):
        raise TypeError("invalid double")
    return float(value)


def _dart_json(value) -> str:
    if isinstance(value, dict):
        return "{" + ",".join(f"{_dart_json(key)}:{_dart_json(item)}" for key, item in value.items()) + "}"
    if isinstance(value, list):
        return "[" + ",".join(map(_dart_json, value)) + "]"
    if isinstance(value, float):
        text = repr(value)
        if "e" not in text:
            return text
        if 1e-6 <= abs(value) < 1e21:
            fixed = format(Decimal(text), "f")
            return fixed if "." in fixed else fixed + ".0"
        mantissa, exponent = text.split("e")
        return f"{mantissa}e{int(exponent):+d}"
    encoded = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    return re.sub(r"[\ud800-\udfff]", lambda match: f"\\u{ord(match[0]):04x}", encoded)
