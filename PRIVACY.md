# Privacy

Island runs locally. It has no accounts, analytics, telemetry, or servers.

- **Media, timers, downloads, battery, devices, mic/camera, calendar, clipboard** are read on your Mac and only shown in the island. Nothing is stored beyond what's on screen.
- **Mic/camera detection** only checks *whether* a device is in use. Island never records audio or video.
- **Clipboard** (off by default) shows a short preview for 2.5 seconds. Items marked concealed by password managers are ignored. Nothing is saved.
- **Web search** sends your query directly to the providers you enable (Wikipedia, DuckDuckGo, or Brave with your own key). Album art may be fetched from the URL the media app provides.
- **AI** (off by default) sends your question and fetched page text to the provider you choose (Anthropic, OpenAI) using your own API key, or to a local Ollama model. Keys are stored in your macOS Keychain.
- **Updates** (on by default, Settings › General): once a day Island asks GitHub's public API for the latest release and its `version.json`. The request carries a generic `Island` user agent and nothing about you; GitHub sees your IP address as with any web request. Island never downloads or installs anything. It shows a link to the release page.
- **AirPods details** come from `system_profiler SPBluetoothDataType`, Apple's local reporting tool, to read the model and battery levels. Nothing leaves your Mac.
- **Teleprompter voice follow** (off by default) uses on-device speech recognition. Audio is never recorded or sent anywhere.
- **Settings** are stored in Island's UserDefaults.
