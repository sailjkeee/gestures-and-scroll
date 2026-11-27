# Gestures & Scroll

[Русская версия](README.ru.md)

Gestures & Scroll is a bilingual macOS menu bar utility. Set separate scrolling directions for a mouse and a trackpad, assign actions to multi-finger gestures, and draw your own shortcuts on the built-in trackpad.

## What it does

- Choose natural, classic, or macOS scrolling independently for the mouse and trackpad. A fixed mouse wheel step is optional.
- Assign actions to three- and four-finger taps and swipes. The initial settings copy with three fingers and paste with four.
- Draw a cross or record a figure in one or two strokes. A figure can send a shortcut, control a window, or open an application you choose.

## Open an application with a figure

Open **Settings → Drawings** from the menu bar icon. Pick **Open Application…** next to a saved figure, or **Record a Drawing…** to create one, then select an installed macOS application in the file chooser. Click the selected application's name to change it later.

Draw the figure with the configured activation key. The default key is Control. macOS activates the selected app if it is already running, or launches it otherwise.

## Build and test

The build targets Apple Silicon Macs running macOS 14 or newer. It uses the Xcode Command Line Tools, Swift, and system frameworks. From the project directory, run the following commands.

~~~sh
./check.sh
./build.sh
~~~

The app bundle is written to **build/Gestures and Scroll.app**. Open it from Finder and grant the app access in **System Settings → Privacy & Security** when requested. The Accessibility entry is called **Device Management & Data Access** on some macOS versions. The app uses this permission to change scroll events and send keyboard shortcuts.

The checks cover input profiles, scroll direction rules, simulated touch frames, application assignments, and native symbol availability. To verify hardware behavior, use a mouse wheel and the built-in trackpad on a Mac with the permission enabled.

## Development and distribution

- **Sources/** contains the settings UI, gesture recognizers, scroll processing, and the native input bridge.
- **Tools/** contains automated checks and app icon generation.
- **Resources/** contains bundle metadata and Russian and English localizations.
- **.github/workflows/** defines a build and check job on a GitHub-hosted Apple Silicon Mac.

Profiles are stored in local UserDefaults. Scrolling uses a Quartz event tap. Built-in trackpad contacts and some device details use private macOS interfaces, so recheck those features on new system versions.

The build script creates an ad hoc signed app for local testing. An update to an ad hoc signed build can require reauthorizing the app in macOS. For distributing a downloadable app to other Macs, follow Apple's Developer ID signing and notarization workflow. [Distribution signing](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/), [Notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

## Publish the source to GitHub

Create an empty repository, then run these commands from the project directory with your repository address. GitHub Actions runs the build and checks after the push.

~~~sh
git init -b main
git add .
git commit -m "Initial public release"
git remote add origin YOUR_GITHUB_REPOSITORY_URL
git push -u origin main
~~~

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE) for attribution.
