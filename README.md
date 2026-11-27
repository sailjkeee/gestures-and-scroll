# Gestures & Scroll

[Русская версия](README.ru.md)

Gestures & Scroll is a macOS menu bar utility that lets you **reverse mouse scrolling while keeping natural scrolling on the trackpad**. You can assign shortcuts to three- and four-finger gestures and draw your own shapes to open apps or control windows.

Choose English, Russian, or **System language** at the top of Settings. The menu bar has separate switches for scrolling and trackpad gestures. [Download the DMG for Apple Silicon](https://github.com/sailjkeee/gestures-and-scroll/releases/latest)

## Why I built it

I used two utilities on my Mac. Scroll Reverser gave me separate scroll directions for the mouse and trackpad. In TrackpadGestureMap, I used a three-finger tap to copy and a four-finger tap to paste. I wanted those everyday controls in one menu bar app, along with the ability to draw a shape to open Telegram or another app. That became Gestures & Scroll. [Scroll Reverser](https://github.com/pilotmoon/Scroll-Reverser) · [TrackpadGestureMap](https://github.com/turhe123/trackpad-gesture-map)

## Reverse mouse scrolling

1. Click the trackpad icon in the macOS menu bar and open **Settings… → Scrolling**.
2. Turn on **Control scrolling**.
3. Set **Mouse** to **Classic** and **Trackpad** to **Natural**. This gives the scroll wheel its traditional direction while the trackpad keeps natural scrolling. These are the initial settings.

You can select any of the following modes for each device.

| Mode | What it does |
| --- | --- |
| **Natural** | Scrolls in the same direction as a trackpad with natural scrolling enabled. |
| **Classic** | Uses the traditional mouse wheel direction, opposite to Natural. |
| **Follow macOS** | Uses the system's scroll direction for that device. |

You can also apply the chosen direction to horizontal scrolling and set a fixed number of lines for each notch of a stepped mouse wheel.

## Customize trackpad gestures

Open **Settings… → Gestures**, turn on **Trackpad gestures**, and choose **3 fingers** or **4 fingers**. Set an action for the tap and each swipe direction in **Assignments**. **Last gesture** shows what the app recognized.

| Default gesture | Action |
| --- | --- |
| Three-finger tap | Copy the current selection |
| Four-finger tap | Paste into the active app |
| Four-finger swipe up | Open Mission Control |

Choose Copy, Paste, Cut, Undo, Redo, Select All, Mission Control, Close Window, Minimize Window, Quit App, or No action. If a swipe also triggers a system gesture, turn off the matching swipe in macOS Trackpad settings.

## Draw a shape to open an app

On the built-in trackpad, draw the built-in cross in two strokes, like an X or plus sign, or record your own shape. The cross sends **Quit App** to the active app by default. Assign **Close Window** if you want the cross to close the active window instead.

1. Keep **Trackpad gestures** enabled, then open **Settings… → Drawings** and turn on **One-finger drawings**.
2. Click **Record a Drawing…**. Draw a shape with one finger in one or two strokes, lift your finger, and give the drawing a name.
3. Select an action and save it. To launch an app, choose **Open Application…** and select the installed app in the macOS file picker.

For example, record a right angle and assign it to Telegram. Hold **Control** and repeat that drawing to launch Telegram or bring it to the foreground. The **Activation key** setting also offers **Option** and **No key**. Click the selected app's name to change it later.

## Install on Mac

Requires an Apple Silicon Mac with macOS 14 or later. Open the DMG from the latest release, drag **Gestures and Scroll.app** to **Applications**, and open it from there. [Latest release and DMG](https://github.com/sailjkeee/gestures-and-scroll/releases/latest)

The published app is signed ad hoc. If macOS blocks the first launch and you trust the download, follow Apple's instructions for approving the app in **System Settings → Privacy & Security**. Once it opens, grant the app **Accessibility** access so it can modify scroll events and send shortcuts. [Apple's first-launch instructions](https://support.apple.com/en-us/102445)

## Build and test

Install the Xcode Command Line Tools. Run these commands in the repository.

~~~sh
./check.sh
./build.sh
~~~

The app bundle is written to **build/Gestures and Scroll.app**. The checks cover profile migration, language settings, scroll direction, gesture and drawing recognition with simulated touch frames, app assignments, and the native input bridge. GitHub Actions also runs the checks and build on an Apple Silicon runner.

Profiles are stored locally in UserDefaults. Scrolling uses a Quartz event tap. Built-in trackpad contacts and some device details use private macOS interfaces. Recheck those features on a physical Mac after system updates.

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE) for attribution.
