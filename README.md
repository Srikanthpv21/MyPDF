# MYPDF - Mobile PDF Viewer App

<p align="center">
  <img src="assets/icon/app_logo.png" width="128" alt="PDF Viewer App Logo" />
</p>

A high-performance, modern Flutter mobile PDF reader app designed with Material 3 aesthetics, smooth touch gestures, and a floating Heads-Up Display (HUD).

---

## Features

- **Core Reading & Smooth Navigation:**
  - **Continuous Vertical Scroll** & **Single Page Flip Mode** (toggleable anytime).
  - **Pinch-to-Zoom** (up to 400%) with double-tap zoom reset and quick zoom presets.
  - **Interactive Page Jump HUD**: Tap the page badge to open a numeric jump dialog with real-time scrub slider and quick shortcut chips.
  - **Page Thumbnails Drawer**: Slide-up drawer displaying page cards with real-time active indicators and instant jump.

- **Reading Comfort Modes:**
  - **Day / Light Mode**: Paper-white background for crisp daylight reading.
  - **Sepia / Warm Paper Mode**: Warm amber spectrum filter reducing blue light and eye strain.
  - **Night / Dark Inverted Mode**: High-contrast OLED dark filter for dim lighting.
  - **Immersive Fullscreen**: Tap anywhere on the page to toggle top & bottom bars for distraction-free reading.

- **In-Document Search:**
  - Keyword search overlay with active occurrence counter (e.g. 2 / 5).
  - Next / Previous match navigation buttons.

- **Document Library & Sources:**
  - **Preloaded Sample Guides**: Built-in multi-page guides (*Flutter Mobile PDF Guide*, *Mobile UX Design Handbook*).
  - **Device Storage**: Open any PDF from phone storage, downloads, or external drive.
  - **Web Link Loader**: Load remote PDFs directly via URL.
  - **Page Bookmarks**: Pin key pages and filter them inside the thumbnail drawer.

---

## How to Run

### Run on Android Emulator or Device:
```bash
# Check connected emulators
flutter emulators

# Launch emulator (e.g. Pixel 8 Pro)
flutter emulators --launch Pixel_8_Pro

# Run the app
flutter run
```

### Run on Chrome (Web Preview):
```bash
flutter run -d chrome
```

### Run on Windows Desktop:
```bash
flutter run -d windows
```

### Run Unit Tests:
```bash
flutter test
```

### Build Android APK:
```bash
flutter build apk
```
The generated release APK will be located at:
`build/app/outputs/flutter-apk/app-release.apk`

