# Namco System 11 for MiSTer

FPGA implementation of the [Namco System 11](https://en.wikipedia.org/wiki/Namco_System_11) arcade board for the [MiSTer platform](https://github.com/MiSTer-devel/Main_MiSTer/wiki).

Namco System 11 (1994) is an arcade board built around Sony PlayStation technology: an R3000A-compatible MIPS CPU, a System 11 GPU (CXD8538Q) with 2 MB VRAM, and main RAM — paired with Namco-specific hardware that has no PlayStation equivalent: banked game ROM in place of a CD drive, a Namco C76 (Mitsubishi M37702) MCU handling sound and cabinet I/O, the Namco C352 32-voice PCM sound chip, and per-game KEYCUS protection chips. This core implements all of the above, including the C76 coprocessor and C352 sound.

The core is derived from the excellent [PSX_MiSTer](https://github.com/MiSTer-devel/PSX_MiSTer) core by **Robert Peip (FPGAzumSpass)**, which provides the CPU, GPU, GTE, DMA, and memory subsystem foundation.

## Changes in this release (2026-07-28)

- **PSX-style P1/P2 controller selectors restored.** Each port can independently
  select Digital, Analog, GunCon, neGcon, JogCon, Wheel, Mouse, explicit
  `SNAC Port 1/2`, or Off. Console-only duplicate modes are omitted. SNAC
  auto-detects native digital/analog pads, GunCon (`0x63`), neGcon (`0x23`),
  and JogCon (`0xE3`) on a shared two-port poller.
- **Pocket Racer specialty controls.** USB and SNAC neGcon/JogCon steering now
  reaches the cabinet wheel ADC, USB wheel pedals and native neGcon analog I
  reach the throttle ADC, and the MRA labels Accelerate/View.
- **C76 mailbox write-lane bug fixed — this is the important one.** The shared-RAM
  mailbox between the MIPS and the C76 sound MCU selected its 16-bit halfword from
  address bit 1 alone, but the CPU issues *word-aligned* addresses with byte
  enables for a halfword store. Every high-halfword write therefore landed in the
  **low** halfword of the same word, clobbering it, and odd halfwords were never
  writable at all. Consequences now fixed:
  - **Pocket Racer boots and plays.** The corrupted mailbox descriptor meant its
    command packet was never built, so the game sat forever on a black screen.
  - **One-shot sound effects no longer drop.** The Tekken 2 insert-coin effect —
    and other one-shots that travelled over the same mailbox — now play.
  - C76 command delivery is measurably more reliable across all titles.
- **Light-gun support added (Point Blank 2, Gunbarl).** The System 11 GUN I/F
  register block is implemented for USB mouse/light-gun axes or real GunCon 1
  controllers through either PSX SNAC port. The **Light Gun** OSD page adds an
  optional on-screen crosshair and mouse sensitivity setting.
- **Three more titles now ship:** Pocket Racer, Point Blank 2 and Gunbarl —
  eleven playable titles in total, up from nine.
- **Soul Edge Kick and Guard confirmed working** in play (both inputs are gated on
  the C409 KEYCUS, so other titles are unaffected).
- Pocket Racer's steering also accepts the **D-pad** now, not just an analog
  stick, with auto-centring.

## Supported Games

| Game | Status | Notes |
|------|--------|-------|
| Tekken (World, TE2/VER.C) | **Playable** | Gameplay, sound effects, music, FMV intros and attract mode all work. Three regional alternates provided. |
| Tekken 2 Ver.B (World, TES2/VER.B) | **Playable** | Boots, renders, music and inputs all work. All eight revisions ship (seven as alternates), each boot-tested. |
| Pocket Racer (Japan, PKR1/VER.B) | **Playable** | KEYCUS C432. New this release — plays with music and sound effects. Steering on the analog stick or D-pad, accelerate on Button 1. |
| Point Blank 2 (World, GNB2/VER.A) | **Playable (light gun)** | KEYCUS C443. Aim with a USB mouse or a GunCon 1 through PSX SNAC. Three alternates plus Gunbarl. |
| Gunbarl (Japan, GNB1/VER.A) | **Playable (light gun)** | The Japanese release of Point Blank 2; ships as a Point Blank 2 alternate. |
| Soul Edge Ver. II (SO4/VER.C) | Boots + attract | KEYCUS C409. Kick and Guard confirmed working. |
| Dunk Mania (DM2/VER.C) | Boots + attract | KEYCUS C410; slow first boot (~2 min) |
| Xevious 3D/G (XV32/VER.B) | Boots + attract | KEYCUS C430 |
| Prime Goal EX (PG1/VER.A) | Boots + attract | KEYCUS C411 |
| Dancing Eyes (DC2/VER.B) | Boots + attract | KEYCUS C431 |
| Star Sweep (STP1/VER.A) | Boots + attract | KEYCUS C442 |
| Kosodate Quiz My Angel 3 (KQT1/VER.A) | Boots + attract | KEYCUS C443 + rom8_64 32 MB banking |

Titles listed as "Boots + attract" pass their KEYCUS protection checks and render
their attract sequences on hardware; gameplay depth-testing at the Tekken level
is ongoing. **Family Bowl** remains out of scope — MAME itself marks it as not
working, and it additionally needs a rotated (ROT90) display.

## Contents

```
SYSTEM11-RELEASE-20260728/
├── release/                       ← copy onto your MiSTer SD card
│   └── _Arcade/
│       ├── <one primary .mra per game (11 games)>
│       ├── _alternatives/         ← 24 regional / revision variants
│       │   ├── _Tekken/           ← World VER.B, Asia VER.C, Japan VER.B                    (3)
│       │   ├── _Tekken 2/         ← the other 7 revisions                                   (7)
│       │   ├── _Point Blank 2/    ← US GNB3-VER.A, World VER.A alt, World unknown,
│       │   │                        plus Gunbarl (Japan GNB1-VER.A)                         (4)
│       │   ├── _Soul Edge/        ← World/US/Japan VER.A, Ver. II US VER.C                  (4)
│       │   ├── _Dancing Eyes/     ← US DC3-VER.C, Japan DC1-VER.A                           (2)
│       │   ├── _Xevious 3D-G/     ← World VER.A, Japan XV31-VER.A                           (2)
│       │   ├── _Dunk Mania/       ← Japan DM1-VER.C                                         (1)
│       │   └── _Star Sweep/       ← Japan STP1-VER.A                                        (1)
│       └── cores/
│           └── XNSYSTEM11_20260728.rbf   ← the FPGA core bitstream
└── source/                        ← full corresponding FPGA source (build it yourself)
```

## Installation

1. Copy `release/_Arcade/` to the `_Arcade/` folder on your MiSTer SD card
   (merging with what is already there).
2. Place your own ROM zips in the MiSTer arcade ROM location
   (`games/mame/` or `_Arcade/mame/`).
3. Select a game from the arcade menu.

The `.mra` files reference the core as `XNSYSTEM11`; MiSTer picks the
newest-dated `XNSYSTEM11_*.rbf` in `_Arcade/cores/`.

ROMs are **not** included with this project and are not linked from it — see [Legal](#legal). The MRA files reference MAME romsets by zip name:

| MRA | ROM zips required |
|-----|-------------------|
| Tekken (World TE2 Ver.C).mra | `tekken.zip` + `namcoc76.zip` |
| Tekken (World TE2 Ver.B).mra | `tekkenb.zip` + `tekken.zip` + `namcoc76.zip` |
| Tekken (Asia TE4 Ver.C).mra | `tekkenac.zip` + `tekken.zip` + `namcoc76.zip` |
| Tekken (Japan TE1 Ver.B).mra | `tekkenjb.zip` + `tekken.zip` + `namcoc76.zip` |
| Tekken 2 Ver.B (World TES2-VER.B).mra | `tekken2b.zip` (or merged `tekken2.zip`) + `namcoc76.zip` |
| Tekken 2 alternates (7 MRAs) | revision zip (`tekken2a/ua/ub/ud/jb/jc`) or merged `tekken2.zip`, + `namcoc76.zip` |
| Soul Edge Ver. II (SO4-VER.C).mra | `souledge.zip` + `namcoc76.zip` |
| Dunk Mania (DM2-VER.C).mra | `dunkmnia.zip` + `namcoc76.zip` |
| Xevious 3D-G (XV32-VER.B).mra | `xevi3dg.zip` + `namcoc76.zip` |
| Prime Goal EX (PG1-VER.A).mra | `primglex.zip` + `namcoc76.zip` |
| Dancing Eyes (DC2-VER.B).mra | `danceyes.zip` + `namcoc76.zip` |
| Star Sweep (STP1-VER.A).mra | `starswep.zip` + `namcoc76.zip` |
| Kosodate Quiz My Angel 3 (KQT1-VER.A).mra | `myangel3.zip` + `namcoc76.zip` |

`namcoc76.zip` (the Namco C76 sound-CPU BIOS) is required by **every** MRA — it is
loaded into the core at runtime and is not embedded in the bitstream.

The regional Tekken alternates and Tekken 2 declare their zip as a fallback list
(e.g. `tekkenb.zip|tekken.zip`): the loader checks the clone zip first and falls back
to the parent. Split/merged clone sets contain only the ROMs that differ from the
parent, so keep the parent zip alongside the clone unless you have non-merged sets.

Launch a game by selecting its MRA entry from the Arcade menu; the MRA loads the game program, banked data ROM, C76 sound program, and C352 wave ROM automatically.

## Controls

Tekken uses an 8-way joystick and four buttons per player, plus Start and Coin:

| Core button | Tekken function | Default pad mapping |
|-------------|-----------------|---------------------|
| Button 1 | Left Punch | A |
| Button 2 | Right Punch | B |
| Button 3 | Left Kick | X |
| Button 4 | Right Kick | Y |
| Buttons 5/6 | Unused by Tekken | L / R |
| Start | Start | Start |
| Coin | Insert coin | Select |
| Pause | Pause the core | L3 |

Two players are supported. The cabinet TEST and SERVICE switches are available as OSD toggles (see below), so the operator test menu can be reached without dedicated buttons.

**Light-gun titles (Point Blank 2, Gunbarl).** Select the source under
**OSD → Controllers → P1/P2 Input**. Choose `Mouse` for the merged USB mouse
stream, `GunCon` for USB absolute axes, or `SNAC Port 1/2` for a
native GunCon. Its trigger fires, A is Start, and B inserts Coin. Native GunCon
aiming requires a compatible 15 kHz CRT/direct-video path; HDMI/LCD output alone
cannot provide optical aiming. Both SNAC ports are supported.

The real cabinet draws no crosshair, so the core's crosshair is an optional aid,
off by default. Adjust *Gun Sensitivity* to suit your mouse's DPI; that setting
does not affect SNAC.

**Pocket Racer.** Digital mode uses the auto-centring D-pad; Analog mode uses
the left stick. USB `neGcon` and `Wheel` use paddle or left-X steering;
`JogCon` also accepts a relative spinner. All three accept analog pedal input.
Button 1 forces full acceleration and Button 2 changes view.
`SNAC Port 1` auto-detects native neGcon/JogCon input. JogCon force feedback is
not implemented. The game has no Start button — insert a coin and it begins.

## OSD Options

- **DIP Switches**
  - `DIP1 Test` — board test DIP
  - `DIP2 Freeze` — board freeze DIP
- **Controllers**
  - `P1 Input` / `P2 Input` — Digital, Analog, GunCon, neGcon, JogCon,
    Wheel, Mouse, SNAC Port 1/2, or Off
  - Explicit controller names select USB mappings; `SNAC Port 1/2` polls and
    auto-detects the physical controller
- **Debug**
  - `FPS Counter` — on-screen frame rate display
  - `Boot Debug Overlay` — diagnostic overlay during boot (off by default)
  - `Test Mode` — asserts the cabinet TEST switch (enters the operator test menu)
  - `Service Mode` — asserts the cabinet SERVICE switch (service credit)
- **Light Gun** (Point Blank 2 / Gunbarl)
  - `Crosshair` — draw an on-screen crosshair (default **Off**; the real cabinet
    draws none, and it is unwanted if you use a real light gun)
  - `Gun Sensitivity` — mouse-to-wheel divisor: 1/4 (default), 1/8, 1/2, 1/1
- **Reset** — resets the board

Opening the OSD pauses the core. Video scaling/aspect options are currently handled by the MiSTer framework defaults; the core-specific video/audio option page is disabled in this release.

## Known Issues

- **Sound fidelity**: the C76/C352 sound engine plays correctly, but is still being
  tuned against real hardware. Feedback is welcome.
- **Long-session display blank (rare).** During soak testing a build has been seen
  to blank its video output for ~46 minutes while the game itself kept running
  (sound and inputs alive, OSD working), then recover on its own. The root cause
  is **not established** — an earlier cross-clock-margin explanation was
  investigated and retracted as unproven — so this is disclosed rather than
  claimed fixed.
- **Timing closure.** The bitstream does not fully meet static timing analysis
  (negative setup slack on the HDMI PLL clock and, marginally, on one core clock
  output). No functional failure has been traced to it, and it is not the cause of
  the blank above, but it is a real defect and is being worked on.
- **JogCon motor feedback is not implemented.** Native and USB JogCon steering
  and buttons are accepted, but System 11 wheel-force output is not yet emulated.
- All nine System 11 KEYCUS chips (C406, C409, C410, C411, C430, C431, C432, C442,
  C443) are implemented and hardware-verified. GPU type is selected per game
  (Tekken 1 = CXD8538Q/coh100; every other title = CXD8561Q/coh110, per MAME).
- **This core targets System 11 hardware only.** PlayStation console features inherited
  from the PSX_MiSTer base that System 11 does not use — memory cards, the SPU and the
  CD-ROM drive — are removed or stubbed to reclaim FPGA logic. The PSX controller port
  (SIO0) is a minimal register stub: several titles run stock PSX pad init at boot and
  need the port's registers to answer (as they do inside the CXD8530 on real boards),
  but no in-game PlayStation controller protocol is implemented. The separate SNAC
  poller translates physical controllers directly into the C76 cabinet inputs.

## Hardware Requirements

A MiSTer with an **SDRAM module (64 MB minimum)** is required (up from 32 MB in the previous release). The core keeps the game program, banked data ROM (up to 32 MB with rom8_64 banking), C76 sound program, and C352 wave ROM (up to 4 MB) in SDRAM, with the load map extending to roughly 45 MB.

## Credits

- **Robert Peip (FPGAzumSpass)** — [PSX_MiSTer](https://github.com/MiSTer-devel/PSX_MiSTer), the PlayStation core this project is built on. The CPU, GPU, GTE, and memory architecture are his work.
- **[MiSTer-devel](https://github.com/MiSTer-devel)** — the MiSTer framework, HPS I/O, and video pipeline.
- **[MAME](https://www.mamedev.org/)** project — the System 11 driver and device documentation used as the reference for the Namco-specific hardware (C76, C352, KEYCUS, ROM banking).
- **The MAME project** (smf et al.) — the Namco System 11 KEYCUS protection algorithms (C406, C409, …) reverse-engineered and documented in `ns11prot.cpp` (BSD-3-Clause); the KEYCUS logic in `s11_io.vhd` is an independent VHDL re-implementation of those documented algorithms.

## License

This core is a combined/derived work licensed under the **GNU General Public License, version 3 or later (GPLv3-or-later)**.

It builds on [PSX_MiSTer](https://github.com/MiSTer-devel/PSX_MiSTer) (Robert Peip) and the MiSTer framework. Several files in the build tree — the MiSTer `sys/` HPS-I/O, SD-card, scandoubler and DDR-service modules, and the SDRAM/DDR memory controllers — are licensed **GPL version 3 or later**. Combining GPLv2-or-later code with GPLv3-or-later code yields a work that can only be conveyed under GPLv3-or-later, so that is the license of this core as a whole. The full texts of both licenses are included (`COPYING.GPL2`, `COPYING.GPL3`); GPLv2-or-later files remain individually available under their own terms.

## Legal

**No ROMs.** This repository contains no game ROMs and no copyrighted game data, and it provides no links or instructions for obtaining them. To use this core you must supply your own ROM dumps, made from original hardware or media that you legally own, where and to the extent your local law permits.

**Trademarks.** "Namco", "System 11", "Tekken", and related names and logos are trademarks or registered trademarks of Bandai Namco Entertainment Inc. and/or their respective owners. "PlayStation" is a trademark of Sony Interactive Entertainment Inc. This project is not affiliated with, endorsed by, or sponsored by Bandai Namco, Sony Interactive Entertainment, or any other rights holder. Such names are used here in a purely nominative and descriptive manner, solely to identify the hardware being re-implemented.

**Purpose.** This is an independent, non-commercial hardware-preservation and interoperability project. The FPGA logic is an original re-implementation of the System 11 board's behavior, developed from observation and from publicly available documentation and references (including the MAME project's hardware documentation); it contains no proprietary source code from the original manufacturers.

**Security-chip emulation.** Namco System 11 boards used per-game KEYCUS chips (C406, C409, …) as a protection measure. This core re-implements that logic for interoperability and preservation, in the same manner as MAME and comparable FPGA cores. The KEYCUS is a small challenge/response algorithm rather than stored key data, so no manufacturer key material is embedded in the bitstream. Laws such as the U.S. DMCA §1201 address circumvention of technological protection measures; whether and how they apply to this kind of preservation/interoperability use can depend on your jurisdiction and circumstances. Users are responsible for their own compliance.

**User responsibility.** Users are solely responsible for ensuring that their use of this core — including the acquisition and use of any ROM images — complies with copyright law and all other applicable laws in their jurisdiction.

**No warranty.** As set out in sections 15–16 of the GNU General Public License (v3) and the equivalent clauses of v2: THIS PROGRAM IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE PROGRAM IS WITH YOU. IN NO EVENT WILL ANY COPYRIGHT HOLDER OR CONTRIBUTOR BE LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE THIS PROGRAM, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.
