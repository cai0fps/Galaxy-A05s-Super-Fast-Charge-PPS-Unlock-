# Galaxy A05s — Super Fast Charge (USB-PD PPS Unlock)

🌐 **[English Version](README_EN.md)** | **[Versão em Português](README.md)**

> **Author & Developer:** [@cai0fps](https://github.com/cai0fps)  
> **Target Device:** Samsung Galaxy A05s (`SM-A057M` / `SM-A057F` / `SM-A057G`)  
> **Platform:** Qualcomm Snapdragon 680 4G (`SM6225` / `bengal`)  
> **Compatibility:** KernelSU / KernelSU Next / Magisk — Specifically calibrated for Samsung Galaxy A05s OneUI (Kernel 5.15 Bengal SM6225 with matching pd_policy_manager). Kernels with different compilation options require verification of symbols and offsets.  

---

## ⚡ Project Overview

The **Samsung Galaxy A05s** features native high-power hardware with a **2:1 switched-capacitor Charge Pump (Silergy SP2130)** coupled to a USB Type-C PD PHY controller (**Richtek RT1711H**). The hardware natively supports up to 25W charging (Super Fast Charging / USB-PD PPS) when connected to genuine 25W adapters (9V @ 2.77A).

However, in Samsung's OEM firmware, an artificial restriction was enforced in the power policy manager kernel driver (`pd_policy_manager.ko`). When connecting 18W–20W USB-PD PPS chargers or universal power adapters whose APDO declares a maximum current below 2,000 mA (for example, `3.3V–11.0V @ 1.8A`), the kernel rejects the PPS contract and forces a fallback to standard 5V slow charging (1.5A to 2.0A).

This project uses **Linux Kernel Kprobes** to dynamically intercept USB-PD contract evaluation in real time. It enables PPS handshake negotiation, VBUS elevation to ~9.0V, and 2:1 SP2130 Charge Pump closed-loop switching. In Normal and Smart modes, OEM thermal protections and the electrochemical CC/CV charging curves are preserved.

---

## 🔬 Hardware Topology

```
USB-C Connector
       │
       ▼
Richtek RT1711H (TCPC / PD PHY)
       │  (BMC Communication / CC Lines)
       ▼
Qualcomm Bengal SoC / Linux Kernel 5.15
  ├─ tcpc_class.ko
  ├─ rt_pd_manager.ko
  └─ pd_policy_manager.ko ──► [KPROBE HOOK @cai0fps]
       │
       ├──────────────────────────────────────────────┐
       ▼ (PPS High Power 2:1 Mode)                    ▼ (Trickle / CV Mode)
Silergy SP2130 (Charge Pump 2:1)             UPM6918 (Buck Charger)
  η ≈ 97% | Switched Capacitor                 Saturation regulation
       │                                              │
       └──────────────────────┬───────────────────────┘
                              ▼
                   SM5602 Fuel Gauge (BMS)
                              ▼
                 Li-ion Battery (5,000 mAh)
```

---

## 🧠 Reverse Engineering the OEM Clamp

By disassembling `usbpd_pd_contact` within `pd_policy_manager.ko`, the assembly rejection logic was isolated in ARM64:

```arm64
// usbpd_pd_contact (pd_policy_manager.ko)
+0x1f8:  mov    w20, #-1             // Initialize APDO state = not found
+0x1fc:  mov    w24, #0x2710         // Voltage ceiling = 10,000 mV (10V)
...
+0x250:  cmp    w4, #0x7d0           // <--- OEM CLAMP: w4 < 2000 mA?
+0x254:  b.lt   +0x280               // If less than 2,000 mA, DISCARD APDO!
...
+0x2a8:  mov    w2, #0x2328          // Default target voltage = 9000 mV
+0x2ac:  mov    w3, #0x7d0           // Default request current = 2000 mA
+0x2b0:  mov    w20, #1              // Mark APDO as qualified
+0x2b8:  bl     usbpd_pps_enable_charging
```

### Dynamic Kernel Hook Mechanism (`pps_kp_override.ko`):
1. **Pre-Handler 1 (`+0x250`)**:
   * Reads advertised charger current directly from register `regs->regs[4]`.
   * If lower than 2,000 mA, stores the real value in internal control memory (`[kp1 + 0x80]`) and elevates `regs->regs[4]` temporarily to 2,000 to cleanly pass the OEM threshold test.
2. **Pre-Handler 2 (`+0x2b0`)**:
   * Intercepts the USB Request Data Object (RDO) creation.
   * Restores the authentic advertised current into `regs->regs[3]`.
   * The transmitted RDO packet accurately reflects the connected power brick's capabilities, preventing primary-side overcurrent tripping.

---

## 📊 Protocol Decoding: Raw Transmitted RDO

During hardware validation with a 20W wall charger (APDO `3300–11000 mV @ 1800 mA`), the raw Request packet transmitted by the TCPC PHY chip was captured:

```text
< 2423.777>TCPC-PE:NewReq, rdo:0x53038424
[ 2423.805585] rt-pd-manager: pd_tcp_notifier_call sink vbus 9000mV 1800mA
< 2438.119>TCPC-PE-EVT:accept
< 2438.141>TCPC-PE-EVT:ps_rdy
```

### Bit-by-Bit Breakdown of RDO `0x53038424` (USB-PD 3.0 Spec, Table 6-15):

| Field | Bits | Hex / Raw | Physical Value |
|---|---|---|---|
| **Object Position** | [31..28] | `0x5` | **APDO #5 selected** |
| **GiveBack Flag** | [27] | `0` | No power giveback |
| **Capability Mismatch** | [26] | `0` | Device power rules satisfied |
| **USB Comm Capable** | [25] | `1` | USB data link active |
| **No USB Suspend** | [24] | `1` | Charging active during sleep |
| **Output Voltage** | [19..9] | `450` (`0x1C2`) | $450 \times 20\text{ mV} = \mathbf{9,000\text{ mV}}$ |
| **Operating Current** | [6..0] | `36` (`0x24`) | $36 \times 50\text{ mA} = \mathbf{1,800\text{ mA}}$ |

---

## ⚡ Physics of Charging: VBUS vs VBAT Explained

Understanding the power path helps interpret diagnostic measurements accurately:

### 1. Bus Voltage ($V_{bus}$) vs Battery Voltage ($V_{bat}$)
* **VBUS (USB Cable)**: Negotiated PPS voltage typically runs between **~9.0V and 9.7V** inside the cable. This higher voltage allows higher power transfer with less cable current, minimizing resistive heat loss ($P_{\text{loss}} = R \times I^2$).
* **Battery Cell (1S Li-Ion)**: Operates strictly between **~3.4V (0%)** and **~4.40V (100%)**. Voltages above this range cannot be applied directly across the battery cell.

### 2. 2:1 Down-Conversion by the SP2130 Charge Pump
The **Silergy SP2130** acts as a switched-capacitor DC-DC converter with $\approx 97\%$ efficiency:
* **Output Voltage to Battery**: $V_{bat} \approx \frac{V_{bus}}{2}$ (e.g., $\frac{9.0\text{V}}{2} \approx 4.5\text{V}$ before battery saturation)
* **Output Current to Battery**: $I_{bat} \approx 2 \times I_{bus} \times \eta$ (e.g., $1.4\text{A}$ at VBUS converts to $\approx 2.7\text{A} - 2.8\text{A}$ into the cell)

### 3. Power Math & Adapter Limits
* **Input Cable Power ($P_{bus}$)**:
  $$P_{bus} = V_{bus} \times I_{bus}$$
  * On a **20W adapter** offering $9.0\text{V} \times 1.8\text{A}$, the theoretical physical ceiling is **$16.2\text{W}$**.
  * On a genuine **25W adapter** offering $9.0\text{V} \times 2.77\text{A}$, the theoretical physical ceiling is **$25.0\text{W}$**.
  * At $V_{bus} = 9.0\text{V}$ and $I_{bus} = 1.4\text{A}$, the cable power drawn is $\mathbf{12.6\text{W}}$.
* **Net Power Absorbed by the Battery ($P_{bat}$)**:
  $$P_{bat} = V_{bat} \times I_{bat}$$
  * At $V_{bat} = 3.98\text{V}$ and $I_{bat} = 2.78\text{A}$, the chemical storage power is:
    $$3.98\text{V} \times 2.78\text{A} \approx \mathbf{11.06\text{W}}$$
  > [!IMPORTANT]
  > Multiplying cable voltage ($9\text{V}$) by battery current ($2.8\text{A}$) gives a fictitious value ($25.2\text{W}$) that confuses input and output stages of the 2:1 converter.

### 4. Electrochemical CC/CV Profile (Why power drops before 100%)
Lithium-ion cells require a two-stage charge cycle:
1. **CC Stage (Constant Current)**: From 0% to approximately 75%–80%, current remains high while cell voltage rises.
2. **CV Stage (Constant Voltage)**: Once the cell reaches its voltage ceiling (~4.35V–4.45V), current is progressively stepped down to prevent electrode degradation and overvoltage, tapering toward 0A at 100%. **No lithium-ion device can sustain peak charging power up to 100%.**

---

## 🌡️ Thermal Mitigation Architecture

Inside Qualcomm's thermal configuration (`/vendor/etc/thermal-engine.conf`), skin mitigation rules regulate high temperatures:

```text
[BATT_SKIN_MITIGATION]
algo_type monitor
sensor quiet-therm
thresholds     38000  39000  40000  41000  43000
thresholds_clr 36000  38000  39000  40000  41000
actions        battery battery battery battery battery
action_info    5      6      7      8      9
```

* **Skin Temperature (`quiet-therm`)**: Above **43 °C**, the daemon triggers thermal mitigations to prevent chassis overheating.
* **Smart Standby Cooldown**: When the screen is turned off during charging, the module lowers high-performance CPU clocks. Lower background heat keeps the chassis within safe thresholds without early thermal throttling.

---

## 🎮 Installation & Profiles

The module is packaged for **KernelSU**, **KernelSU Next**, and **Magisk**:

### 1. Interactive Volume Key Installer
During flash time:
* **`[VOL -]` = Navigate**: Cycle between profiles (`1 -> 2 -> 3 -> 1...`).
* **`[VOL +]` = CONFIRM**: Select the highlighted profile.
* **Safe Timeout (30s)**: If no keys are pressed, automatically defaults to **Mode 1 (Normal / Safe)**.

#### Operating Profiles:
* **`[>] 1. Normal Mode (Recommended / Safe Default)`**:
  - Unlocks PPS handshakes for chargers advertising $< 2,000\text{ mA}$.
  - Keeps all factory thermal limits and the natural Samsung charge curve active.
* **`[>] 2. Smart Mode`**:
  - Unlocks PPS handshakes with dynamic CPU standby cooldown during screen-off.
  - Safe thermal limits and CC/CV curve preserved.
* **`[>] 3. ULTRA Mode (Experimental / Bench Testing)`**:
  - Relaxes thermal mitigation levels while the battery stays under safe limits ($< 42^\circ\text{C}$).
  - Enforces a safety cutoff: if battery reaches $42^\circ\text{C}$, OEM thermal throttling resumes immediately.

### 2. Native Telemetry Dashboard (`action.sh`)
In KernelSU module list, click **"Action" / "Execute"** to view real-time diagnostics:
```text
==================================================
    GALAXY A05s — PPS TELEMETRY DASHBOARD
                by @cai0fps                       
==================================================

 [+] Active Profile  : Mode ULTRA
 [+] Kernel Driver   : ACTIVE (Universal Kprobe @cai0fps)
 [+] USB Protocol    : SUPER FAST CHARGING (25W PPS ACTIVE)
 [+] Charge Pump     : ON (SP2130 2:1 mode active)
 [+] Battery Level   : 68% (Target: 100%)
 [+] Battery Voltage : 3.98 V
 [+] Real Current    : +2780 mA
 [+] Real Power      : 23.4 W delivered
 [+] Battery Temp    : 36.0 C
 [+] Chassis Temp    : 38.2 C (quiet-therm)
 [+] Thermal Level   : 0 (Full Power)
 [+] Thermal Bypass  : ACTIVE (Throttling disarmed)
 [+] Screen Bypass   : ACTIVE (25W unlocked with screen on)
 [!] Use of this module is at the user's sole risk and responsibility.

==================================================
```

### 3. Integrated WebUI Dashboard (`webroot/`)
For KernelSU Next users, the WebUI provides:
* Real-time power metrics (Watts, Volts, Amperes, Temperatures, Charge Pump state).
* One-tap instant profile switcher (Normal, Smart, ULTRA) with dynamic hardware reload.
* Built-in **"Run System Diagnostic"** button testing I2C bus `0x6d` and USB-C cable quality.
* Automatic English/Portuguese detection + `[🌐 PT / EN]` manual language toggle.

### 4. Native System Notifications
The background daemon dynamically monitors USB-PD negotiations and dispatches an Android notification whenever 25W PPS (9V) mode and the SP2130 Charge Pump are engaged.

---

## 📁 File Structure

```
Galaxy_A05s_SuperFastCharge_v1.6.zip
├── module.prop                  # Module metadata (v1.6 Universal)
├── customize.sh                 # Interactive volume cursor installer (bilingual)
├── service.sh                   # Boot daemon, dynamic config reload, thermal bypass & notifications
├── action.sh                    # KernelSU "Action" telemetry script (bilingual)
├── diag.sh                      # Hardware and cable quality diagnostic tool (bilingual)
├── config.prop                  # Active user profile configuration
├── pps_kp_override.ko           # Signed universal kprobe kernel driver
├── webroot/
│   └── index.html               # WebUI dashboard with diagnostic & Watts calculation
└── META-INF/
    └── com/google/android/
        ├── update-binary        # Installer entrypoint
        └── updater-script       # Magisk/KernelSU instruction script
```

---

## ⚠️ Legal Disclaimer, Terms of Use & User Consent

> ### 🛑 IMPORTANT NOTICE: READ CAREFULLY BEFORE INSTALLATION
> This project is a proof of concept (PoC) involving low-level reverse engineering and kernel modifications on the Qualcomm Snapdragon 680 platform.

### 1. Experimental and Research Nature
* All code, binaries, scripts, and kernel drivers in this repository are provided solely for **educational purposes, technical research, and experimental validation of USB-PD PPS charging protocols**.
* This software is distributed **"AS IS"**, without warranty of any kind, express or implied, including but not limited to fitness for a particular purpose or hardware lifespan preservation.

### 2. Complete Disclaimer of Author Liability (@cai0fps)
* **The developer and author ([@cai0fps](https://github.com/cai0fps)) SHALL NOT BE LIABLE under any circumstances for:**
  1. **Physical or Hardware Damage:** Overheating, short circuit, overvoltage, or irreversible component failure (including Qualcomm PMIC, Richtek RT1711H TCPC, Silergy SP2130 Charge Pump, fuel gauge, display panel, USB-C port, or motherboard).
  2. **Battery Wear:** Accelerated chemical degradation, reduced cycle life, excessive heat, swelling, or lithium-ion cell failure.
  3. **Warranty:** Invalidation or denial of official warranty by Samsung or authorized repair centers resulting from bootloader unlocking, KernelSU/Magisk, or kernel script execution.
  4. **Software & Data:** Partition corruption, personal data loss, bootloops, or operating system instabilities.

### 3. General and Irrevocable User Consent Clause
* **Universal Scope:** Consent and assumption of risk apply to the **module in its entirety and across all operational profiles (Mode 1: Normal, Mode 2: Smart, Mode 3: ULTRA)**.
* **No Reimbursement or Liability:** The author ([@cai0fps](https://github.com/cai0fps)) **DOES NOT bear any liability and will NOT reimburse, repair, or compensate for any damages or problems caused directly or indirectly**.
* **Informed Consent:** By downloading, flashing, or using this module, the user explicitly confirms **full awareness of all electrical, thermal, and operational risks**, providing **irrevocable consent** and assuming **100% of all civil, financial, and technical responsibility**.

---

## 🛡️ Best Practices & Risk Mitigation Guidelines

To protect your device and ensure safe operation:
1. **Certified PPS Chargers Only:** Use original Samsung 25W chargers (`EP-TA800`) or USB-IF certified bricks from reputable manufacturers (Anker, Baseus, Ugreen). Avoid counterfeit adapters with excessive voltage ripple.
2. **Quality 3A USB-C Cables:** Use intact, high-gauge Type-C cables rated for $\ge 3\text{A}$ with healthy Configuration Channel (CC) lines.
3. **Adequate Ventilation:** Never charge the phone under pillows, blankets, or inside backpacks.
4. **Remove Thick Cases:** Heavy protective cases act as thermal insulators; remove them during high-power charging sessions.
5. **Daily Driving:** Mode 2 (Smart) is recommended for daily use, delivering full 25W charging while keeping the chassis cool during standby.
6. **Temperature Monitoring:** If battery temperature exceeds $45^\circ\text{C}$ continuously, unplug the charger and allow the device to cool down.

---

## 👤 Author

Researched and developed by:  
**[@cai0fps](https://github.com/cai0fps)**

---
*Notice: This project was developed strictly for educational and reverse-engineering research purposes on the Linux/Android kernel.*
