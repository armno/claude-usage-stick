# T-Display S3 case — print & assembly

Two-shell wedge desk stand. Source: `case.scad`
(`mode = "assembly" | "front" | "back" | ...`). Exported STLs live in
`case/stl/`.

## Files

| File | `mode` | Notes |
|---|---|---|
| `stl/front.stl` | `front` | Print this first — it doubles as the test-fit coupon (checklist below). Direct-press button openings |
| `stl/back.stl` | `back` | Wedge body + battery bay — print once the front passes the checklist |

Re-export any of these with:
```bash
TOOLS=~/.claude/skills/openscad/tools
$TOOLS/export-stl.sh case/case.scad case/stl/<name>.stl -D 'mode="<mode>"' [-D 'param=value' ...]
```

## Print settings

- PLA, 0.2mm layers, **3 perimeters** (the 2mm walls and the narrow struts
  around the button/USB openings rely on perimeter strength — don't drop
  this to save time).
- No supports needed on any part. Caveat: `back.stl`'s top-wall ceiling is a
  ~15mm-span flat PLA bridge over the cavity — printable at 0.2mm layers with
  part cooling on, but expect the first bridged layer to sag slightly / look
  rough. No support needed, just keep the fan running.
- Orientation:
  - `front.stl` — **bezel face down**. The STL is already rotated so the
    bezel is flat on Z=0; load as-is, don't rotate in the slicer.
  - `back.stl` — **base down** (already sits base-down in the export).

## Test-fit: print `front.stl` first — it IS the coupon

> **Before assembly (one-time):** clip the soldered pin headers' pins flush
> with their plastic strips — both rows, flush cutters, eye protection (clipped
> pins fly). The case is modeled around the leftover plastic strips (~2.5mm +
> stub); intact ~9mm pins do NOT fit. Wear safety glasses and clip close to
> the plastic, not mid-pin. The two hooks on the back shell assume the header
> strips are ≤34mm long and roughly centered on the long edges (the normal
> 2×12 layout) — eyeball yours against that before printing `back.stl`.

The front shell is thin (9.9mm deep, ~30-45 min at 0.2mm layers) and
contains every fit-critical feature, so there's no separate coupon part:
print `front.stl` alone first and test it. Print `back.stl` only once the
front passes. Board dimensions were caliper-measured 2026-07-03 (±0.5mm,
see `dimensions.md`). Check, **in this order**:

1. **USB cable fit** — does your USB cable's plug *boot* (not just the bare
   connector) fit through the 12mm slot (`usb_slot_w`)? The boot itself
   wasn't measured — this print verifies it. **Ceiling:** at the measured
   `btn_spacing` 18.5 the slot can widen to ≈13.9mm before it merges with
   the button openings; past that, use a slim or right-angle cable.
2. **Board drop-in fit** — does the board drop into the pocket cleanly,
   resting on the two end ledges? If too tight/loose, adjust `board_fit`
   (default 0.25mm clearance).
3. **Window position** — the window is cut 0.55mm inside the *measured glass
   outline* (46 × 25), so the bezel lips over the glass border and the lit
   area sits well inside. Power the board on (USB in, board seated) and
   check: full lit area visible, bezel overlapping only the black glass
   border. If the bezel shadows pixels anywhere, reduce `win_inset` or
   correct `act_off_grove` / `act_off_bot` and re-export.
4. **Button actuation** — the side switch caps project ~2mm past the PCB
   edge, i.e. nearly through the 2mm wall, so each button opening is a
   direct-press cutout the cap pokes into: you press the switch **itself**.
   Check both caps sit centered in their openings and actuate freely; if a
   cap binds against an opening edge, increase `switch_clr` (default 0.3mm
   clearance per side) and re-export.
5. **RST button (bottom long edge)** — deliberately has NO opening in v1:
   USB auto-reset covers normal flashing, and the friction-fit lid pops off
   in seconds for the rare manual BOOT+RST dance. If that annoys you in
   practice, note where the switch sits and ask for a pinhole in v1.1.

## Assembly

0. Pins clipped? (See the note at the top — one-time job, do it before the
   board ever goes in the case.)
1. Drop the board into the front shell **display-first**, resting on the
   two end ledges.
2. Foam-tape the battery into the bay on the back shell's base floor.
3. Route the battery's JST lead through the channel and plug it into the
   board.
4. Close the shells: **bottom edge first** — slide the chin under the two
   bottom retention hooks, then rotate the top of the front shell down until
   the seam seats flush all around.

**This is a friction-fit lid, not a snap.** The two bottom hooks are alignment
keys, not pull-off retention — closure holds via the snug seam fit, the
hooks resisting shear/slide, and the foam-taped battery filling the cavity.
Expect to lift it off with a deliberate tug, not a click. To reopen, use the
pry slot at the bottom seam (spudger or fingernail).

*v2 option:* if you want real click-shut retention, the left end wall is
feature-free and can carry a cantilever snap tongue engaging a front
through-window — not built in this version.

## Reference

- `case/dimensions.md` — board/battery dimensions and what to measure if the
  test-fit checklist fails.
- `case.scad` header comment — coordinate frame conventions (assembly frame
  vs. face frame).
