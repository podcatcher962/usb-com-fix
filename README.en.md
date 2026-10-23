# USB / COM Port One-Click Fix

<p align="center">
  <a href="README.md">简体中文</a> &nbsp;|&nbsp; <b>English</b>
</p>

> Make an undetected USB / COM device detectable again, and pin it to a fixed COM port.

<p align="center">
  <a href="https://github.com/podcatcher962/usb-com-fix/releases/latest">
    <img src="https://img.shields.io/badge/Download_v3.0-3DC98A?style=for-the-badge" height="40" alt="Download">
  </a>
</p>

<p align="center">
  <b>Direct link:</b><br>
  <a href="https://github.com/podcatcher962/usb-com-fix/releases/download/v3.0.0/usb-com-fix-v3.0.0.zip">
    https://github.com/podcatcher962/usb-com-fix/releases/download/v3.0.0/usb-com-fix-v3.0.0.zip
  </a>
</p>

<p align="center">
  <sub>Unzip -> double-click the .bat -> approve UAC -> click "Diagnose" (diagnosis + repair in one go)</sub>
</p>

<p align="center">
  <img src="docs/screenshot-en.png" width="700" alt="English UI">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Windows-7%20%7C%208%20%7C%2010%20%7C%2011-0078D6?logo=windows&logoColor=white">
  <img src="https://img.shields.io/badge/arch-x86%20%7C%20x64-4D9EF5">
  <img src="https://img.shields.io/badge/PowerShell-5.1+-5391FE?logo=powershell&logoColor=white">
  <img src="https://img.shields.io/badge/license-MIT-3DC98A">
  <img src="https://img.shields.io/badge/lang-中文%20%7C%20English-8A94A6">
</p>

---

## What it is

When a Windows PC has USB devices plugged and unplugged at high frequency over a long period
(USB-serial adapters, dev boards, burners, test fixtures, card readers, USB NICs...), the device
records pile up and eventually rot. The typical symptoms:

- You plug in a USB device and **Device Manager shows nothing new** - not even a yellow mark
- Or an "Unknown device" with a yellow mark and code 10 / 43
- Devices plugged before still work; **anything new gets no response at all**
- Uninstall the device and reboot: it works once, then fails again
- Reinstalling Windows helps for a while, then it comes back weeks later
- Another PC works fine with the same device; only this one fails
- The COM number keeps jumping (COM3 -> COM7 -> COM11) and no longer matches your software
- The COM numbers are exhausted, or a newly plugged device gets no number at all

This tool targets exactly that symptom group: **one click, clear everything that blocks detection,
and pin what needs to be pinned.**

It is not a "cleanup utility" - cleanup is only the means. **The goal is getting devices detected again.**

