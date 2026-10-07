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

## 🧠 Analysis of APDO < 2,000 mA Rejection Condition

By disassembling the `usbpd_pd_contact` routine within Samsung's stock `pd_policy_manager.ko` vendor driver, the instruction responsible for filtering low-current contracts was identified:

```arm64
// usbpd_pd_contact (pd_policy_manager.ko - reference build)
+0x1f8:  mov    w20, #-1             // Initialize APDO state = not found
+0x1fc:  mov    w24, #0x2710         // Voltage ceiling = 10,000 mV (10V)
...
+0x250:  cmp    w4, #0x7d0           // <--- OEM gatekeeper: w4 < 2000 mA?
+0x254:  b.lt   +0x280               // If less than 2,000 mA, DISCARD APDO!
...
+0x2a8:  mov    w2, #0x2328          // Default target voltage = 9000 mV
+0x2ac:  mov    w3, #0x7d0           // Default request current = 2000 mA
+0x2b0:  mov    w20, #1              // Mark APDO as qualified
+0x2b8:  bl     usbpd_pps_enable_charging
```

### Dynamic Kernel Hook Mechanism (`pps_kp_override.ko`):
1. **Pre-Handler 1 (`+0x250`)**:
   * Reads the charger's advertised current from `regs->regs[4]`.
   * If lower than 2,000 mA (such as 18W–20W chargers advertising 1,800 mA), stores the advertised current and temporarily replaces `regs->regs[4]` with 2,000 mA to pass verification without discarding the APDO.
2. **Pre-Handler 2 (`+0x2b0`)**:
   * Intercepts the Request Data Object (RDO) creation.
   * Restores the charger's authentic advertised current into `regs->regs[3]`.
   * This ensures the device never requests more current than the power supply is rated to deliver.

> [!WARNING]
> **Scope & ABI Dependency:**
> - The condition at `+0x250` specifically addresses the **rejection of chargers advertising $< 2,000\text{ mA}$** (such as 18W–20W units at 1.8A). Genuine 25W chargers advertising $\ge 2,000\text{ mA}$ (e.g., 2.25A or 2.77A) are not discarded by this instruction. Therefore, this hook resolves compatibility for lower-current PPS chargers rather than acting as a universal 25W override.
> - The offsets `+0x250` and `+0x2b0`, as well as registers $x3$/$x4$, are compiled specifically for Samsung's reference kernel build. Security patches or alternative kernels may shift addresses or alter register allocation.

---

## 📊 Protocol Decoding: Raw Transmitted RDO

During hardware testing with a 20W charger (APDO `3300–11000 mV @ 1800 mA`), the raw Request Data Object transmitted by the TCPC PHY was captured:

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

> [!NOTE]
> **Contract Interpretation:** RDO `0x53038424` confirms that the device successfully negotiated a PPS contract of **$9.0\text{ V} @ 1.8\text{ A}$ ($16.2\text{ W}$ maximum at VBUS)**. It proves that the PPS handshake succeeded on a charger that was previously relegated to 5V slow charging. However, **it does not demonstrate 25W**, as the test adapter is physically capped at 16.2W. Higher charging power requires an adapter with a corresponding APDO (e.g., 9V @ 2.25A = 20.25W; 9V @ 2.77A = 25W).

---

## ⚡ Power Flow Architecture: VBUS, Charge Pump, and Battery

Accurate interpretation requires distinguishing the different stages of the charging circuit:

```
[ Charger ] ──(VBUS: ~9.0V / Ibus)──► [ SP2130 Charge Pump 2:1 ] ──(VBAT: ~4.0V / Ibat)──► [ Battery Cell ]
  P_contract = V_apdo × I_apdo            η ≈ 97%                                           P_bat = V_bat × I_bat
  (Physical ceiling)                     I_bat ≈ 2 × I_bus × η                             (Net chemical storage)
```

### 1. Contract Ceiling vs Input Power ($P_{bus}$)
* **Contract Ceiling ($P_{\text{contract}}$)**: Determined by the active APDO.
  * 20W Charger (APDO 9V @ 1.8A): Physical ceiling of **$16.2\text{ W}$**.
  * 25W Charger (APDO 9V @ 2.77A): Physical ceiling of **$25.0\text{ W}$**.
