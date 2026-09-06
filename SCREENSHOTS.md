# Screenshots — Screenshot Buddy

```
docs/screenshots/{locale}/raw/      # real app window captures
docs/screenshots/{locale}/banners/ # framed 1280×800 marketing images
docs/screenshots/mock-content.md
```

Locales: `en`, `nl`, `pt`, `es`, `fr`, `it`, `ar`, `zh`, `ru`, `ja`.

## Capture real UI

```bash
# Builds apps, seeds demo data, captures every locale, then frames banners
./shared-buddy/scripts/marketing/capture_real_screenshots.sh all

# Or one app:
./shared-buddy/scripts/marketing/capture_real_screenshots.sh screenshot
```

Each launch uses `-BuddyMarketingCapture` + `-AppleLanguages '(xx)'`.

Frame existing raws only (does not overwrite with PIL mocks):

```bash
python3 shared-buddy/scripts/marketing/generate_marketing_banners.py --frame-only
```

Banner size: **1280×800**. Brand frame uses the Screenshot Buddy orange / amber / peach icon gradient.

## Required shots

| ID | Feature | Banner title (en) | Banner description (en) |
|----|---------|-------------------|-------------------------|
| gallery | Gallery | All your shots | Browse, search, and open captures in one clean gallery. |
| editor | Annotate | Quick edit | Draw, arrow, text, crop, blur, and black-box in one editor. |
| redact | Auto-blur | Hide secrets | Auto-detect passwords, IBANs, and cards — blur in one tap. |
| smart | OCR + color | Smart tools | OCR copy text and pick hex colors straight from the shot. |
| qr | QR scan | Scan every QR | List every QR in a shot — open links or copy payloads instantly. |
| menubar | Menu bar | Menu bar ready | Grab recent shots from the menu bar without leaving your flow. |
