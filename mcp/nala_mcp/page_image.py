from dataclasses import dataclass
from functools import lru_cache
from io import BytesIO
import math
from pathlib import Path
import subprocess

from PIL import Image, ImageDraw, ImageFont

from .assets import AssetError, asset_bytes


MAX_EDGE = 1900
MAX_SOURCE_PIXELS = 24_000_000
MAX_STROKE_POINTS = 500_000
PAPER_COLOR = (219, 227, 220)
PAPER_PATTERNS = {'blank', 'ruled', 'grid', 'dots', 'cornell', 'weekly'}
_FONT_FILE = Path(__file__).resolve().parents[2] / 'assets' / 'fonts' / 'NalaSans.ttf'


@dataclass(frozen=True)
class PageImage:
    png: bytes
    warnings: tuple[str, ...]


def _number(value: object) -> float:
    if not isinstance(value, (float, int)) or isinstance(value, bool):
        raise ValueError('Coordenada de página inválida.')
    number = float(value)
    if not math.isfinite(number):
        raise ValueError('Coordenada de página inválida.')
    return number


def _paper(image: Image.Image, pattern: str, width: float, height: float, scale: float) -> None:
    draw = ImageDraw.Draw(image)
    step = 20
    guide_width = max(1, round(0.6 * scale))

    def line(x1, y1, x2, y2):
        draw.line(tuple(value * scale for value in (x1, y1, x2, y2)), PAPER_COLOR, guide_width)

    # If a large format makes guides subpixel, omit dense rules rather than fill
    # the preview with moiré or spend time drawing unresolvable detail.
    guides_visible = step * scale >= 3
    if pattern in {'grid', 'ruled'} and guides_visible:
        for y in range(step, math.ceil(height), step):
            line(0, y, width, y)
    if pattern == 'grid' and guides_visible:
        for x in range(step, math.ceil(width), step):
            line(x, 0, x, height)
    if pattern == 'dots' and guides_visible:
        radius = max(0.5, 0.8 * scale)
        for y in range(step, math.ceil(height), step):
            for x in range(step, math.ceil(width), step):
                px, py = x * scale, y * scale
                draw.ellipse((px - radius, py - radius, px + radius, py + radius), PAPER_COLOR)
    if pattern == 'cornell':
        margin, cue = width * 0.06, width * 0.28
        header, summary = height * 0.10, height * 0.80
        line(margin, header, width - margin, header)
        line(margin, summary, width - margin, summary)
        line(cue, header, cue, summary)
        if guides_visible:
            for row in range(1, math.ceil((summary - header) / step)):
                y = header + step * row
                line(cue, y, width - margin, y)
            for row in range(1, math.ceil((height - margin - summary) / step)):
                y = summary + step * row
                line(margin, y, width - margin, y)
    if pattern == 'weekly':
        margin, day = width * 0.06, width * 0.22
        header, bottom = height * 0.10, height - margin
        for x in (margin, day, width - margin):
            line(x, header, x, bottom)
        for row in range(8):
            y = header + row * (bottom - header) / 7
            line(margin, y, width - margin, y)


def _decode_image(contents: bytes, size: tuple[int, int]) -> Image.Image:
    with Image.open(BytesIO(contents)) as source:
        if source.width * source.height > MAX_SOURCE_PIXELS:
            raise ValueError('La imagen es demasiado grande.')
        return source.convert('RGBA').resize(size, Image.Resampling.LANCZOS)


def _pdf_page(contents: bytes, page_number: object, edge: int) -> bytes:
    if type(page_number) is not int or not 1 <= page_number <= 2_147_483_647:
        raise ValueError('Número de página PDF inválido.')
    command = [
        'pdftoppm', '-q', '-f', str(page_number), '-l', str(page_number),
        '-scale-to', str(edge), '-singlefile', '-png', '-',
    ]
    return subprocess.run(
        command, input=contents, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        check=True, timeout=15,
    ).stdout


