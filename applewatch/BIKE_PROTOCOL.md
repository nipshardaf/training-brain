# Renpho AI Smart Bike — Bluetooth protocol notes

How the Renpho "AI Gym" app (Android `com.renpho.aigym` 1.9.07) talks to the bike,
worked out from the app for interoperability with the owner's own bike. The app is built
on the bike maker's ("Mage Fitness", model code MG03) Bluetooth kit and does **not** use
the standard Fitness Machine Service — it uses the private service below.
**Verified on the real bike (Training Brain v3.50+).**

## Services
| | UUID |
|---|---|
| Bike service (MG03) | `00000001-21a4-11e8-8812-000c2920efff` |
| Bike service (MGE03 variant) | `00000001-8210-4578-82f1-0b2fc1e5c7fb` |
| Data characteristic (notify + write) | `00000004-` + same suffix as the service |
| `00000002-…`, `00000003-…` | firmware update (OTA) — never write to these |

Model names seen in the app: `R-Q002`, `R-Q002 N`. Scan by service UUID.

## Framing
One message = `cmd` `sub` `payload…` `crcHi` `crcLo`, then SLIP-encoded:
- CRC = CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF) over `cmd sub payload`, big-endian.
- SLIP: `C0` → `DB DC`, `DB` → `DB DD`; every message ends with `C0`.
- Incoming notifications are ≤ 20 bytes, so a message can span several: buffer until `C0`,
  drop empty chunks, un-escape, check the CRC.
- All multi-byte numbers are big-endian. Writes are "without response".

## App → bike
| cmd sub | payload | meaning |
|---|---|---|
| `00 40` | `00 01` / `00 02` / `00 03` / `00 04` / `00 05` / `00 00` | Prepare / Start / Pause / Resume / Stop / Cancel |
| `00 44` | 1 byte = torque × 2 (2…80; `00` = reset) | set resistance torque, 1.0–40.0 N·m in 0.5 steps (the "80 levels") |
| `00 45` | `01` / `00` | "deposit": app controls resistance / knob controls it |
| `00 46` | `00` / `01` | bike display shows torque / gear ratio |
| `00 22` | – | ask for component serial numbers |
| `01 31` | – | acknowledge the bike's request to disconnect |

AI Gym's ride start: `00 46 00`, `00 45 01` (when the app drives resistance), then `00 40 00 02`.
ERG (hold a target power): torque = power × 9.56 ÷ cadence (cadence clamped 40–170,
torque capped at 40), re-sent as cadence changes.

## Bike → app
| cmd sub | payload | meaning |
|---|---|---|
| `00 50` | live data, see below | sent continuously while riding |
| `00 52` | 1 signed byte | resistance knob turned by N clicks |
| `00 41` | `01 01` / `01 02` / `02 01` | knob pressed / released / long press |
| `00 47` | – | braking |
| `00 31` | – | bike wants to disconnect (reply `01 31`) |
| `01 27` | type, voltage, temperature, supply mode | device and battery status |
| `01 22` | serial numbers | reply to `00 22` |
| `01 A1` | `01` ok / `00` error | handshake result (the app never sends a handshake) |

### Live data (`00 50`), payload offsets
| offset | size | value |
|---|---|---|
| 0 | 2 | cadence, rpm |
| 2 | 2 | speed ÷ 1000 (m/s) |
| 4 | 2 | power ÷ 10 (W) |
| 6 | 4 | distance |
| 10 | 2 | status |
| 12 | 1 | gear |
| 13 | 1 | torque × 0.5 (N·m) |
| 14 | 1 | heart rate (from a strap paired to the bike; 0 if none) |
| 15 | 4 | calories ÷ 1000 |
| 19 | 2 | motor-controller status (23-byte payloads) |
| 21 | 2 | motor-controller temperature ÷ 10 (23-byte payloads) |

The app discards samples outside: speed 0–200, power 0–1000 W, torque 0–50, heart rate 0–300.

## How AI Gym drives the bike (full review, 2026-10-04)
Checked against the decompiled app before its emulator was removed. Our protocol use has been
confirmed on the real bike since Training Brain v3.50.

### Ride modes in AI Gym
| Mode | What it does with the bike |
|---|---|
| ERG courses | Every live-data sample: torque = target W × 9.56 ÷ cadence, sent at once (no smoothing). Course segments come from the server. |
| Video courses (Les Mills, licensed) | Same, with segment torque / cadence range / stand cues. Content is licensed — not reproducible. |
| Target ride | Free ride toward a time / distance / calorie goal; resistance from the knob. |
| Map routes / video routes | Display switches to gears (`00 46 01`), app takes control (`00 45 01`) and sets torque from road physics (below). Knob clicks (`00 52`) change the virtual gear. |
| FTP test | Ramp test (below). |
Model `R-Q002 N` only: the app sends zero torque (`00 44 00`) when a ride starts.

### Course segments (server "script points")
start/end time, `intensity` (% of FTP), `torque`, `rpm` / `rpm_min` / `rpm_max`, `stand` (stand-up cue),
`zone`, `position`, plus audio/tips text. Cadence is "on target" when inside rpm_min…rpm_max.

### Road physics (map routes)
torque (N·m) = m·g·(sin θ + cos θ·Crr) × wheel radius × front/rear teeth, with m = rider mass (75 kg
default), Crr 0.015, wheel radius 0.30 m, gears 30/20, θ = atan(slope % / 100), air drag ignored for
torque; clamped 1–40. Example: 111 kg rider, 5 % grade ≈ 32 N·m. Virtual speed uses the same model plus
CdA 0.1548 (solved each sample).

### FTP and zones
- No test yet → FTP 100 W (men) / 70 W (women).
- FTP test = ramp: each step targets base FTP × step intensity %; more than 20 W under target for
  15 s ends it; FTP = 0.75 × (last full step + fraction of current step × the step's increase).
- Power zones (% FTP): 0 / 56 / 76 / 91 / 106 / 121. Heart-rate zone tables: 61/71/81/91/101 and
  51/61/71/81/91 (% of max HR).
- FTP levels (W): men 101 / 134 / 167 / 200, women 71 / 104 / 137 / 170 → Beginner, Junior, Senior,
  Superior, Professional.

### Not used by Training Brain
Firmware update (OTA) characteristics, account/family features, Health Connect / Samsung / Huawei
sync, cloud course downloads.
