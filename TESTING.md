# Testing — Capture Buddy

## Unit

```bash
xcodebuild test -scheme ScreenshotBuddy -destination 'platform=macOS'
```

## UI / e2e

Smoke: launch, gallery accessibility id visible.

## CI

GitHub Actions: `xcodebuild test` on `macos-latest`.
