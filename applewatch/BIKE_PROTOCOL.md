# Renpho AI Smart Bike — Bluetooth protocol notes

How the Renpho "AI Gym" app (Android `com.renpho.aigym` 1.9.07) talks to the bike,
worked out from the app for interoperability with the owner's own bike. The app is built
on the bike maker's ("Mage Fitness", model code MG03) Bluetooth kit and does **not** use
the standard Fitness Machine Service — it uses the private service below.
**Not yet verified against the real bike.**

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