def _background(image: Image.Image, page: dict, assets: Path, scale: float, warnings: list[str]) -> None:
    background = page.get('background', {})
    kind = background.get('kind')
    if kind == 'paper' and background.get('pattern') in PAPER_PATTERNS:
        _paper(image, background['pattern'], _number(page['width']), _number(page['height']), scale)
        return
    if kind not in {'image', 'pdf'}:
        warnings.append('El tipo de fondo no se pudo representar.')
        return
    try:
        contents = asset_bytes(assets, background.get('assetId'))
        if kind == 'pdf':
            contents = _pdf_page(contents, background.get('pageNumber'), MAX_EDGE)
        overlay = _decode_image(contents, image.size)
        image.paste(overlay, (0, 0), overlay)
    except FileNotFoundError:
        warnings.append('El fondo PDF requiere pdftoppm (Poppler).')
    except (AssetError, OSError, ValueError, Image.DecompressionBombError, subprocess.SubprocessError):
        name = 'PDF' if kind == 'pdf' else 'de imagen'
        warnings.append(f'El fondo {name} no se pudo representar.')


def _color(argb: int) -> tuple[int, int, int, int]:
    return ((argb >> 16) & 255, (argb >> 8) & 255, argb & 255, (argb >> 24) & 255)


@lru_cache(maxsize=32)
def _font(size: int):
    try:
        return ImageFont.truetype(str(_FONT_FILE), size)
    except OSError:
        return ImageFont.load_default(size=size)


def _text_lines(text: str, font, width: int):
    for paragraph in text.split('\n'):
        line = ''
        for word in paragraph.split():
            candidate = f'{line} {word}' if line else word
            if line and font.getlength(candidate) > width:
                yield line
                line = word
            else:
                line = candidate
        yield line


def _text_object(obj: dict, size: tuple[int, int], scale: float, warnings: list[str]) -> Image.Image:
    layer = Image.new('RGBA', size)
    font_size = round(_number(obj.get('fontSize', 16)) * scale)
    font = _font(min(MAX_EDGE, max(1, font_size)))
    foreground = _color(obj.get('argb', 0xff202020))
    brush = ImageDraw.Draw(layer)
    text = obj['text']
    if len(text) > 20_000:
        warnings.append('Un objeto de texto se recortó en la imagen.')
    line_height = max(1, round(1.2 * font.size))
    for index, line in enumerate(_text_lines(text[:20_000], font, size[0])):
        y = index * line_height
        if y >= size[1]:
            break
        brush.text((0, y), line, foreground, font=font, anchor='lt')
        if obj.get('link'):
            underline_y = min(size[1] - 1, y + font.size)
            brush.line((0, underline_y, min(size[0], font.getlength(line)), underline_y), foreground)
    return layer


def _page_object(image: Image.Image, obj: dict, assets: Path, scale: float, warnings: list[str]) -> None:
    left, top = (_number(obj[key]) * scale for key in ('x', 'y'))
    width, height = (max(1, round(_number(obj[key]) * scale)) for key in ('width', 'height'))
    if max(width, height) > MAX_EDGE * 2 or width * height > MAX_SOURCE_PIXELS // 3:
        raise ValueError('Objeto demasiado grande.')
    rotation = _number(obj.get('rotation', 0))
    extent = math.hypot(width, height) / 2
    center_x, center_y = left + width / 2, top + height / 2
    if (center_x + extent < 0 or center_x - extent > image.width or
            center_y + extent < 0 or center_y - extent > image.height):
        return
    size = (width, height)
    if obj['kind'] == 'text':
        layer = _text_object(obj, size, scale, warnings)
    elif obj['kind'] in {'image', 'latex'}:
        layer = _decode_image(asset_bytes(assets, obj.get('assetId')), size)
    else:
        raise ValueError('Objeto no compatible.')
    if rotation:
        angle = -math.degrees(math.remainder(rotation, math.tau))
        layer = layer.rotate(angle, resample=Image.Resampling.BICUBIC, expand=True)
    opacity = _number(obj.get('opacity', 1))
    alpha = layer.getchannel('A')
    if opacity < 1:
        alpha = alpha.point([round(level * max(0, opacity)) for level in range(256)])
    image.paste(layer, (round(center_x - layer.width / 2), round(center_y - layer.height / 2)), alpha)


