# FuelTech USB driver — ARM64 (Windows on ARM)

FuelTech's USB driver ships only for x86/x64, so the device won't install on
**Windows 11 on ARM** (e.g. a **UTM** VM on an Apple Silicon Mac). This repo adds a
working **ARM64** version.

> Verified working on **UTM (QEMU) + Windows 11 ARM** with a **FuelTech PowerFT
> ECU** (`USB\VID_1C5E&PID_1002`).

## What the original driver actually is

The original "driver" turned out to be a rebranded copy of the open-source
**[libusb-win32](https://github.com/mcuee/libusb-win32)** — confirmed by the build
path embedded in the binary (`...\libusb-win32\...\amd64\libusb0.pdb`). The only
FuelTech-specific part is the **INF file**, which binds the generic driver to
FuelTech's USB IDs (`VID_1C5E`: WBO2 / PRO24 / DashBoard / Dyno / CAN / Bootloader).

So **nothing in the binary needs reverse engineering**: a `.sys` is native machine
code that can't be "translated" to ARM64, but the source is public *and an ARM64
build already exists*. We pair an upstream ARM64 `libusb0.sys` with a
FuelTech-branded ARM64 INF.

## How it works on Windows on ARM

| Component | Architecture needed | Why |
|-----------|--------------------|-----|
| `libusb0.sys` (kernel driver) | **ARM64 native** | The Windows kernel runs native code only — no emulation in kernel mode. |
| `libusb0.dll` (user library) | **x86 or x64** (match the app) | FT Manager runs under emulation and loads its same-bitness DLL, which talks to the native ARM64 `.sys` over IOCTL. |

So you only swap in a **native ARM64** `libusb0.sys`; the app keeps using its
existing x86/x64 `libusb0.dll`.

## Layout

| Path | What it is |
|------|------------|
| `driver-arm64/datalogger.inf` | FuelTech-branded ARM64 (NTARM64) INF |
| `driver-arm64/libusb0.sys` | ARM64 kernel driver — libusb-win32 1.4.0.2, EV-signed (DonTech ApS / GlobalSign) |
| `driver-arm64/sign-and-install.ps1` | Generates + signs the catalog and installs the package |
| `driver-arm64/libusb0.dll` | ARM64 user DLL (optional; emulated apps use the x86/x64 DLL) |

---

# Installation

Run everything below **inside the Windows 11 ARM VM**.

### Dead ends (don't waste time on these on ARM64)

- **Zadig 2.9** fails with *"Operation not supported or not implemented"* — its
  libwdi backend can't install libusb-win32 on Windows-on-ARM (even the
  `zadig-2.9_mod.exe` that bundles the ARM64 driver).
- **Plain "Update driver → Browse"** on the unsigned package hard-blocks with
  *"The third-party INF does not contain digital signature information"* and **no
  "Install anyway" button** on ARM64.

The procedure that works is below.

## Step 1 — Enable Test Mode

`libusb0.sys` is EV-signed but **not** Microsoft-attestation signed, which
Windows-on-ARM requires for kernel drivers — so you must relax enforcement. UTM has
no Secure Boot checkbox; it's in the VM's UEFI firmware menu.

1. In Windows, open an **Administrator Command Prompt** and run:
   ```
   bcdedit /set testsigning on
   ```
   - ✅ *"The operation completed successfully."* → reboot, confirm the **"Test
     Mode"** watermark (bottom-right of the desktop), then go to Step 2.
   - ❌ *"...protected by Secure Boot policy..."* → Secure Boot is on; do the next
     step first.
2. **Only if you got the Secure Boot error — disable it in UTM's firmware:** shut
   down, start the VM and **spam `Esc`** to enter the **edk2/TianoCore** menu →
   **Device Manager → Secure Boot Configuration → uncheck "Attempt Secure Boot"** →
   **F10** to save → boot Windows, then rerun `bcdedit /set testsigning on` and
   confirm the **"Test Mode"** watermark.
   *(`shutdown /r /fw` does **not** work on UTM — it returns error 203.)*

## Step 2 — Sign the package

The kernel accepts the EV-signed `.sys` in Test Mode, but the PnP *installer* still
refuses to stage an unsigned package. Generate a self-signed catalog for it.

1. Copy the `driver-arm64` folder into the VM (e.g. to the Desktop).
2. In an **Administrator PowerShell**, from that folder:
   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass -Force
   .\sign-and-install.ps1
   ```
   This creates a trusted self-signed cert, builds `datalogger.cat`, and signs it
   (with `-IncludeChain All`, required so the self-signed root is embedded). Its
   install attempt **will fail** with *"publisher not trusted"* — that's expected on
   ARM64; the catalog is what we needed. Continue to Step 3.

## Step 3 — Install with enforcement off (one time)

ARM64's driver trust provider rejects the self-signed catalog during staging, so
stage it once with enforcement disabled:

1. **Settings → System → Recovery → Advanced startup → Restart now** →
   **Troubleshoot → Advanced options → Startup Settings → Restart** → press **7**
   ("Disable driver signature enforcement"). *(Leave Test Mode on — this is an
   additional one-time relaxation.)*
2. After that reboot, in **Administrator PowerShell**:
   ```powershell
   pnputil /add-driver "<path>\driver-arm64\datalogger.inf" /install
   ```
   It now reports **"Added driver packages: 1"** and binds the device. If it's still
   under "Other devices," right-click it → **Update driver → Browse** → the
   `driver-arm64` folder.
3. Reboot **normally** (back to plain Test Mode). The package is staged in the
   driver store and `libusb0.sys` is EV-signed, so it loads — the device stays bound.

## Step 4 — Point the app at the right `libusb0.dll`

FT Manager loads `libusb0.dll` from **its own install folder**, and already ships
one — so usually nothing to do. It just has to match the app's bitness (x86 or x64,
**not** ARM64, since the app runs under emulation).

If the device is healthy in Device Manager but the app still can't see it, replace
that `libusb0.dll` with the matching-bitness build from the **libusb-win32 1.4.0.2**
release (`bin/x86/libusb0.dll` for a 32-bit app, `bin/amd64/libusb0.dll` for a
64-bit app): https://github.com/mcuee/libusb-win32/releases/tag/release_1.4.0.2 .
Check bitness in Task Manager → Details (FT Manager showing "(32 bit)" → x86).

## Verifying

- **Device Manager**: the device appears under *libusb-win32 devices* / *Fueltech
  USB Devices* with no yellow `!`.
- **PowerShell**: `Get-PnpDevice` shows the `VID_1C5E` device with `Status: OK`.
- **FT Manager** detects and connects to the ECU.

## Reverting

```
bcdedit /set testsigning off
```
then re-enable Secure Boot in the UTM firmware and reboot (do this only after
uninstalling the driver, if you no longer need the device).
