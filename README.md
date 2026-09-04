# PillVolume

A lightweight rootless iOS 16 tweak that replaces Apple's stock volume HUD with the classic SmartVolumeControl3-style **Pill** HUD.

## Current beta

- Dark rounded pill in the top-left
- Green fill tracks the current volume
- White speaker icon
- Smooth live updates while pressing volume up/down
- Automatically fades out after 1 second
- Suppresses the stock iOS volume HUD
- Works in SpringBoard, apps, and on the Lock Screen because the HUD is hosted by SpringBoard
- Built for rootless Dopamine-style jailbreaks

## Target

- iOS 16.x
- arm64 / arm64e
- Rootless Theos package

The default dimensions are 125 x 48 points, matching the proportions of the reference SmartVolumeControl3 Pill screenshot as closely as practical on modern Retina devices. On notched iPhones the pill is positioned just below the status-bar safe area so it does not sit underneath the notch.

## Building

GitHub Actions builds the `.deb` automatically after every push to `main`. Open the latest **Build rootless deb** workflow run and download the `PillVolume-rootless-v0.1.0` artifact.

## Credits

Inspired by the Pill HUD style from [SmartVolumeControl3](https://github.com/midkin/SmartVolumeControl3). PillVolume is a new iOS 16 implementation rather than a direct port of the original tweak.

The iOS 16 stock-HUD suppression hook uses `SBVolumeControl`'s `_presentVolumeHUDWithVolume:` presentation path, which is also used by modern open-source iOS 16 volume UI tweaks.
