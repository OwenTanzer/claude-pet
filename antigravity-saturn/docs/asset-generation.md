# Saturn asset generation

The three Saturn states were generated as one coherent strip with the built-in image-generation path, using the full Moon frame as a house-style reference. The source was placed on a flat magenta chroma background, converted to alpha without purple-destroying despill, then deterministically cropped and normalized to three 360×360 frames.

Core prompt:

> Create one coherent horizontal strip containing exactly three equally spaced Saturn mascot poses, all the same character and scale: idle, working, and done/celebrating. Use the supplied Moon mascot only as the house-style reference for flat-color warmth, integrated face, bold friendly contour, simple crater-like texture, and small-size legibility. Draw a deep indigo/plum Saturn with warm amber and dusty-coral bands, thick golden rings passing behind the upper globe and in front of the lower globe, and a face integrated into the planet. Keep the three states consistent, isolated, fully visible, unlabelled, and free of detached effects on a flat `#ff00ff` chroma background.

Regenerate normalized frames from an approved transparent strip:

```powershell
python tools\extract-saturn-frames.py `
  --source assets\source\saturn-strip-transparent-v3.png `
  --output-dir assets `
  --preview docs\saturn-preview.png
```
