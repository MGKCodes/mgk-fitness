"""Contact sheet of stills for one film: python sheet.py <Id> <frames...>"""
import subprocess, sys
from PIL import Image
name, frames = sys.argv[1], [int(f) for f in sys.argv[2:]]
ims = []
for f in frames:
    out = f'out/still-{name}-{f:03d}.png'
    ims.append(Image.open(out).convert('RGB'))
s = 0.34
tw, th = int(ims[0].width * s), int(ims[0].height * s)
cols = len(ims)
sheet = Image.new('RGB', (cols * (tw + 4) - 4, th), (60, 60, 60))
for i, im in enumerate(ims):
    sheet.paste(im.resize((tw, th), Image.LANCZOS), (i * (tw + 4), 0))
sheet.save(f'out/sheet-{name}.png')
print(sheet.size)
