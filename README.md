# macTilt

The **macTilt** 3D clamshell fold animation for MacBooks, driven by the physical lid angle sensor.

> *"When the lid closes, the picture on its screen stays where it is in space while the hardware sweeps through it: the image frosts over and slips into black without ever changing its size."*

Rather than rendering inside a separate window, **the entire macOS display follows the animation in 3D space as you close your MacBook lid**.

## NOTE

- **Opening MacBook**: Works on lockscreen via private skyline APIs
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
- just install and see duh

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