> Production and industrial PCs hit the last case most often: to keep port numbers stable, someone
> once wrote `PortName` by hardware ID via a .bat or hand-edited registry - but never synced the
> system's port bitmap. That is the classic cause of "a brand-new device is not detected at all".
> See [Why pinning ports breaks itself](#why-pinning-ports-breaks-itself).

---

## The seven steps

One click on "One-click fix" runs these in order:

| # | Step | What it does |
|---|---|---|
| 1 | **Snapshot** | Full copy of the original state, restorable at any time |
| 2 | **Fix system-level blockers** | Device installation policy banning new devices, broken `Enum` permissions, leftover class filter drivers, disabled USB storage / device installation services, driver search set to "never install", rotation of `setupapi.dev.log` when it grows past ~10 MB |
| 3 | **Remove offline records** | Records of devices that were unplugged long ago and still hold a slot |
| 4 | **Clear failure flags** | `Install failed` / `Reinstall pending` flags - new devices often stall right here |
| 5 | **Repair the COM bitmap** | When `COM Name Arbiter` disagrees with reality, new devices get no port |
| 6 | **Rescan hardware** | Let Windows enumerate once more |
| 7 | **Pin the port** | Pin currently plugged-in serial devices to your target number (default COM3) |

**Steps 3-5 only touch records that are NOT online.** Devices that are currently plugged in are never touched.

### Scope (selectable in the UI, four options)

| Scope | What is cleaned | When to use |
|---|---|---|
| Serial ports (COM) | Serial class only | You know the model is USB-to-serial |
| Vendor-specific | `Vendor` / `Composite` only | Burners, test fixtures |
| **All USB devices (default)** | Both of the above, excluding HID | Use when unsure |
| All USB devices (incl. HID) | Adds offline HID records | The new model uses HID class (shows under "Human Interface Devices") |

Whatever the scope, keyboards, mice, audio, cameras, NICs, printers, hubs and controllers are
protected and never deleted.

> Pure USB devices (no COM port) are covered too: steps 5 and 7 skip themselves, steps 2-4 and 6
> still apply. To judge whether it can be fixed, click **Diagnose** and read section 7:
> a `FAILURE(0x...)` for that VID/PID means the install chain is blocked (fixable); no install
> attempt at all means the device was never enumerated (hardware/descriptor level, out of scope).

---

## Why pinning ports breaks itself

This is the part worth reading carefully.

Windows tracks COM numbers with two tables:

| | Location | Role |
|---|---|---|
| **1. Device nameplate** | `Device Parameters\PortName` inside each device record | "I am COM3" |
| **2. Master ledger** | `HKLM\SYSTEM\CurrentControlSet\Control\COM Name Arbiter\ComDB` | 32-byte bitmap, 256 bits, which numbers are taken |

**Changing the port in Device Manager updates both tables.**
**Editing the registry by hand (or using a "batch-write PortName by VID/PID" .bat found online)
updates only table 1.**

The result: the device says "I am COM3", the ledger says "COM3 is free", a new device asks for a
number and gets one that collides with the hard-coded nameplate -> Windows refuses to start it ->
**Device Manager shows nothing at all.**

That is the root of "what was plugged before still works, anything new gets no response".

This tool follows the logic of the official path:

| | Typical .bat / online script | This tool |
|---|---|---|
| Lookup key | VID/PID - **every** historical instance of that model | **Instance ID** - only the one currently online |
| What it writes | `PortName` only | `PortName` **plus** the `ComDB` bitmap |
| Device absent | Writes anyway (touches dead records) | Does not write |
| Conflicts | Unaware; many records all set to COM3 | Target occupied -> **skip and report** |
| Takes effect | Reboot the whole system | Restart that one device (seconds) |

---

## Safety boundaries

- ✅ **Only offline records are removed** - plugged-in devices are never touched
- ✅ **No reliable list, no deletion**: if the online device list cannot be read, the step is skipped and flagged
- ✅ **Root hub self-check**: if even the on-board root hub is reported offline, the logic is wrong -> refuse to delete
- ✅ **Ancestor protection**: if a composite device has a protected child interface (e.g. a keyboard receiver), the parent is skipped as well
- ✅ **Hubs/controllers, keyboards, mice, audio, cameras, NICs, printers: never touched**
- ✅ **Everything is snapshotted** to `C:\ProgramData\ComFix\backup\`; menu "Restore last" rolls back
- ⚠️ **`DenyDeviceIDs` blocks are detected but not removed automatically** - those are usually set by IT on purpose

---

## Usage

```
1. Unzip, double-click "请双击这个-USB串口一键修复.bat"
2. Approve the UAC prompt (admin rights are required to modify device records)
3. Plug in the device that is not detected, and keep it plugged in
4. Click "Diagnose" - read-only diagnosis first, then repair if a fixable cause is found
5. When asked whether to reboot, click Yes
6. After rebooting, plug in a new device and see whether it is detected
```

**"Diagnose" is the second button on the main window.** It runs the read-only deep diagnosis
first, reads a machine-readable `[VERDICT]` line at the end of the report, and decides on its own
whether to continue:

| Verdict | Basis | What the tool does |
|---|---|---|
| **Fixable** | install policy blocks new devices / the last install ended in `FAILURE(0x...)` / unknown devices present / leftover class filters / "install failed" flags | asks once (default button is Yes), then repairs immediately |
| **Not enumerated** | no unknown device at all and no log entry for that device | **report only, nothing is changed** - that case is port / cable / power |

To get a report without letting it touch anything: menu **Tools -> Diagnosis report only**.

**No device needs to be plugged in beforehand.** Without a device, steps 1-6 still run as a
"clear the field" pass; with a device plugged in, step 7 is added.

### After the fix, three possible outcomes

```
Plug in a new device
  ├─ Detected, port is already the target   -> done, back to production
  ├─ Detected, port is wrong                -> turn on "Auto-pin", fixed within 2 seconds
  └─ Still not detected at all              -> click "Diagnose"; if it still fails, send the report
```

---

## Auto-pin

Click "Auto-pin: OFF" -> the button turns red and stays on.
From then on **every newly plugged device is pinned to the target number within 2 seconds** -
no more registry editing.

Intended for the case where every device looks brand new to Windows. If your devices share a single
record (no serial number), a single fix pass is enough and auto-pin can stay off.

---

## Pure USB devices vs serial devices

A common misconception first: **a pure USB device is not necessarily a HID device.** HID is just one
kind (keyboards, mice, gamepads, custom HID boards). Others are vendor-specific devices
(WinUSB / libusb - most burners and test fixtures fall here), mass storage, NICs, audio, cameras,
printers. What they share is that **Windows assigns them no COM number.**

The tool routes each record by what that record actually is, not by a blanket setting:

| Device type | Clean offline records | Write port number / pin |
|---|---|---|
| Serial (COM port) | Yes | Yes |
| Vendor-specific / HID / storage / NIC / audio | Yes (HID only with the incl.-HID scope) | **No, never** |
| Hubs / USB controllers | No | No |

Port writing has two gates:

1. **Candidates come only from the serial category** - HID, vendor-specific, storage and NIC devices
   never enter the candidate list
2. **A hard check on top of that** - the device must already own a Windows-assigned COM number, or
   its device class must be `Ports`. If neither holds, it is skipped and not a single byte is written

So a pure USB device **never gets a port name and never occupies a slot in the COM pool**. It only
benefits from "remove stale offline records" and "fix system-level blockers" - pure gain, no side
effects. Serial models are still pinned as before, and both kinds can share one PC without interfering.

### One physical limit no software can bypass

A USB device without a serial number gets its record **per USB port it is plugged into**:

```
Same device in port 1 -> one record (pinned to COM3)
Same device in port 2 -> a different record (treated as new, gets a new number)
```

This is a Windows rule, not a flaw of the tool. Therefore:

- Pinning assumes the device is **always plugged into the same USB port** - label the port on the bench
- If the port must change, leave "Auto-pin" running and it corrects the number within 2 seconds
- Pinning by VID/PID works for **all devices of the same model**, because they share one record set -
  which is exactly why the old .bat kept working

---

## Bilingual

The **right side of the menu bar has two buttons: "中文 | English"**. The active language is shown in
bold blue - one click switches the whole window. There is no "Language" drop-down, so an English
speaker never has to recognise a Chinese menu label: seeing `English` is enough.

What switches: title bar, the rest of the menu bar, buttons, drop-downs, status bar, log, every
message box, all three documentation dialogs - **even the generated report files match the selected
language**. The choice is remembered, and the first launch follows the system language.

---

## Compatibility

| Item | Support |
|---|---|
| OS | Windows 7 / 8 / 8.1 / 10 / 11, including LTSC |
| Architecture | 32-bit / 64-bit |
| Runtime | System .NET Framework and PowerShell 5.1 only - **nothing to install** |
| Network | **Never connects to the internet** |
| Installation | Portable, unzip and run |

On small screens (1024x768 / 1280x1024) the layout scales down to fit the work area; if it is truly
too small, scrollbars appear so no button becomes unreachable.

---

## Reports

Written to the desktop automatically:

| File | When |
|---|---|
| `Device-Check-Report.txt` | Refreshed after every "Check only" or "One-click fix" |
| `USB-Fix-Error-Report.txt` | On error, with line numbers, call stack and operation log |
| `USB-Not-Detected-Report.txt` | Only when the program cannot even open its window |

Contents: COM pool usage, record counts per USB category, offline counts, top 15 most accumulated
models, system-level status, and the per-step result of the run.

---

## Diagnose / Deep inspection

**Main-window button "Diagnose"** = deep diagnosis + immediate repair when a fixable cause is found,
in a single click.
**Menu "Tools -> Diagnosis report only"** = diagnose without repairing (when you only want a report).

The diagnosis itself is **read-only**: it changes no setting and deletes no record; the only write is a
temporary registry key that is deleted immediately.

Run it with the undetected device plugged in. Ten sections:

1. System and privileges
2. COM port bitmap
3. USB record statistics (with / without serial number)
4. Error code list
5. Current USB devices (`Win32_PnPEntity`)
6. Device installation policy
7. Windows driver setup log (`Exit status` success vs `FAILURE(0x...)`)
8. `Enum\USB` write test
9. Services and driver cache state
10. **Conclusion** - reading this section alone is usually enough

---

## Repository layout

```
usb-com-fix/
├─ src/
│  ├─ comfix-gui.ps1          UI, bilingual, menus
│  ├─ comfix-core.ps1         seven steps, snapshot/restore, reports
│  ├─ usbprobe.ps1            deep inspection (read-only)
│  └─ report-launch-fail.ps1  fallback report when startup fails
├─ docs/
│  ├─ screenshot-zh.png
│  └─ screenshot-en.png
├─ 使用说明（先看这个）.txt      user guide (Chinese)
├─ build.py                   builds the distributable folder + zip (and the .bat)
├─ LICENSE
├─ README.md                  Chinese
└─ README.en.md               English
```

---

## Build it yourself

```bash
python build.py
```

Produces `USB串口一键修复-发给生产部/` and the matching `.zip`.
`build.py` converts `.ps1` to **UTF-8 with BOM + CRLF** and `.bat` to **GBK** - PowerShell 5.1 and
cmd have different encoding requirements, and neither step can be skipped.

---

## Known limitations

- **Hardware cannot be fixed**: physically damaged ports, insufficient power, broken controller
  drivers are outside what software can do
- **Driver matching failures**: if the required driver is not present on the system, install it first
- **`DenyDeviceIDs` blocks**: detected and reported, not removed automatically
- **Not yet validated on other machines**: the logic is fully verified here (dry runs, ACL unit tests,
  online/offline detection, the hard check that refuses to write port names to pure USB devices), but
  the "delete records -> change number -> restart device -> takes effect" chain is only truly proven
  on a real faulty machine
- **Changing the USB port invalidates a pinned number**: records of devices without serial numbers
  are generated per port position. That is a Windows rule no software can bypass. Keep the same port,
  or leave "Auto-pin" on

---

## License

MIT License - see [LICENSE](LICENSE).

---

## Disclaimer

**Read this section in full before use. Using this program means you understand and accept all terms below.**

1. **System-level changes.** This program modifies the Windows registry (device records, the
   `COM Name Arbiter` port bitmap), device installation policy, the device setup log, and the state
   of some devices. Such operations carry risks that cannot be fully eliminated.
2. **No warranty.** The program is provided "AS IS", without warranty of any kind, express or implied,
   including but not limited to the warranties of merchantability, fitness for a particular purpose,
   and non-infringement. The author does not guarantee that it will fix any specific fault, nor that
   it is free of side effects.
3. **Limitation of liability.** To the maximum extent permitted by applicable law, the author shall not
   be liable for any direct, indirect, incidental, special, or consequential damages arising from the
   use of, or inability to use, this program - including but not limited to loss of data, device
   malfunction, production downtime, schedule delays, and loss of business profits.
4. **Validate on one machine first.** Before rolling out, **test on a single machine** and confirm it
   works without adverse side effects. Create a system restore point or a full backup on critical
   machines. The built-in "Restore last" function is a convenience, not a guarantee of data safety.
5. **Out of scope.** This program does not modify firmware, flash chips, or the device being repaired,
   and does not touch any production or business software. Hardware faults (damaged ports,
   insufficient power, faulty controllers) are outside its scope.
6. **Authorized use only.** Run this program only on computers you own or are authorized to administer.
   You are responsible for any consequence of using it beyond that authorization.
7. **Not accepted?** If you do not agree with any of the above, stop using the program immediately and
   delete all of its files.

---

## Author

**© 2026 永远的兰兰 · Lanlan Eternal**
