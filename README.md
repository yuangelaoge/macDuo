# macTilt

The **macTilt** 3D clamshell fold animation for MacBooks, driven by the physical lid angle sensor.

> *"When the lid closes, the picture on its screen stays where it is in space while the hardware sweeps through it: the image frosts over and slips into black without ever changing its size."*

Rather than rendering inside a separate window, **the entire macOS display follows the animation in 3D space as you close your MacBook lid**.

## NOTE

- **Opening MacBook**: on the lock screen this is not possible due to macOS restrictions (it would require disabling SIP, which is not recommended — any malicious app could then draw a login flow on your lock screen and steal your passwords). The opening animation is implemented for the unlocked desktop.
- **Normal MacBook Use**: when you are actively using your MacBook (lid open), the app does **nothing** — the overlay is completely hidden, with zero CPU/GPU overhead and full click-through.
- **Closing MacBook**: as you tilt the screen closed, the display freezes the screen and seamlessly folds **from up to down** toward the bottom keyboard hinge into the dark void.
- **Clamshell desktop mode**: with an external display attached and the built-in panel asleep, the effect is suppressed — there is no visible hinge motion to animate.

---

## Hardware Support

macTilt adapts to the lid hardware it finds:

- **Macs with Apple's continuous lid angle sensor** (Vendor `0x05AC`, Product `0x8104`, UsagePage `0x0020`, Usage `0x008A`): the fold is driven 1:1 by the live hinge angle, at up to 120 Hz.
- **Macs with only the binary clamshell switch** (for example the MacBook Pro 13" M1): there is no continuous angle to read, so macTilt plays a smooth time-based unfold whenever the lid opens, with an adjustable duration.

---

## Features

### Animation

- **Physical Lid Angle Sensing**: real-time 60 Hz polling of Apple's internal lid angle sensor, with an alpha-beta lead predictor to mask sensor latency.
- **Native Metal Fold**: 3D perspective projection with an up-to-down clamshell hinge bend, rendered at the panel's native refresh rate (120 Hz ProMotion or 60 Hz).
- **True Gaussian Defocus**: a six-level binomial gaussian pyramid feeds a continuous matte blur of any width, with adaptive 12/20/32-tap sampling and a velocity-aware boost during fast closes. No discrete ghost copies, no frosted grain.
- **Glass Treatment**: grazing-angle tint, a specular rim band, a hinge highlight line, and a dark void horizon falloff. The frozen image is never bent or lensed — only dimmed and darkened.
- **Side Blackout**: the horizontal parallax spread that lets the left and right edges fall into the void as the panel tilts away. Adjustable from 0% (the frame keeps its full width) to 200% (a deeper falloff), where 100% matches the physical projection.
- **Full-Screen Seamless Overlay**: spans the entire screen at `.screenSaver` level. Completely click-through, and invisible while the lid is open.

### Settings

- **Screen Recording Permission**: live status, one-click authorization, and troubleshooting with an app relaunch plus a copyable `tccutil reset` command.
- **Battery and Performance**: reports whether capture is dormant or pre-arming. macTilt polls nothing at idle and pre-arms the capture only in the moment the lid starts to close.
- **Tilt Trigger Thresholds** (angle-sensor Macs): set the angle where the fold begins and the angle where it reaches full black.
- **Clamshell Opening Animation** (switch-only Macs): opening duration from 0.4 s to 2.5 s, with Snappy, Natural and Cinematic presets and a live preview.
- **Display Source**: live screen capture (`ScreenCaptureKit`), the current desktop wallpaper, bundled artwork, or a custom image.
- **Menu Bar**: show or hide the live angle readout, or hide the status icon entirely.
- **Physics and Shaders**: follow responsiveness, blur intensity, specular reflection, and side blackout.
- **Lock Screen and Sleep Wake**: raises the overlay priority so the animation survives wake transitions.
- **Interactive Preview**: scrub the whole fold on screen without physically moving the lid.
- **Software Updates**: current version, a manual check, download of the latest DMG, and an automatic background check on launch.

### Menu Bar

- Live angle readout (for example `126°`) next to the status icon.
- **Settings** (Command-Comma) and **Check for Updates** (Command-U).
- Opening-animation controls and speed presets on switch-only Macs.
- **Quit macTilt** (Command-Q).

---

## Requirements

- macOS 14.0 or later.
- A MacBook with a lid. The hardware paths need a hinge to read; on a desktop Mac only the interactive preview is available.
- Xcode Command Line Tools (`swiftc`, `xcrun metal`).

---

## Building and Installing

Run the automated build script:

```bash
./build.sh
```

Every run of `./build.sh`:

1. Increments the patch version and the build number in `Info.plist`.
2. Compiles the Metal shaders into `default.metallib`.
3. Compiles the Swift application as a universal binary (arm64 + x86_64, targeting macOS 14.0+).
4. Codesigns the app bundle.
5. Creates `build/macTilt.dmg`.
6. Installs directly to `/Applications/macTilt.app`.

---

## Launching

Open the installed application from `/Applications`, or run:

```bash
open /Applications/macTilt.app
```

The menu bar icon shows your current lid status. **Settings** lets you customize the tilt thresholds and preview the animation live.

---

## Credits and Acknowledgements

- **Lid Angle Sensor**: inspired by the hardware reverse-engineering documented in [samhenrigold/LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor) by [@samhenrigold](https://github.com/samhenrigold).