def _stroke_radius(width: float, curve: str, sensitivity: float, pressure: float) -> float:
    pressure = max(0, min(1, pressure))
    if curve == 'uniform':
        return width / 2
    if curve == 'expressive':
        return width * (1 - sensitivity + sensitivity * (0.15 + 1.35 * pressure ** 0.65)) / 2
    return width * (0.35 + 0.65 * pressure) / 2


def _stroke_shape(draw: ImageDraw.ImageDraw, points: list[tuple[float, float, float]], fill, origin) -> None:
    previous = None
    offset_x, offset_y = origin
    for x, y, radius in points:
        x, y = x - offset_x, y - offset_y
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill)
        if previous is not None:
            px, py, pr = previous
            dx, dy = x - px, y - py
            length = math.hypot(dx, dy)
            if length:
                nx, ny = -dy / length, dx / length
                draw.polygon((
                    (px - nx * pr, py - ny * pr), (x - nx * radius, y - ny * radius),
                    (x + nx * radius, y + ny * radius), (px + nx * pr, py + ny * pr),
                ), fill)
        previous = x, y, radius


def _stroke(image: Image.Image, stroke: dict, scale: float) -> None:
    width = _number(stroke['width']) * scale
    curve = stroke.get('pressureCurve', 'legacy')
    sensitivity = _number(stroke.get('sensitivity', 1))
    red, green, blue, alpha = _color(stroke['argb'])
    if stroke.get('tool') == 'highlighter':
        alpha = 0x55
    if alpha == 0:
        return
    points = [
        (
            _number(point['x']) * scale,
            _number(point['y']) * scale,
            _stroke_radius(width, curve, sensitivity, _number(point['pressure'])),
        )
        for point in stroke['points']
    ]
    if any(not math.isfinite(value) or abs(value) > 1_000_000 for point in points for value in point):
        raise ValueError('Trazo fuera de escala.')
    if alpha == 255:
        _stroke_shape(ImageDraw.Draw(image), points, (red, green, blue), (0, 0))
        return
    x0 = max(0, math.floor(min(x - radius for x, _, radius in points)))
    y0 = max(0, math.floor(min(y - radius for _, y, radius in points)))
    x1 = min(image.width, 1 + math.ceil(max(x + radius for x, _, radius in points)))
    y1 = min(image.height, 1 + math.ceil(max(y + radius for _, y, radius in points)))
    if x0 >= x1 or y0 >= y1:
        return
    mask = Image.new('L', (x1 - x0, y1 - y0))
    _stroke_shape(ImageDraw.Draw(mask), points, alpha, (x0, y0))
    image.paste((red, green, blue), (x0, y0, x1, y1), mask)


def render_page(page: dict, assets: Path) -> PageImage:
    width, height = (_number(page[axis]) for axis in ('width', 'height'))
    if min(width, height) <= 0:
        raise ValueError('La página no tiene dimensiones válidas.')
    edge = max(width, height)
    output = tuple(max(1, round(value / edge * MAX_EDGE)) for value in (width, height))
    intermediate = tuple(round(value * 1.5) for value in output)
    scale = MAX_EDGE * 1.5 / edge
    image = Image.new('RGB', intermediate, 'white')
    warnings: list[str] = []
    _background(image, page, assets, scale, warnings)
    for obj in page.get('objects', []):
        try:
            _page_object(image, obj, assets, scale, warnings)
        except (OSError, ValueError, TypeError, OverflowError, KeyError, Image.DecompressionBombError):
            warnings.append('No se pudieron representar algunos objetos de la página.')
    remaining = MAX_STROKE_POINTS
    for stroke in page.get('strokes', []):
        remaining -= len(stroke['points'])
        if remaining < 0:
            warnings.append('La imagen omite trazos que exceden el límite de renderizado.')
            break
        try:
            _stroke(image, stroke, scale)
        except (ValueError, TypeError, OverflowError, KeyError):
            warnings.append('No se pudieron representar algunos trazos de la página.')
    encoded = BytesIO()
    image.resize(output, Image.Resampling.LANCZOS).save(encoded, 'PNG')
    return PageImage(encoded.getvalue(), tuple(dict.fromkeys(warnings)))
