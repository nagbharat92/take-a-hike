"""Reproducible local adaptations of the licensed packs. Requires existing Pillow."""
from pathlib import Path
from PIL import Image
import shutil

ROOT = Path(__file__).resolve().parents[1]
VENDOR = ROOT / "assets/vendor"
OUT = ROOT / "assets/forest"
OUT.mkdir(parents=True, exist_ok=True)
forest = next((VENDOR / "forest").glob("Legacy*"))


def forest_palette(image):
    """Map source greens and bark separately, retaining each source shade."""
    image = image.convert("RGBA")
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = image.getpixel((x, y))
            if not a:
                continue
            value = (r * .24 + g * .62 + b * .14) / 255
            if g > r * 1.08:
                dark, light = (27, 57, 53), (125, 151, 100)
                t = min(1, max(0, (value - .055) / .40))
            else:
                dark, light = (38, 51, 46), (151, 131, 85)
                t = min(1, max(0, (value - .055) / .43))
            image.putpixel((x, y), (*[round(d + (l-d)*t) for d, l in zip(dark, light)], a))
    return image


# Five authored tree silhouettes, not the adjacent canopy/trunk construction layers.
source = Image.open(forest / "Trees/Green-Tree.png").convert("RGBA")
for i, rect in enumerate([(0, 0, 112, 368), (0, 384, 112, 704),
                          (0, 720, 96, 928), (0, 944, 80, 1088),
                          (0, 1104, 64, 1200)]):
    tree = source.crop(rect)
    tree = tree.crop(tree.getbbox())
    tree = forest_palette(tree)
    tree.resize((tree.width//2, tree.height//2), Image.Resampling.NEAREST).save(OUT / f"tree-{i}.png")

leaves = Image.open(forest / "Assets/Tree-Assets.png").convert("RGBA")
leaves = leaves.crop((208, 0, 336, 103))
leaves = leaves.crop(leaves.getbbox())
forest_palette(leaves).resize((64, 52), Image.Resampling.NEAREST).save(OUT / "canopy.png")

hiker_out = ROOT / "assets/hiker"
hiker_out.mkdir(parents=True, exist_ok=True)
source_dir = VENDOR / "rvros/Individual Sprites"
# Six actual authored walk poses supply the torso. Two contact holds make an
# eight-phase distance-driven cycle; legs are retargeted to the terrain in Godot.
for mode, count in [("walk", 6), ("idle", 4)]:
    for i in range(count):
        image = Image.open(source_dir / f"adventurer-{mode}-{i:02}.png").convert("RGBA")
        for y in range(image.height):
            for x in range(image.width):
                r, g, b, a = image.getpixel((x, y))
                if a and r > g * 1.25 and r > b * 1.2:
                    value = (r + g + b) / 765
                    image.putpixel((x, y), (round(43+value*95), round(65+value*115),
                                           round(62+value*95), a))
        image.save(hiker_out / f"{mode}-{i}.png")

licenses = ROOT / "assets/licenses"
licenses.mkdir(exist_ok=True)
for source, destination in [
    (ROOT / "downloads/forest-terms.pdf", licenses / "Anokolisa-Terms.pdf"),
    (VENDOR / "kenney/License.txt", licenses / "Kenney-CC0.txt"),
]:
    if source.exists():
        shutil.copy2(source, destination)
print("Prepared five imported forest silhouettes, canopy and licensed hiker poses.")
