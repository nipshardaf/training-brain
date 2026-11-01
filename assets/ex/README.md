# Exercise pictures to make (job for the PC chat)

These exercises have no photo in free-exercise-db, so the app shows a coloured placeholder
(`p:null` in `EX` in `index.html`). Make one picture each with the `chatgpt-image-gen` skill
(ChatGPT in the user's Chrome), show them to the user, and add the ones they approve.

## Style (keep it the same for all of them)
- One adult in plain gym clothes doing the exercise, side or three-quarter view, the machine
  or kit clearly visible, the working muscle easy to read.
- Clean flat illustration, light neutral background, no text, no logos or brand names.
- Landscape, saved as `assets/ex/<id>.webp`, about 900 × 500 (the card is wide), under 120 KB.
- Optional second frame for the "Animate" toggle: `assets/ex/<id>-2.webp` (end of the movement).

## Wiring an approved picture
In `EX`, change the entry's `p:null` to `p:['assets/ex/<id>.webp']`, or
`p:['assets/ex/<id>.webp','assets/ex/<id>-2.webp']` with a second frame. Arrays are direct
image URLs, so nothing else is needed (sw.js caches same-origin files). Then follow the
publish flow in CLAUDE.md.

## The list (id: what to show)
- `mach_hip_thrust`: hip thrust machine, upper back on the pad, belt over the hips, hips up
- `smith_hip_thrust`: Smith machine bar over the hips with a pad, upper back on a bench
- `pendulum_squat`: pendulum squat machine, back on the pad, deep squat
- `belt_squat`: belt squat machine, belt around the hips, hands on the rails
- `v_squat`: V-squat (power squat) machine, shoulders under the pads
- `seated_leg_press`: horizontal seated leg press (pin-loaded), back flat on the seat
- `sl_leg_press`: 45° leg press with one foot on the platform
- `glute_kick_mach`: glute kickback machine, chest on the pad, one foot pushing the plate back
- `landmine_press`: half-kneeling single-arm landmine press
- `cable_upright_row`: rope or bar upright row on a low pulley
- `cable_y_raise`: two low pulleys crossed, arms raised into a Y
- `bayesian_curl`: facing away from a low pulley, arm behind the body, curling
- `iso_pulldown`: plate-loaded iso-lateral front pulldown, thighs under the pad
- `mach_pullover`: pullover machine, elbows on the pads
- `back_ext_mach`: seated back extension machine, pad across the upper back
- `rotary_torso`: rotary torso machine, seated, turning the upper body
- `wall_sit`: wall sit, thighs level
- `short_foot`: barefoot "short foot", the arch lifted
- `towel_scrunch`: barefoot, toes scrunching a towel
- `arch_raise`: barefoot standing arch raise
- `toe_spread`: barefoot, toes spread wide
- `heel_raise`: barefoot heel raise, arch lifted