* **Measured Input Power ($P_{bus} = V_{bus} \times I_{bus}$)**:
  * Operating at an intermediate charging state with the 9V @ 1.8A contract active, bus current registered $I_{bus} \approx 1.39\text{ A}$.
  * Input cable power: $9.0\text{ V} \times 1.39\text{ A} \approx \mathbf{12.5\text{ W}}$.

### 2. 2:1 Down-Conversion by the SP2130 Charge Pump
The **Silergy SP2130** operates as a switched-capacitor converter with $\approx 97\%$ efficiency:
* Halves voltage: $V_{cp\_out} \approx \frac{V_{bus}}{2} \approx 4.5\text{ V}$ (clamped by battery impedance).
* Doubles current: $I_{bat} \approx 2 \times I_{bus} \times \eta \approx 2 \times 1.39\text{ A} \times 0.97 \approx \mathbf{2.7\text{ A} - 2.8\text{ A}}$.

### 3. Net Power Absorbed by the Battery ($P_{bat}$)
* A 1S Lithium-ion cell operates between $3.4\text{ V}$ and $4.45\text{ V}$.
* Simultaneous Fuel Gauge (SM5602) reading: $V_{bat} = 3.98\text{ V}$ and $I_{bat} = +2.78\text{ A}$.
* Net chemical power stored:
  $$P_{bat} = 3.98\text{ V} \times 2.78\text{ A} \approx \mathbf{11.06\text{ W}}$$
* **Energy Balance:**
  * Cable Input ($P_{bus}$): $\approx 12.5\text{ W}$
  * Cell Delivery ($P_{bat}$): $\approx 11.1\text{ W}$
  * System efficiency: $\frac{11.1\text{ W}}{12.5\text{ W}} \approx 88.8\%$ (accounting for USB connector resistance, charge pump switching losses, and active phone system power).

### 4. Electrochemical CC/CV Profile (Why power drops before 100%)
Lithium-ion cells require a two-stage charge cycle:
1. **CC Stage (Constant Current)**: From 0% to approximately 75%–80%, current remains high while cell voltage rises.
2. **CV Stage (Constant Voltage)**: Once the cell reaches its voltage ceiling (~4.35V–4.45V), current is progressively stepped down to prevent electrode degradation and overvoltage, tapering toward 0A at 100%. **No lithium-ion device can sustain peak charging power up to 100%.**

---

## 🌡️ Thermal Mitigation Architecture

Qualcomm's thermal engine configuration (`/vendor/etc/thermal-engine.conf`) defines skin mitigation rules:

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

 [+] Active Profile  : Mode NORMAL
 [+] Kernel Driver   : ACTIVE (Kprobe @cai0fps)
 [+] USB Protocol    : SUPER FAST CHARGING (PPS ACTIVE)
 [+] Charge Pump     : ON (SP2130 2:1 mode active)
 [+] Battery Level   : 68%
 [+] Cell Voltage    : 3.98 V (1S Battery Max 4.45V)
 [+] Battery Current : +2780 mA
 [+] Battery Power   : +11.1 W (net cell power)
 [+] Cable Input     : ~12.5 W (VBUS Input 9V PPS)
 [+] Cable Voltage   : ~9.0 V (USB-C PPS)
 [+] Cable Current   : ~1390 mA (÷2 by SP2130)
 [+] Battery Temp    : 36.0 C
 [+] Chassis Temp    : 38.2 C (quiet-therm)
 [+] Thermal Level   : 0 (Normal)
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

## 📁 Repository & File Structure

The repository maintains the complete module files directly at the root (standard for Magisk / KernelSU modules to ensure raw GitHub URLs never return 404) while also maintaining `module_package/` for zip packing:

```
Galaxy-A05s-Super-Fast-Charge-PPS-Unlock-
├── module.prop                  # Module metadata (v1.7)
├── service.sh                   # Boot daemon, dynamic thermal detection & cooldown
├── action.sh                    # KernelSU "Action" telemetry script (VBUS/VBAT)
├── customize.sh                 # Interactive volume cursor installer
├── diag.sh                      # Hardware and cable quality diagnostic tool
├── config.prop                  # Active user profile configuration
├── pps_kp_override.ko           # LKM kernel driver with kprobes (calibrated for Kernel 5.15 Bengal SM6225)
├── package_module.py            # Automated zip packager and permission verifier
├── Galaxy_A05s_SuperFastCharge_v1.7.zip # Generated flashable module package
├── webroot/
│   └── index.html               # Clean monochrome (Black/White) WebUI dashboard
├── META-INF/
│   └── com/google/android/
│       ├── update-binary        # Installer entrypoint
│       └── updater-script       # Magisk/KernelSU instruction script
└── module_package/              # Mirrored tree for flashable packaging
```

