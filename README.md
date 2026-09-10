# Capture Buddy

macOS screenshot gallery with quick edit, redact, and export.

```bash
ln -sfn ../../shared-buddy Vendor/shared-buddy
xcodegen generate
xcodebuild -scheme ScreenshotBuddy -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO
```

Ship to the Mac App Store (sign, metadata, screenshots): see [FASTLANE.md](FASTLANE.md).
