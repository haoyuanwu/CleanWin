"""Export the approved CleanWin logo to Flutter PNG and Windows ICO assets.

Run from any directory: python tool/make_app_icon.py
Requires Pillow. The original generated artwork is preserved as the source.
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/icon/cleanwin_logo_v2.png'
PNG = ROOT / 'assets/icon/cleanwin_icon.png'
ICO = ROOT / 'windows/runner/resources/app_icon.ico'
SIZES = (16, 24, 32, 48, 64, 128, 256)


def make_icon():
    with Image.open(SOURCE) as source:
        return source.convert('RGBA').resize((1024, 1024), Image.Resampling.LANCZOS)


if __name__ == '__main__':
    image = make_icon()
    PNG.parent.mkdir(parents=True, exist_ok=True)
    ICO.parent.mkdir(parents=True, exist_ok=True)
    image.save(PNG)
    image.save(ICO, format='ICO', sizes=[(size, size) for size in SIZES])
    print(f'Updated {PNG} and {ICO}')
