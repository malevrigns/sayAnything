"""Regenerate the small, self-hosted website font after editing site copy."""
from pathlib import Path
from fontTools import subset

root = Path(__file__).resolve().parent.parent
web = root / 'server' / 'web'
text = ''.join(p.read_text(encoding='utf-8') for p in [web / 'index.html', web / 'site.js'])
text += ''.join(chr(i) for i in range(32, 127))
options = subset.Options()
options.flavor = 'woff2'
options.layout_features = ['*']
font = subset.load_font(str(root / 'client' / 'assets' / 'fonts' / 'NotoSansSC.ttf'), options)
subsetter = subset.Subsetter(options=options)
subsetter.populate(text=text)
subsetter.subset(font)
target = web / 'fonts' / 'sayanything.woff2'
subset.save_font(font, str(target), options)
print(f'{target.name}: {target.stat().st_size:,} bytes')
