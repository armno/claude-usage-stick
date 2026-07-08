# 3D-Printed Case (T-Display S3) — Design

**Date:** 2026-07-02
**Goal:** A 3D-printable desk-stand case for the T-Display S3 + 602040 LiPo,
modeled parametrically in OpenSCAD and printed on the user's FDM printer in PLA.

## Decisions (from brainstorming)

- **Form factor:** angled wedge desk stand — screen leaned back ~25° from
  vertical, landscape, like a tiny monitor. Battery hides in the wedge base.
- **Construction:** two-shell wedge, snap-fit. Front shell carries the screen
  bezel, board mounts, and button flexures; back shell is the wedge body with
  the battery bay.
- **Buttons:** living-hinge flexures printed into the case wall (user's pick;
  fatigue/tuning risk accepted — open-hole fallback is a parameter flip).
- **Printer:** user's own FDM, PLA, 0.4mm nozzle assumed. Both shells must
  print flat on the bed, support-free.
- **Measurements:** LILYGO's STEP model (`dimensions/t-display-s3-full.stp`
  from the Xinyuan-LilyGO/T-Display-S3 repo) is the source of truth,
  sanity-checked with the user's 1mm analog calipers (±0.5mm). Generous
  clearances + a test-fit coupon before the full case.

## Geometry

- Rough envelope ~62mm W × ~40mm D × ~45mm H. Final numbers are parametric,
  derived from: board ~56×26mm, battery 40×20×6mm (602040 + lead), 2mm walls,
  fit clearances.
- USB-C edge faces **right** (firmware can flip the screen if cable-left is
  ever preferred).
- Wedge cross-section: front face at ~25° back-lean, flat base, vertical back.

## Parts (2 prints)

1. **Front shell** — screen bezel (window = active area ~43×23mm + margin,
   chamfered so the bezel doesn't shadow the display), board posts/ledge,
   two living-hinge button flexures, USB-C slot in the right wall.
2. **Back shell** — wedge body, battery bay in the base, snap-clip sockets,
   pry slot at the bottom seam for reopening.

Join: 4 cantilever snap clips, 2 per long edge.

## Openings

- Screen window (front face).
- USB-C slot, right wall: sized for a cable plug boot (~12×7mm) so flashing
  and charging work without opening the case.
- Two flexure buttons over the GPIO0/GPIO14 tact switches (same right edge as
  USB-C on this board).
- RST pinhole — position taken from the STEP model, verified on the physical
  board.
- No vents: ~100mA average draw produces negligible heat.

## Living-hinge buttons

- U-shaped slot through the wall leaves a thin cantilever bridge (~0.8mm
  thick); a nub on the inside face presses the tact switch.
- Bridge thickness, bridge width, and nub height are parameters.
- Fallback: a boolean parameter replaces each flexure with a plain open hole
  if the hinges fatigue or won't tune in.

## Battery

- 602040 lies flat in the wedge base, retained with double-sided foam tape
  (no printed clamp — simpler, absorbs the cell's dimensional slop).
- Cable channel routes the JST lead from the bay up to the board's connector.
- Battery stays plugged in during assembly/disassembly.

## Tolerances & printing

- Parametric clearances: 0.25mm around the board pocket, 0.2mm on snap fits —
  single `fit` parameters tunable per printer.
- Walls 2mm. Both shells print flat, support-free, PLA.

## OpenSCAD implementation

- New `case/` directory (approved): `case/case.scad` — one parametric file
  with a dimensions block at the top and a render-mode switch
  (`front` / `back` / `coupon` / `assembly preview`).
- The openscad skill renders preview PNGs from several angles for review
  before any printing, and exports per-part STLs.
- Board dimensions extracted from the STEP model; extraction method (FreeCAD
  CLI vs. manual read-off + calipers) is decided in the implementation plan.

## Print & verify order

1. **Test-fit coupon** — thin frame with just the board pocket + USB/button
   openings (~10 min print). Board drops in, USB cable reaches, buttons line
   up.
2. Adjust clearance parameters from coupon findings.
3. Print both shells; assemble: board into front shell, battery taped into
   base, JST routed, shells snapped.
4. Physical checks: screen fully visible (no bezel shadow), both buttons
   click through the flexures, USB cable seats, snaps hold, wedge sits stable,
   device runs (WiFi unaffected by the case).

## Non-goals

- No printed button caps or press-fit lenses over the screen.
- No screw assembly, no vents, no rubber feet, no wall/monitor mount.
- No multi-material or resin variants.
- No case for other boards (M5StickC etc.).

## Assumed defaults (chosen while user was AFK — cheap to change)

- Construction approach: two-shell wedge (recommended option; presented
  design was approved by the user afterward).
- Tilt angle ~25° back-lean; USB on the right.

## Implementation notes (v1, 2026-07-03)

- Living-hinge buttons dropped: the T-Display S3 side-switch caps project ~2mm past the PCB edge, reaching the case wall's outer face, so the openings are direct-press cutouts (cap footprint + `switch_clr`) — geometrically forced, reviewer-adjudicated.
- Snap clips became 2 bottom retention hooks + a friction-fit seam; the top clips were unprintable support-free in the base-down back-shell orientation and were deleted.
- Left end-wall cantilever snap remains the v2 click-retention option.