---

## 🗺️ Architectural Roadmap & Next Steps (Source Capabilities → PDO/APDO → RDO → VBUS/IBUS)

The current release (v1.7) targets the specific $I < 2,000\text{ mA}$ restriction within Samsung's reference `pd_policy_manager.ko` (Kernel 5.15 Bengal). To evolve into an extensible universal charging framework, the following architectural milestones are defined:

1. **Dynamic Instruction Pattern Scanning**:
   * Replace fixed opcode offsets (`+0x250`, `+0x2b0`) with an in-memory AArch64 instruction pattern scanner at load time (`insmod`).
   * Verify the exact comparison instruction prior to arming the kprobes, aborting safely if a mismatched kernel build is detected.

2. **Full `Source_Capabilities` Decoding**:
   * Intercept raw capability packets exchanged over the BMC configuration channel of the **Richtek RT1711H** TCPC PHY.
   * Parse all advertised **Fixed Supply PDOs** (5V, 9V, 12V, 15V, 20V) and **Augmented PDOs (PPS)** (ranges `3.3V–5.9V`, `3.3V–11.0V`, `3.3V–16.0V`, `3.3V–21.0V`).

3. **Dynamic RDO Synthesis**:
   * Replace the fixed 9,000 mV request with dynamic voltage optimization bounded by $[V_{\min}, V_{\max}]$ advertised by the selected APDO.
   * Strictly enforce the maximum current advertised by the source to prevent overcurrent protection (OCP) tripping.

4. **Direct Physical Telemetry (True VBUS & IBUS Sensing)**:
   * Interface directly with RT1711H TCPC sysfs nodes (`/sys/class/typec/...`).
   * Clearly segregate electrical domains on the dashboard:
     - **Input Power**: $P_{bus} = V_{bus} \times I_{bus}$
     - **Delivered Chemical Power**: $P_{bat} = V_{bat} \times I_{bat}$
     - **Real SP2130 Conversion Efficiency**: $\eta = \frac{P_{bat}}{P_{bus}}$

5. **Proprietary Fast-Charging Protocol Expansion**:
   * Extend the negotiation engine to support **Samsung Adaptive Fast Charging (AFC 9V)**, **Qualcomm Quick Charge (QC 2.0/3.0)**, and Fixed USB-PD profiles for non-PPS chargers.

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
* **Mode 3 (ULTRA / High Power):** Mode 3 dynamically scans battery thermal cooling devices (`/sys/class/thermal/cooling_device*`) to relax mitigations only while temperature remains safe ($< 38^\circ\text{C}$). If temperature reaches $40^\circ\text{C}$, the module automatically yields control back to kernel thermal policies.

---

## 🛡️ Best Practices & Risk Mitigation Guidelines

To protect your device and ensure safe operation:
1. **Certified PPS Chargers Only:** Use original Samsung 25W chargers (`EP-TA800`) or USB-IF certified bricks from reputable manufacturers (Anker, Baseus, Ugreen). Avoid counterfeit adapters with excessive voltage ripple.
2. **Quality 3A USB-C Cables:** Use intact, high-gauge Type-C cables rated for $\ge 3\text{A}$ with healthy Configuration Channel (CC) lines.
3. **Adequate Ventilation:** Never charge the phone under pillows, blankets, or inside backpacks.
4. **Remove Thick Cases:** Heavy protective cases act as thermal insulators; remove them during high-power charging sessions.
5. **Daily Driving:** Mode 2 (Smart) is recommended for daily use, negotiating maximum charger power while keeping the chassis cool during standby.
6. **Temperature Monitoring:** If battery temperature exceeds $45^\circ\text{C}$ continuously, unplug the charger and allow the device to cool down.

---

## 👤 Author

Researched and developed by:  
**[@cai0fps](https://github.com/cai0fps)**

---
*Notice: This project was developed strictly for educational and reverse-engineering research purposes on the Linux/Android kernel.*
