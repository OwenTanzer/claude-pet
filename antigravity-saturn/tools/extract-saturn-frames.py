from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


FRAME_NAMES = ("saturn-idle.png", "saturn-working.png", "saturn-done.png")


def alpha_bounds(image: Image.Image) -> tuple[int, int, int, int]:
    alpha = image.getchannel("A").point(lambda value: 255 if value >= 8 else 0)
    bounds = alpha.getbbox()
    if bounds is None:
        raise ValueError("sprite slot is empty")
    return bounds


def extract(source: Path, output_dir: Path, preview_path: Path) -> dict:
    strip = Image.open(source).convert("RGBA")
    slot_edges = [round(index * strip.width / 3) for index in range(4)]
    slots = [strip.crop((slot_edges[index], 0, slot_edges[index + 1], strip.height)) for index in range(3)]
    crops = [slot.crop(alpha_bounds(slot)) for slot in slots]

    max_width = max(sprite.width for sprite in crops)
    max_height = max(sprite.height for sprite in crops)
    scale = min(332 / max_width, 332 / max_height)
    output_dir.mkdir(parents=True, exist_ok=True)

    manifest = {"source": str(source), "frameSize": [360, 360], "frames": {}}
    finished: list[Image.Image] = []
    for name, sprite in zip(FRAME_NAMES, crops):
        size = (max(1, round(sprite.width * scale)), max(1, round(sprite.height * scale)))
        resized = sprite.resize(size, Image.Resampling.LANCZOS)
        frame = Image.new("RGBA", (360, 360), (0, 0, 0, 0))
        x = (360 - size[0]) // 2
        y = (360 - size[1]) // 2
        frame.alpha_composite(resized, (x, y))
        destination = output_dir / name
        frame.save(destination, optimize=True)
        finished.append(frame)
        manifest["frames"][name] = {
            "path": str(destination),
            "contentBounds": list(alpha_bounds(frame)),
            "cornerAlpha": [frame.getpixel(point)[3] for point in ((0, 0), (359, 0), (0, 359), (359, 359))],
        }

    cell = 148
    label_height = 28
    preview = Image.new("RGB", (cell * 3, cell + label_height), (244, 244, 246))
    draw = ImageDraw.Draw(preview)
    font = ImageFont.load_default()
    labels = ("idle", "working", "done")
    for index, (frame, label) in enumerate(zip(finished, labels)):
        reduced = frame.resize((cell, cell), Image.Resampling.LANCZOS)
        checker = Image.new("RGB", (cell, cell), (238, 238, 240))
        check_draw = ImageDraw.Draw(checker)
        block = 12
        for yy in range(0, cell, block):
            for xx in range(0, cell, block):
                if (xx // block + yy // block) % 2:
                    check_draw.rectangle((xx, yy, xx + block - 1, yy + block - 1), fill=(221, 221, 225))
        checker.paste(reduced, (0, 0), reduced)
        preview.paste(checker, (index * cell, 0))
        box = draw.textbbox((0, 0), label, font=font)
        text_width = box[2] - box[0]
        draw.text((index * cell + (cell - text_width) / 2, cell + 8), label, fill=(45, 45, 52), font=font)
    preview_path.parent.mkdir(parents=True, exist_ok=True)
    preview.save(preview_path, optimize=True)

    manifest_path = output_dir / "asset-manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--preview", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(extract(args.source, args.output_dir, args.preview), indent=2))


if __name__ == "__main__":
    main()
