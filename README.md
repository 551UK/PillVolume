# PillVolume

PillVolume is a lightweight rootless iOS 16 tweak that replaces Apple's stock volume HUD with a compact SmartVolumeControl3-style **Pill** HUD.

## Features

- Dark rounded pill in the top-left
- Green fill tracks the current volume
- White speaker icon that changes at mute/low volume
- Smooth live updates while pressing volume up/down
- Automatically fades out after about 1 second
- Suppresses the stock iOS volume HUD while enabled
- Works from SpringBoard, inside apps, and on the Lock Screen
- Settings pane with a master Enable switch and Respring button
- Rootless package for Dopamine-style jailbreaks

## Target

- iOS 16.x
- arm64 / arm64e
- Rootless Theos package

The default pill is 126 x 48 points and is positioned just below the status-bar safe area on notched iPhones to closely match the supplied SmartVolumeControl3 Pill reference.

## Building / DEB

GitHub Actions builds the rootless `.deb` automatically after every push to `main`. Open the latest **Build rootless deb** workflow run and download the `PillVolume-rootless-v0.1.0` artifact.

Package ID: `com.551.pillvolume`

## Credits

Inspired by the Pill HUD style from [SmartVolumeControl3](https://github.com/midkin/SmartVolumeControl3). PillVolume is a new iOS 16 implementation rather than a direct port of the complete SmartVolumeControl3 tweak.
