import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from nala_mcp.page_text import page_text


def page(**values):
    return {
        "id": "p",
        "width": 595.28,
        "height": 842,
        "background": {"kind": "paper", "pattern": "grid"},
        "strokes": [],
        **values,
    }


def fixture_pdf(*page_contents: bytes) -> bytes:
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        f"<< /Type /Pages /Count {len(page_contents)} /Kids [".encode()
        + b" ".join(f"{4 + 2 * index} 0 R".encode() for index in range(len(page_contents)))
        + b"] >>",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]
    for index, contents in enumerate(page_contents):
        stream = b"BT /F1 12 Tf 10 40 Td (" + contents + b") Tj ET" if contents else b""
        objects.append(
            b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 80] "
            b"/Resources << /Font << /F1 3 0 R >> >> "
            + f"/Contents {5 + 2 * index} 0 R >>".encode()
        )
        objects.append(f"<< /Length {len(stream)} >>\nstream\n".encode() + stream + b"\nendstream")
    pdf = bytearray(b"%PDF-1.4\n")
    offsets = [0]
    for index, body in enumerate(objects, 1):
        offsets.append(len(pdf))
        pdf.extend(f"{index} 0 obj\n".encode() + body + b"\nendobj\n")
    xref = len(pdf)
    pdf.extend(f"xref\n0 {len(offsets)}\n0000000000 65535 f \n".encode())
    for offset in offsets[1:]:
        pdf.extend(f"{offset:010d} 00000 n \n".encode())
    pdf.extend(f"trailer\n<< /Size {len(offsets)} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode())
    return bytes(pdf)


class PageTextTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="nala-text-test-")
        self.addCleanup(directory.cleanup)
        self.assets = Path(directory.name)

    def store_pdf(self, contents: bytes) -> str:
        asset_id = hashlib.sha256(contents).hexdigest()
        (self.assets / asset_id).write_bytes(contents)
        return asset_id

    def pdf_page(self, asset_id, number=1):
        return page(background={"kind": "pdf", "assetId": asset_id, "pageNumber": number})

    def fake_pdftotext(self, script):
        backend = self.assets / "pdftotext"
        backend.write_text(f"#!{sys.executable}\n{script}\n", encoding="utf-8")
        backend.chmod(0o700)
        return patch.dict(os.environ, {"PATH": str(self.assets)})

    def test_text_and_formula_are_inserted_text_and_comments_keep_their_section(self):
        result = page_text(page(
            objects=[
                {"kind": "text", "text": "  Límite  "},
                {"kind": "latex", "text": r"\sqrt{x}"},
                {"kind": "image", "text": "ignorado"},
            ],
            comments=[{"text": "Repasar"}, {"text": "", "audioAssetId": "c" * 64}],
        ), self.assets)
        self.assertEqual(result.sections, (
            ("Texto insertado", "Límite\n\n" + r"\sqrt{x}"),
            ("Comentarios", "Repasar"),
        ))
        self.assertEqual(result.warnings, ())

    def test_recognition_hash_matches_dart_normalization_for_v1_data(self):
        # Digests produced with NotebookPage.fromJson/toJson and Dart jsonEncode.
        simple = page(
            recognizedText="Derivada",
            recognitionFingerprint="95ea0d630c8c2cd3be21014977d76286600cb21658455253dbe0b693b1abe00e",
            comments=[{"text": "Puede cambiar sin tocar el OCR"}],
        )
        self.assertIn(("Texto reconocido", "Derivada"), page_text(simple, self.assets).sections)
        self.assertEqual(page_text({**simple, "height": 841}, self.assets).warnings, ("recognition_stale",))
        complex_page = self.pdf_page("b" * 64, 2) | {
            "width": 1e20, "height": 1e21,
            "strokes": [{
                "id": "s", "tool": "pen", "argb": 0xff202020, "width": 2,
                "pressureCurve": "legacy", "sensitivity": 1,
                "points": [{"pressure": 1, "y": 1e-6, "x": 1e-7},
                           {"x": -0.0, "y": 2, "pressure": 0.125}],
            }],
            "objects": [
                {"id": "o", "kind": "text", "x": 0, "y": 1, "width": 2, "height": 3,
                 "rotation": -0.0, "text": "Raíz Ω 🧮\n\u0001\u2028", "argb": 0xff202020,
                 "fontSize": 16, "opacity": 1, "locked": False,
                 "link": {"pageId": "clase", "notebookId": "mate"}},
                {"id": "f", "kind": "latex", "x": 4, "y": 5, "width": 6, "height": 7,
                 "rotation": 0.125, "text": r"\sqrt{x}", "argb": 0xff111111, "fontSize": 20,
                 "opacity": 0.5, "locked": True, "assetId": "c" * 64},
            ],
            "recognizedText": "Reconocido",
            "recognitionFingerprint": "3895ca518738a720f53a0cd42f04597c55992081c0749496d8b60ae4fcbf2105",
        }
        self.assertIn(("Texto reconocido", "Reconocido"), page_text(complex_page, self.assets).sections)
        complex_page["objects"][1]["rotation"] = 0.2
        result = page_text(complex_page, self.assets)
        self.assertNotIn("Texto reconocido", dict(result.sections))
        self.assertIn("recognition_stale", result.warnings)

    @unittest.skipUnless(shutil.which("pdftotext"), "requiere Poppler")
    def test_extracts_only_requested_pdf_page_and_reports_blank_or_missing(self):
        asset_id = self.store_pdf(fixture_pdf(b"Primera hoja", b"Segunda hoja", b""))
        selected = self.pdf_page(asset_id, 2)
        self.assertEqual(page_text(selected, self.assets).sections, (
            ("Texto original del PDF", "Segunda hoja"),
        ))
        self.assertEqual(page_text(self.pdf_page(asset_id, 3), self.assets).warnings, ("pdf_textless",))
        (self.assets / asset_id).unlink()
        self.assertEqual(page_text(selected, self.assets).warnings, ("pdf_missing",))

    def test_asset_id_rejects_traversal_symlinks_and_invalid_contents(self):
        self.assertEqual(page_text(self.pdf_page("../file"), self.assets).warnings, ("pdf_invalid",))
        contents = fixture_pdf(b"Privado")
        separate = self.assets / "different-name.pdf"
        separate.write_bytes(contents)
        asset_id = hashlib.sha256(contents).hexdigest()
        (self.assets / asset_id).symlink_to(separate)
        result = page_text(self.pdf_page(asset_id), self.assets)
        self.assertEqual(result.sections, ())
        self.assertEqual(result.warnings, ("pdf_invalid",))

    def test_output_is_bounded_and_repeated_page_does_not_invoke_poppler_again(self):
        source = self.pdf_page(self.store_pdf(fixture_pdf(b"Synthetic")))
        count = self.assets / "calls"
        script = f"from pathlib import Path\nwith Path({str(count)!r}).open('a') as calls: calls.write('1')\nprint('a' * 4096)"
        with self.fake_pdftotext(script), patch("nala_mcp.page_text._PDF_MAX_TEXT", 32):
            result = page_text(source, self.assets)
            self.assertEqual(result.sections, (("Texto original del PDF", "a" * 32),))
            self.assertEqual(result.warnings, ("pdf_truncated",))
            self.assertEqual(page_text(source, self.assets), result)
        self.assertEqual(count.read_text(encoding="utf-8"), "1")

    def test_timeout_is_reported_when_subprocess_does_not_finish(self):
        source = self.pdf_page(self.store_pdf(fixture_pdf(b"Synthetic")))
        with self.fake_pdftotext("import time\ntime.sleep(20)"), patch("nala_mcp.page_text._PDF_TIMEOUT", 0.15):
            result = page_text(source, self.assets)
        self.assertEqual(result.sections, ())
        self.assertEqual(result.warnings, ("pdf_timeout",))

    @unittest.skipUnless(shutil.which("pdftotext") and shutil.which("mutool"), "requiere Poppler y MuPDF")
    def test_protected_pdf_is_distinct_from_a_textless_page(self):
        original = self.assets / "fixture.pdf"
        encrypted = self.assets / "encrypted.pdf"
        original.write_bytes(fixture_pdf(b"Cifrado"))
        subprocess.run(
            ["mutool", "clean", "-E", "aes-128", "-O", "owner", "-U", "synthetic", str(original), str(encrypted)],
            check=True, capture_output=True, timeout=5,
        )
        result = page_text(self.pdf_page(self.store_pdf(encrypted.read_bytes())), self.assets)
        self.assertEqual(result.sections, ())
        self.assertEqual(result.warnings, ("pdf_protected",))
