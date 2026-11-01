<p align="center">
  <img src="Snowdrop-icon.png" alt="Snowdrop" width="128" height="128">
</p>

<h1 align="center">Snowdrop</h1>
<h2 align="center">A minimalistic custom YouTube Music and YouTube client for macOS</h2>

> [!CAUTION]
> This is an unofficial YouTube Music and YouTube client! Google doesn't support it.

> [!NOTE]
> This project is forked from sozercan/kaset

<h3 align="center"><b>⭐️ Features</b></h3>

- **🎵 YouTube Music**: Recommendations are organized like in the original YT Music client, in a floating glass sidebar
- **▶️ YouTube**: Switch to regular YouTube with one button at the bottom of the sidebar. The home page follows the original: topic chips on top and a grid of video cards
- **📱 Shorts**: A vertical Shorts player with like, dislike, share and next/previous buttons
- **💽 Floating Player**: Floating overlay that shows what is playing, a song or a YouTube video, and lets you control it
- **💬 Subtitles**: A YouTube-style CC button in the player bar. Click to toggle, right-click to pick a language
- **🎨 Themes**: Several color themes, adjustable window transparency and blur
- **🔧 Other**: Almost all features from Kaset: https://github.com/sozercan/kaset

<h3 align="center"><b>📟 Requirements</b></h3>

- **macOS Version**: macOS 15.4 or later (Apple Intelligence features need macOS 26)
- **Other**: Google Account (signed-in playback)

<h3 align="center"><b>🔧 Installation</b></h3>

- Download the latest release from Releases
- Open the `.dmg` file
- Drag Snowdrop to Applications
- Gatekeeper will block the app from launching because it's not notarized, bypass it by clicking _Right Click -> Open_ or _System Settings -> Privacy & Security -> Open Anyway_

<h3 align="center"><b>✏️ Building</b></h3>

```zsh
git clone https://github.com/varla-am/snowdrop
cd snowdrop
xcodebuild -project Snowdrop.xcodeproj -scheme Snowdrop -configuration Release build
```

<h2 align="center"><b>⚙️ Credits</b></h2>

**Snowdrop** is a fork of [Kaset](https://github.com/sozercan/kaset) by sozercan, licensed under the MIT license. See [LICENSE](LICENSE).
