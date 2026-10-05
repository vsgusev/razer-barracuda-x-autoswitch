# Razer Barracuda X auto switch

Headphones on: Windows plays sound through them. Headphones off: sound goes back to your speakers.

Windows can't do this by itself with the Barracuda X. The USB dongle stays connected when the headphones
are off, so Windows keeps sending sound into it, and you hear nothing until you switch the device by hand.

## Requirements

- Windows 10 or 11
- Razer Barracuda X 2.4 with its USB dongle, USB ID `1532:0550`

To check your USB ID, run this in PowerShell. If it prints a line, your dongle is supported:

```powershell
Get-PnpDevice -PresentOnly -InstanceId 'USB\VID_1532&PID_0550\*'
```

No Razer Synapse, admin rights or extra software needed.

## Install

1. Download the ZIP (green **Code** button, then **Download ZIP**) and extract it.
2. Double-click `install.cmd`.

If Windows warns that the file came from the internet, choose **Run** (or **More info**, then **Run anyway**).

That's it. The switcher starts right away and then at every sign-in, with no window.

Its files go to `%LOCALAPPDATA%\razer-barracuda-x-autoswitch`, so the extracted folder can be deleted afterwards.

## Uninstall

Double-click `uninstall.cmd`.

## Good to know

- **Apps have to use the default device.** In Discord: *Settings, Voice & Video, Output Device: Default*.
  The same goes for games and other apps with their own device setting.
- **Some games pick the device only at launch.** If you turn the headphones on mid-game and the sound
  stays on the speakers, restart the game.
- **Your speakers are remembered automatically.** Whatever device was the default when the headphones
  turned on is what you get back when they turn off.
- **The dongle can't be asked whether the headphones are on**, it only reports changes. If the headphones
  are still the default device when Windows starts, the switcher assumes they are off and switches
  back to your speakers.

## How it works

The dongle has a vendor HID interface (`MI_03`, collection `COL02`). Each time the headphones connect or
disconnect, it sends a 64-byte report:

```
02 0E 50 49 08 xx xx xx 06 00 04 00 20 02 01 01 ...   headphones on
02 0E 50 49 08 xx xx xx 06 00 04 00 20 02 01 00 ...   headphones off
```

The switcher waits for these reports and sets the default output device for all roles, including
communications (calls in Discord, Zoom and so on). It doesn't poll, so it uses no CPU while waiting.

## Other Barracuda X versions

Other revisions use other USB IDs (`1532:0536` for the 2021 model, `1532:0552` for the 2022 model).
They are not tested and may report the connection differently. If you have one, open an issue.

Razer can also change this behavior in a dongle firmware update.
