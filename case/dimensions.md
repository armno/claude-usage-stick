# T-Display S3 measured dimensions

Defaults below come from published specs and the 1.9" 170×320 panel geometry
(active area = 42.6 × 22.6mm computed from the 48.26mm diagonal at 32:17).
The **Measured** column is intentionally left empty: the user waived
pre-measurement, so the first test print IS the measurement (see the
`case/README.md` test-fit checklist). Fill it in from calipers only if a fit
fails. The STEP model
(`Xinyuan-LilyGO/T-Display-S3` → `dimensions/t-display-s3-full.stp`) is the
tie-breaker if a measurement disagrees with a default by >1mm.

| Param           | What to measure                                              | Default | Measured |
|-----------------|--------------------------------------------------------------|---------|----------|
| `pcb_l`         | Board length, USB edge to Grove edge                         | 56.0    | 62       |
| `pcb_w`         | Board width across the long edges                            | 26.0    | 27       |
| `pcb_t`         | Bare PCB edge thickness                                      | 1.6     | 1.6      |
| `stack_t`       | Total thickness: display glass to tallest rear component     | 7.7     | 15.5 (?) |
| `disp_h`        | Display top surface above PCB front face                     | 2.8     | 4.5 (?)  |
| `back_h`        | Tallest rear-side component (USB shell) above PCB back face  | 3.3     | —        |
| `act_l`         | Lit-area length (power the device on, measure the lit part)  | 42.6    | 46 (?)   |
| `act_w`         | Lit-area width                                               | 22.6    | 25 (?)   |
| `act_off_grove` | Lit-area edge distance from the Grove (non-USB) board edge   | 6.0     | 4.5 (?)  |
| `act_off_bot`   | Lit-area distance from the nearest long board edge           | 1.7     | —        |
| `btn_spacing`   | Center-to-center distance between the two buttons            | 15.0    | 18.5     |
| `btn_w`         | Width of one tact switch cap                                 | 4.0     | 4        |
| `has_rst_button`| Any third button anywhere on the board edges? (yes/no + edge)| no      | yes (edge TBD) |

Measured 2026-07-03 with 1mm analog calipers (±0.5). `pcb_l` 62 confirmed by
ProtoSupplies' published spec (62 × 26mm) — the 56.0 default was wrong.
`(?)` entries were clarified the same day (CL-01 sheet) and are now in
`case.scad`:

- `stack_t` 15.5 = soldered pin headers, **confirmed** (user picked "pins" on
  the cross-section card). Pins ≈ 9.4mm behind the PCB back face.
  **DECIDED 2026-07-04: clip the pins flush.** The model carries the residue
  as `header_h`/`header_l`/`header_w` strips in `board_mock`, verified by the
  `probe_board_back` gate. Intact pins do NOT fit — clip before assembly
  (README has the procedure).
- `disp_h` = 4.5 confirmed net of pcb_t (glass really sits 4.5 proud; total
  4.5+1.6+3.3 = 9.4 ≈ the "×10mm" in ProtoSupplies' spec — consistent).
- 46 × 25 = the **glass envelope**, not lit pixels (confirmed). `act_*` in
  `case.scad` now carry glass semantics; window = glass − 2×`win_inset`.
  `act_off_bot` set to (27−25)/2 = 1.0 (glass centered across board width).
- 3rd button = RST on the **bottom long edge**. v1 deliberately has no
  opening for it (pop the lid instead); exact position unrecorded.
- Cable boot width: unmeasured — `usb_slot_w` set to 12.0 (ceiling ≈13.9 at
  `btn_spacing` 18.5); the coupon print verifies.

Also confirm: the two buttons sit on the same short edge as USB-C, one each
side of the connector; the JST battery socket location on the rear face
(distance from USB edge + from long edge), and JST lead length.

| Extra           | What to measure                                    | Measured |
|-----------------|----------------------------------------------------|----------|
| JST socket pos  | Rear face: distance from USB edge / from long edge | 3 / 1.2  |
| JST lead length | Battery lead, cell body to connector tip           | 86       |
| Battery         | Confirm 40 × 20 × 6 (602040) incl. wrap            | —        |
