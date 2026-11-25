import hashlib
import shutil
import tempfile
import unittest
from io import BytesIO
from pathlib import Path

from PIL import Image

from nala_mcp.page_image import render_page


def page(**changes):
    return {
        'width': 200,
        'height': 100,
        'background': {'kind': 'paper', 'pattern': 'blank'},
        **changes,
    }


class PageImageTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.assets = Path(temporary.name)

    def test_handwriting_has_pressure_width_and_a_bounded_png(self):
        result = render_page(page(strokes=[{
            'tool': 'pen', 'argb': 0xff000000, 'width': 10,
            'pressureCurve': 'expressive',
            'points': [
                {'x': 20, 'y': 50, 'pressure': 0},
                {'x': 175, 'y': 50, 'pressure': 1},
            ],
        }]), self.assets)
        with Image.open(BytesIO(result.png)) as image:
            self.assertEqual(image.format, 'PNG')
            self.assertLessEqual(max(image.size), 1900)
            self.assertAlmostEqual(image.width / image.height, 2, places=2)
            scale = image.width / 200

            def sample(x, y):
                return image.getpixel((round(x * scale), round(y * scale)))[0]

            self.assertLess(sample(80, 50), 64)
            self.assertGreater(sample(22, 45), 224)
            self.assertLess(sample(171, 45), 64)
        self.assertEqual(result.warnings, ())

    def test_highlighter_applies_opacity_once_per_stroke(self):
        result = render_page(page(strokes=[{
            'tool': 'highlighter', 'argb': 0xffff0000, 'width': 12,
            'pressureCurve': 'uniform',
            'points': [
                {'x': x, 'y': y, 'pressure': 1}
                for x, y in [(30, 15), (170, 85), (30, 85), (170, 15)]
            ],
        }]), self.assets)
        with Image.open(BytesIO(result.png)) as image:
            self.assertEqual(image.getpixel((image.width // 2, image.height // 2)), (255, 170, 170))

    def test_read_local_image_background_with_content_address(self):
        data = BytesIO()
        Image.new('RGB', (20, 10), (35, 120, 55)).save(data, 'PNG')
        contents = data.getvalue()
        asset_id = hashlib.sha256(contents).hexdigest()
        (self.assets / asset_id).write_bytes(contents)
        result = render_page(page(background={'kind': 'image', 'assetId': asset_id}), self.assets)
        with Image.open(BytesIO(result.png)) as image:
            self.assertEqual(image.getpixel((image.width // 2, image.height // 2)), (35, 120, 55))
        self.assertEqual(result.warnings, ())

    def test_bad_asset_does_not_hide_other_page_content(self):
        external = self.assets.parent / f'{self.assets.name}-outside'
        data = BytesIO()
        Image.new('RGB', (20, 10), (35, 120, 55)).save(data, 'PNG')
        contents = data.getvalue()
        external.write_bytes(contents)
        self.addCleanup(external.unlink)
        asset_id = hashlib.sha256(contents).hexdigest()
        (self.assets / asset_id).symlink_to(external)
        result = render_page(page(background={'kind': 'image', 'assetId': asset_id}), self.assets)
        with Image.open(BytesIO(result.png)) as image:
            self.assertEqual(image.getpixel((image.width // 2, image.height // 2)), (255, 255, 255))
        self.assertTrue(result.warnings)
        self.assertNotIn(str(external), '\n'.join(result.warnings))

    @unittest.skipUnless(shutil.which('pdftoppm'), 'Poppler no está instalado')
    def test_pdf_uses_the_selected_one_based_page(self):
        first = Image.new('RGB', (200, 100), (255, 35, 35))
        second = Image.new('RGB', (200, 100), (35, 35, 255))
        data = BytesIO()
        first.save(data, 'PDF', save_all=True, append_images=[second])
        contents = data.getvalue()
        asset_id = hashlib.sha256(contents).hexdigest()
        (self.assets / asset_id).write_bytes(contents)

        background = {'kind': 'pdf', 'assetId': asset_id, 'pageNumber': 2}
        result = render_page(page(background=background), self.assets)
        with Image.open(BytesIO(result.png)) as image:
            red, _, blue = image.getpixel((image.width // 2, image.height // 2))
            self.assertLess(red, 50)
            self.assertGreater(blue, 240)
        self.assertEqual(result.warnings, ())

    def test_rendered_object_respects_opacity_and_keeps_typed_text(self):
        data = BytesIO()
        Image.new('RGB', (7, 7), (0, 0, 0)).save(data, 'PNG')
        contents = data.getvalue()
        asset_id = hashlib.sha256(contents).hexdigest()
        (self.assets / asset_id).write_bytes(contents)
        objects = [
            {'kind': 'image', 'x': 20, 'y': 20, 'width': 30, 'height': 30,
             'opacity': 0.5, 'assetId': asset_id},
            {'kind': 'text', 'x': 70, 'y': 20, 'width': 100, 'height': 50,
             'text': 'Álgebra', 'fontSize': 17},
        ]
        result = render_page(page(objects=objects), self.assets)
        with Image.open(BytesIO(result.png)) as image:
            scale = image.width / 200
            self.assertEqual(image.getpixel((round(35 * scale), round(35 * scale))), (127, 127, 127))
            text = image.crop(tuple(round(v * scale) for v in (70, 20, 170, 70)))
            self.assertLess(text.getextrema()[0][0], 64)
        self.assertEqual(result.warnings, ())
