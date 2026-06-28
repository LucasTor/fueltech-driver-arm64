# driver-arm64

ARM64 (Windows on ARM) FuelTech USB driver package.

| File | Purpose |
|------|---------|
| `datalogger.inf` | FuelTech-branded ARM64 (NTARM64) INF |
| `libusb0.sys` | ARM64 kernel driver — libusb-win32 1.4.0.2, EV-signed (DonTech ApS / GlobalSign) |
| `sign-and-install.ps1` | Generates + signs the catalog and installs the package |
| `libusb0.dll` | ARM64 user DLL (optional; emulated apps use the x86/x64 DLL) |
| `datalogger.cat` | *Generated here by `sign-and-install.ps1` in the VM — not committed* |

➡️ **Full background and step-by-step install instructions are in the
[repository README](../README.md).**
