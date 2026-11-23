# Roadmap

**Done (v0.1):**
- Notch-anchored island with compact, minimal, expanded and search states
- Priority engine with deterministic ordering
- Liquid Glass
- Universal media (Music, Spotify, VLC, browsers)
- Timers, downloads, mic/camera, battery, devices, network, calendar and clipboard
- Settings, debug panel and performance overlay
- Search (apps, files, actions, web), AI research with citations, automation engine
- CI and releases

**Done (v0.2):**
- Teleprompter: timed or voice-follow scrolling, pause on hover, hidden from capture, opens with the camera (optional)
- File shelf with AirDrop drop target
- Click the media artwork or title to open its app
- Compact Island is solid black by default, like Apple's Dynamic Island

**Next**
- Automation rule editor UI (the engine and storage already exist)
- Keyboard control of the expanded Island (Tab through controls; Space to play/pause the teleprompter)
- Drop a .txt or .md file on the Island to load it into the teleprompter
- Per-app media allow list; more browsers
- Focus-mode-aware quiet hours
- Localization
- Optional Sparkle-style update check against GitHub Releases

**Known limits (platform)**
- macOS has no public API to read system-wide Now Playing. Island supports apps that expose their state publicly (see README).
- Calls (FaceTime and others) have no public observation API, so the `call` kind is available to custom and test activities only.
- Island can see that the mic or camera is in use, but not stop another app's recording.
