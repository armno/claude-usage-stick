# 3D-Printed Wedge Case Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A parametric OpenSCAD model of a two-shell wedge desk-stand case for the T-Display S3 + 602040 LiPo, verified through rendered previews and a printed test-fit coupon, exported as STLs.

**Architecture:** One `case/case.scad` file, all geometry in an "assembly frame" (desk = XY plane, z up). A `mode` variable selects what renders: reference mocks, front shell, back shell, coupon, or full assembly. The wedge outer solid is split by a plane parallel to the screen face into a front shell (bezel, board pocket, USB slot, button flexures) and a back shell (wedge body, battery bay, snap clips). Verification = `validate.sh` + `assert()` invariants + multi-angle PNG renders read visually + physical coupon print.

**Tech Stack:** OpenSCAD 2021.01 (installed at `/opt/homebrew/bin/openscad`), openscad skill tools at `~/.claude/skills/openscad/tools/`, PLA FDM printing.

**Spec:** `docs/superpowers/specs/2026-07-02-3d-printed-case-design.md`

## Global Constraints

- All dimensions in mm. OpenSCAD 2021.01 syntax only (no newer language features).
- Both shells must print flat on the bed, support-free: front shell face-down, back shell base-down. No overhang steeper than 45° from vertical in print orientation.
- Walls 2.0mm. Clearances: 0.25mm around the board pocket, 0.2mm on snap fits — single parameters, never hardcoded per-feature.
- Every `.scad` change: run `~/.claude/skills/openscad/tools/validate.sh case/case.scad`, then render previews and **Read every generated PNG** — never deliver geometry without looking at it (openscad skill rule).
- Git: all work on branch `3d-case`; one commit per task, 1-line message, no `Co-Authored-By`. Never merge to `main` or push without explicit user go-ahead. (User pre-approved per-task branch commits at execution start; if that approval is missing, ask before the first commit.)
- Working directory for all commands: repo root `/Users/armno/code/personal/claude-usage-stick`.
- Tool shorthand used below: `TOOLS=~/.claude/skills/openscad/tools`.

---

### Task 1: Dimension capture

**Files:**
- Create: `case/dimensions.md`

**Interfaces:**
- Produces: confirmed values for the `/* [Board] */` parameter block used verbatim in Task 2. Parameter names defined here are final: `pcb_l, pcb_w, pcb_t, stack_t, disp_h, back_h, act_l, act_w, act_off_grove, act_off_bot, btn_spacing, btn_w, has_rst_button`.

- [ ] **Step 1: Create the measurement sheet with prefilled defaults**

Write `case/dimensions.md`:

```markdown
# T-Display S3 measured dimensions

Defaults below come from published specs and the 1.9" 170×320 panel geometry
(active area = 42.6 × 22.6mm computed from the 48.26mm diagonal at 32:17).
"Measured" column filled from the user's calipers (1mm scale, ±0.5mm — fine,
every opening carries ≥1mm margin). The STEP model
(`Xinyuan-LilyGO/T-Display-S3` → `dimensions/t-display-s3-full.stp`) is the
tie-breaker if a measurement disagrees with a default by >1mm.

| Param           | What to measure                                              | Default | Measured |
|-----------------|--------------------------------------------------------------|---------|----------|
| `pcb_l`         | Board length, USB edge to Grove edge                         | 56.0    |          |
| `pcb_w`         | Board width across the long edges                            | 26.0    |          |
| `pcb_t`         | Bare PCB edge thickness                                      | 1.6     |          |
| `stack_t`       | Total thickness: display glass to tallest rear component     | 7.7     |          |
| `disp_h`        | Display top surface above PCB front face                     | 2.8     |          |
| `back_h`        | Tallest rear-side component (USB shell) above PCB back face  | 3.3     |          |
| `act_l`         | Lit-area length (power the device on, measure the lit part)  | 42.6    |          |
| `act_w`         | Lit-area width                                               | 22.6    |          |
| `act_off_grove` | Lit-area edge distance from the Grove (non-USB) board edge   | 6.0     |          |
| `act_off_bot`   | Lit-area distance from the nearest long board edge           | 1.7     |          |
| `btn_spacing`   | Center-to-center distance between the two buttons            | 15.0    |          |
| `btn_w`         | Width of one tact switch cap                                 | 4.0     |          |
| `has_rst_button`| Any third button anywhere on the board edges? (yes/no + edge)| no      |          |

Also confirm: the two buttons sit on the same short edge as USB-C, one each
side of the connector; the JST battery socket location on the rear face
(distance from USB edge + from long edge), and JST lead length.

| Extra           | What to measure                                    | Measured |
|-----------------|----------------------------------------------------|----------|
| JST socket pos  | Rear face: distance from USB edge / from long edge |          |
| JST lead length | Battery lead, cell body to connector tip           |          |
| Battery         | Confirm 40 × 20 × 6 (602040) incl. wrap            |          |
```

- [ ] **Step 2: User checkpoint — collect measurements**

Ask the user to measure the table rows (needs: board in hand, powered once for the lit-area rows, calipers). Fill the Measured column with their numbers. This is a blocking user interaction — do not guess values. If a measured value differs from its default by more than 1mm, flag it in the sheet and use the measured value.

- [ ] **Step 3: Create branch and commit**

```bash
git checkout -b 3d-case
git add case/dimensions.md
git commit -m "docs: T-Display S3 measured dimensions for case"
```

---

### Task 2: Scaffold case.scad — parameters, modes, reference mocks

**Files:**
- Create: `case/case.scad`

**Interfaces:**
- Consumes: measured values from `case/dimensions.md` (replace the `/* [Board] */` defaults below with the measured column).
- Produces: parameter names above plus `/* [Case] */` params (`tilt, wall, board_fit, snap_fit, win_margin, tray_d, base_d`); modules `board_mock()`, `battery_mock()`, helper `on_face()`; derived values `face_w, face_l, wedge_h, wedge_d`; render-mode dispatch on `mode`. Later tasks add `front_shell()`, `back_shell()` — the dispatch block already references stubs for them.

- [ ] **Step 1: Write the scaffold**

`case/case.scad` (complete file; board defaults shown — substitute measured values):

```openscad
// T-Display S3 wedge desk-stand case — two shells, snap-fit.
// Spec: docs/superpowers/specs/2026-07-02-3d-printed-case-design.md
// Dims:  case/dimensions.md   (all mm)
//
// Assembly frame: desk = XY plane, +z up, +y toward the back of the wedge.
// Screen face leans back `tilt` deg from vertical; its outer surface contains
// the front bottom edge of the wedge (y=0, z=0).
// Face frame (used by on_face()): XY = screen face outer surface, +x device
// width, +y up along the slope, +z INTO the case.

/* [Render] */
mode = "assembly"; // [assembly, board, front, back, coupon]

/* [Board — from case/dimensions.md] */
pcb_l         = 56.0;
pcb_w         = 26.0;
pcb_t         = 1.6;
disp_h        = 2.8;
back_h        = 3.3;
act_l         = 42.6;
act_w         = 22.6;
act_off_grove = 6.0;
act_off_bot   = 1.7;
btn_spacing   = 15.0;
btn_w         = 4.0;

/* [Battery 602040] */
bat_l = 40.0;
bat_w = 20.0;
bat_t = 6.0;

/* [Case] */
tilt       = 25;   // [15:5:40] face back-lean from vertical, deg
wall       = 2.0;
board_fit  = 0.25; // clearance around the board pocket
snap_fit   = 0.20; // clearance on snap fits
win_margin = 1.0;  // window overcut per side around the active area
glass_gap  = 0.3;  // gap between bezel inner face and display glass
base_d     = 36.0; // wedge base depth (front edge to back wall)
flex_buttons = true; // false = plain open holes instead of living hinges

/* [Hidden] */
$fn = 48;
eps = 0.01;

// ── Derived ─────────────────────────────────────────────
face_w  = pcb_l + 2*(board_fit + wall);          // wedge width (x)
face_l  = pcb_w + 2*(board_fit + wall);          // bezel length along slope
wedge_h = face_l * sin(90 - tilt);               // wedge height
face_run = face_l * cos(90 - tilt);              // horizontal run of the face
tray_d  = wall + glass_gap + disp_h + pcb_t + 1.5; // front-shell slice depth
wedge_d = base_d;

assert(wedge_d > face_run + wall, "base too shallow for the face slope");
assert(face_w - 2*wall > bat_l + 1, "battery does not fit across the base");

// ── Helpers ─────────────────────────────────────────────
// Face frame -> assembly frame.
module on_face() {
    rotate([90 - tilt, 0, 0]) children();
}

// ── Reference mocks (never printed) ────────────────────
// Board in face frame: display glass toward -z, PCB behind it.
// Origin: board's lower-left corner at x=0,y=0 of the *pocket*; callers
// translate by wall+board_fit. z=0 is the display glass top surface.
module board_mock() {
    color("DarkGreen") translate([0, 0, disp_h])
        cube([pcb_l, pcb_w, pcb_t]);                       // PCB
    color("Black") translate([act_off_grove_x(), act_off_bot, 0])
        cube([act_l, act_w, disp_h]);                      // display block
    color("Silver")                                        // USB-C, right edge
        translate([pcb_l - eps, pcb_w/2 - 4.5, disp_h + pcb_t])
            cube([7.4, 9.0, 3.3]);
    for (s = [-1, 1]) color("Orange")                      // buttons flank USB
        translate([pcb_l - eps, pcb_w/2 + s*btn_spacing/2 - btn_w/2, disp_h])
            cube([2.0, btn_w, pcb_t + 2.0]);
}
function act_off_grove_x() = act_off_grove;  // active area starts at Grove end

module battery_mock() {
    color("SteelBlue") cube([bat_l, bat_w, bat_t]);
}

// ── Shell stubs (Tasks 3-5) ─────────────────────────────
module front_shell() {}
module back_shell()  {}
module coupon()      {}

// ── Render dispatch ─────────────────────────────────────
if (mode == "board") {
    board_mock();
    translate([wall + 5, -35, 0]) battery_mock();
} else if (mode == "front") {
    front_shell();
} else if (mode == "back") {
    back_shell();
} else if (mode == "coupon") {
    coupon();
} else { // assembly
    front_shell();
    back_shell();
    on_face() translate([wall + board_fit, wall + board_fit, wall + glass_gap])
        board_mock();
    translate([(face_w - bat_l)/2, face_run + 1, wall])
        battery_mock();
}
```

- [ ] **Step 2: Validate**

```bash
TOOLS=~/.claude/skills/openscad/tools
$TOOLS/validate.sh case/case.scad
```
Expected: `✓ Syntax OK`, no assert failures.

- [ ] **Step 3: Render the board mock and inspect**

```bash
$TOOLS/multi-preview.sh case/case.scad case/previews/board/ -D 'mode="board"'
```
Read all six PNGs. Check: PCB is 56×26 proportioned, display block sits toward the Grove (left) end, USB block + two orange buttons on the right edge, battery block is 2:1 rectangle. Fix and re-render until correct.

- [ ] **Step 4: Commit**

```bash
git add case/case.scad case/previews/board/
git commit -m "feat(case): scaffold parametric case.scad with board/battery mocks"
```

---

### Task 3: Wedge outer solid and shell split (blank shells)

**Files:**
- Modify: `case/case.scad` (replace the stub `front_shell()`/`back_shell()`; add `wedge_outer()`, `face_slab()`, section-view support)

**Interfaces:**
- Consumes: derived values from Task 2 (`face_w, face_l, wedge_h, wedge_d, tray_d`), `on_face()`.
- Produces: `wedge_outer()` (solid wedge), `front_blank()` / `back_blank()` (hollowed halves, no features), `front_shell()` / `back_shell()` now render the blanks; `section = false` parameter renders a center cross-section when true.

- [ ] **Step 1: Add the wedge solid and split**

Add to `case/case.scad` (replacing the shell stubs):

```openscad
/* [Case] */  // append to the existing block
section = false; // cut-away view down the center for cavity inspection

// Side profile in the y-z plane, extruded along x.
module wedge_outer() {
    rotate([90, 0, 90])           // put polygon's x=depth(y), y=height(z)
        linear_extrude(face_w)
            polygon([[0, 0], [wedge_d, 0], [wedge_d, wedge_h],
                     [face_run, wedge_h]]);
}

// Slab of thickness t starting at depth d behind the face plane.
module face_slab(d, t) {
    on_face() translate([-1, -1, d])
        cube([face_w + 2, face_l + 2, t]);
}

// Interior cavity: wedge shrunk by `wall` on all faces except the front
// face (the bezel handles that side in the front shell).
module wedge_cavity() {
    rotate([90, 0, 90]) translate([0, 0, wall])
        linear_extrude(face_w - 2*wall)
            offset(delta = -wall)
                polygon([[0, 0], [wedge_d, 0], [wedge_d, wedge_h],
                         [face_run, wedge_h]]);
}

module front_blank() {
    difference() {
        intersection() { wedge_outer(); face_slab(-eps, tray_d + eps); }
        wedge_cavity_front();
    }
}

// Cavity portion inside the front slice: the board pocket volume.
module wedge_cavity_front() {
    on_face() translate([wall, wall, wall])
        cube([face_w - 2*wall, face_l - 2*wall, tray_d]); // over-deep: trimmed by slab
}

module back_blank() {
    difference() {
        difference() { wedge_outer(); face_slab(-1, tray_d); }
        wedge_cavity();
    }
}

module maybe_section() {
    if (section)
        difference() { children();
            translate([face_w/2, -5, -1]) cube([face_w, wedge_d + 10, wedge_h + 10]); }
    else children();
}
```

Change `front_shell()`/`back_shell()` to:

```openscad
module front_shell() { maybe_section() front_blank(); }
module back_shell()  { maybe_section() back_blank(); }
```

- [ ] **Step 2: Validate + render assembly and section**

```bash
$TOOLS/validate.sh case/case.scad
$TOOLS/multi-preview.sh case/case.scad case/previews/assembly/
$TOOLS/preview.sh case/case.scad case/previews/section.png -D 'section=true' --camera=0,0,0,90,0,90,0
```
Read all PNGs. Check: wedge silhouette matches the spec sketch (flat base, ~25° face, vertical back); front slice + back body mate with no gap or overlap at the seam; the board mock sits inside the front slice in the section view with the display against the bezel plane; battery mock sits inside the base cavity. Iterate `base_d`/`tray_d` if the mocks poke through walls — re-render after each change.

- [ ] **Step 3: Interference smoke check**

Temporarily append `intersection() { front_blank(); back_blank(); }` as `mode=="clash"` branch in the dispatch (keep it — later tasks reuse it):

```openscad
} else if (mode == "clash") {
    intersection() { front_blank(); back_blank(); }
```

```bash
openscad -o case/previews/clash.stl -D 'mode="clash"' case/case.scad 2>&1 | tail -3
```
Expected: OpenSCAD warns `Current top level object is empty` — the shells do not overlap. A non-empty STL is a failure: fix the seam before continuing.

- [ ] **Step 4: Commit**

```bash
git add case/case.scad case/previews/
git commit -m "feat(case): wedge outer solid split into blank front/back shells"
```

---

### Task 4: Front shell features — window, board mounts, USB slot, buttons

**Files:**
- Modify: `case/case.scad` (`front_shell()` internals)

**Interfaces:**
- Consumes: `front_blank()`, board params, `on_face()`.
- Produces: final `front_shell()` = blank − window − USB slot − button openings + ledge strips; `flex_buttons=false` swaps living hinges for plain holes.

- [ ] **Step 1: Add the features**

All cuts in face frame. Pocket origin (board lower-left) is at `[wall + board_fit, wall + board_fit]`; the window must align to the *active area*, not the board.

```openscad
px = wall + board_fit;  // pocket origin x (Grove end at left)
py = wall + board_fit;

module screen_window() {
    on_face() translate([px + act_off_grove - win_margin,
                         py + act_off_bot   - win_margin, -1])
        hull() {  // 45° chamfer opening outward (printed face-down => no support)
            translate([0, 0, 1 - eps])
                cube([act_l + 2*win_margin, act_w + 2*win_margin, wall + 2]);
            translate([-wall, -wall, 0])
                cube([act_l + 2*(win_margin + wall),
                      act_w + 2*(win_margin + wall), eps]);
        }
}

module usb_slot() {   // right wall, centered on board width; 12 x 7 for plug boots
    on_face() translate([face_w - wall - 1, py + pcb_w/2 - 6,
                         wall + glass_gap + disp_h + pcb_t - 2])
        cube([wall + 2, 12, 7]);
}

// One button opening. Living hinge: U-slot leaves a 0.8mm bridge with an
// inner nub over the switch; fallback: plain hole.
bridge_t = 0.8;  // hinge bridge thickness
module button_cut(center_y) {
    if (flex_buttons)
        on_face() translate([face_w - wall - 1, center_y - (btn_w + 2)/2,
                             wall + glass_gap + disp_h - 1]) {
            // U-slot: three thin channels through the wall around the bridge
            cube([wall + 2, 0.6, pcb_t + 4]);                      // bottom leg
            translate([0, btn_w + 1.4, 0]) cube([wall + 2, 0.6, pcb_t + 4]);
            translate([0, 0, pcb_t + 4 - 0.6]) cube([wall + 2, btn_w + 2, 0.6]);
        }
    else
        on_face() translate([face_w - wall - 1, center_y - (btn_w + 1)/2,
                             wall + glass_gap + disp_h - 0.5])
            cube([wall + 2, btn_w + 1, pcb_t + 3]);
}
module button_nub(center_y) {   // only with flex_buttons: presses the switch
    on_face() translate([face_w - wall - 1.0, center_y - 1,
                         wall + glass_gap + disp_h])
        cube([1.0, 2, 2]);
}

// Ledge strips along the long edges: board's display-side face rests on them.
module ledges() {
    on_face() for (y = [wall, face_l - wall - 1.5])
        translate([px + 4, y, wall])
            cube([pcb_l - 8 - 12, 1.5, glass_gap + disp_h]); // keep clear of USB end
}

module front_shell() {
    maybe_section() union() {
        difference() {
            front_blank();
            screen_window();
            usb_slot();
            for (s = [-1, 1]) button_cut(py + pcb_w/2 + s*btn_spacing/2);
        }
        ledges();
        if (flex_buttons)
            for (s = [-1, 1]) button_nub(py + pcb_w/2 + s*btn_spacing/2);
    }
}
```

The exact leg widths/positions of the U-slot will need visual tuning — the invariant to preserve: bridge ≈ `btn_w+1` wide, anchored at the bottom, free on the other three sides, nub centered over the switch cap.

- [ ] **Step 2: Validate + render both button variants**

```bash
$TOOLS/validate.sh case/case.scad
$TOOLS/multi-preview.sh case/case.scad case/previews/front/ -D 'mode="front"'
$TOOLS/preview.sh case/case.scad case/previews/front_holes.png -D 'mode="front"' -D 'flex_buttons=false'
$TOOLS/preview.sh case/case.scad case/previews/front_section.png -D 'mode="front"' -D 'section=true' --camera=0,0,0,90,0,90,0
```
Read every PNG. Check: window rectangle sits over the display mock's footprint (render `mode="assembly"` too and compare), chamfer visible, USB slot and two U-slots on the right wall at board level, ledges present in the section, hole-variant renders plain rectangles. Iterate until all pass.

- [ ] **Step 3: Commit**

```bash
git add case/case.scad case/previews/
git commit -m "feat(case): front shell window, ledges, USB slot, flex buttons"
```

---

### Task 5: Back shell features — battery bay, cable channel, snaps

**Files:**
- Modify: `case/case.scad` (`back_shell()` internals, clip slots in `front_shell()`, real battery assert)

**Interfaces:**
- Consumes: `back_blank()`, `front_shell()`, battery params, `snap_fit`.
- Produces: final `back_shell()` with battery bay + JST channel + 4 cantilever clips; matching clip slots cut into the front shell's base/top strips; `mode="clash"` still renders empty.

- [ ] **Step 1: Add battery bay, channel, clips**

```openscad
// Battery bay: recess in the base floor of the back shell, opening toward
// the seam. 0.5mm slop per side; foam tape supplies retention.
bay_l = bat_l + 1;  bay_w = bat_w + 1;  bay_d = bat_t + 0.5;

module battery_bay() {
    translate([(face_w - bay_l)/2, face_run + 0.5, wall - eps])
        cube([bay_l, bay_w, bay_d]);
}
module jst_channel() {  // lead runs forward from the bay through the seam region
    translate([face_w/2 + bay_l/2 - 8, wall, wall - eps])
        cube([6, face_run + 2, bay_d]);
}

// Cantilever clips: rise from the back shell's cavity rim, hook into slots
// in the front shell's base/top strips. 2 bottom + 2 top.
clip_w = 6; clip_t = 1.6; clip_hook = 1.2; clip_len = tray_d + 2;
```

The clip module geometry itself is the one part not worth pre-writing blind — shape it in the render loop against these parameters: start from a `cube` arm + 45°-chamfered hook (a `polyhedron` or hulled cubes), anchored to `back_blank()`'s rim, entering matching `clip_w + 2*snap_fit` slots cut in the front strips, hook engagement `clip_hook` beyond the slot edge, plus a 6×3mm pry slot centered on the bottom seam. Constraints that make it printable and serviceable: arm cross-section `clip_w × clip_t` vertical in print orientation, hook chamfered on the insertion side, slot depth = strip thickness. Iterate: render `mode="back"`, `mode="front"`, `mode="assembly"`, and section views after every change; keep going until the clips visibly engage the slots in the section render.

Replace the Task-2 placeholder assert with the real one:

```openscad
assert(wedge_d - face_run - wall >= bay_w + 0.5, "base too shallow for battery bay");
assert(bay_d + wall < wedge_h/2, "battery bay deeper than the base region");
```

- [ ] **Step 2: Validate + render + clash check**

```bash
$TOOLS/validate.sh case/case.scad
$TOOLS/multi-preview.sh case/case.scad case/previews/back/ -D 'mode="back"'
$TOOLS/preview.sh case/case.scad case/previews/assembly_section.png -D 'section=true' --camera=0,0,0,90,0,90,0
openscad -o case/previews/clash.stl -D 'mode="clash"' case/case.scad 2>&1 | tail -3
```
Read the PNGs: battery mock inside the bay with visible slop, JST channel connects bay to seam, 4 clips + slots engaged in section, pry slot on the bottom seam. Clash render must be empty (clips overlap slots by design — exclude the clip/slot pairs from the clash modules or verify the only intersection volume is the intended `clip_hook` engagement; state which in a comment).

- [ ] **Step 3: Commit**

```bash
git add case/case.scad case/previews/
git commit -m "feat(case): back shell battery bay, JST channel, snap clips"
```

---

### Task 6: Coupon mode, STL export, print docs

**Files:**
- Modify: `case/case.scad` (`coupon()`)
- Create: `case/README.md`, `case/stl/` outputs

**Interfaces:**
- Consumes: `front_shell()`.
- Produces: `coupon()` = front shell with walls truncated to 6mm above the bezel (fast print that still tests board pocket, window position, USB slot, button alignment); STLs `case/stl/{coupon,front,back}.stl`; print/assembly README.

- [ ] **Step 1: Coupon mode**

```openscad
module coupon() {
    intersection() {
        front_shell();
        face_slab(-1, 6 + 1);   // bezel + first 6mm of wall height
    }
}
```

- [ ] **Step 2: Export STLs (print orientation)**

Front/coupon print face-down: STL must lie flat. Add a final orientation wrapper in the dispatch: front + coupon exported as `on_face()`-inverse — rotate so the face plane is XY with the bezel at z=0 facing down is exactly the face frame; export front/coupon in **face frame** by wrapping with `rotate([-(90 - tilt), 0, 0])`. Back shell already sits base-down. Then:

```bash
$TOOLS/export-stl.sh case/case.scad case/stl/coupon.stl -D 'mode="coupon"'
$TOOLS/export-stl.sh case/case.scad case/stl/front.stl  -D 'mode="front"'
$TOOLS/export-stl.sh case/case.scad case/stl/back.stl   -D 'mode="back"'
```
Expected: three STLs, no warnings. Confirm bed orientation by rendering the export modes with the orientation wrapper active and checking each part sits flat at z=0:
```bash
$TOOLS/preview.sh case/case.scad case/previews/orient_front.png -D 'mode="front"' --camera=0,0,0,90,0,0,0
$TOOLS/preview.sh case/case.scad case/previews/orient_coupon.png -D 'mode="coupon"' --camera=0,0,0,90,0,0,0
$TOOLS/preview.sh case/case.scad case/previews/orient_back.png -D 'mode="back"' --camera=0,0,0,90,0,0,0
```
Read all three: bezel/coupon face and back-shell base must be the lowest flat surface.

- [ ] **Step 3: Write case/README.md**

Contents (write them out fully): print settings (PLA, 0.2mm layers, 3 perimeters for flexure strength, no supports, front/coupon face-down, back base-down), assembly order (board into front shell display-first onto ledges → battery foam-taped into bay → JST routed through channel and plugged → shells snapped, bottom edge first), reopening (pry slot), and the fallback note (`flex_buttons=false` + re-export if hinges fail).

- [ ] **Step 4: Commit**

```bash
git add case/case.scad case/stl/ case/README.md case/previews/
git commit -m "feat(case): coupon mode, STL exports, print/assembly README"
```

---

### Task 7: Physical verification loop

**Files:**
- Modify: `case/case.scad` (fit parameters only), `case/dimensions.md` (findings), re-export `case/stl/`

**Interfaces:**
- Consumes: printed coupon + shells, user feedback.
- Produces: tuned `board_fit`/`snap_fit`/flexure params; final STLs; spec's physical checklist all passing.

- [ ] **Step 1: User prints the coupon** — board drop-in fit, window over lit area (power it in the coupon), USB cable seats through the slot, buttons align under the flexure bridges. Collect what binds or rattles.
- [ ] **Step 2: Tune parameters** — adjust only `board_fit`, window offsets (via corrected `act_off_*` in dimensions.md), USB slot position, `btn_spacing`, `bridge_t`. One change → validate → re-render → re-export coupon → reprint if the change is >0.3mm. Record each round in `case/dimensions.md` under a `## Fit findings` heading.
- [ ] **Step 3: User prints both shells** — full assembly per README. Run the spec's checklist: screen fully visible, buttons click, USB seats, snaps hold, wedge stable, device runs with WiFi inside the case.
- [ ] **Step 4: Commit the tuned state**

```bash
git add case/
git commit -m "feat(case): fit-tuned parameters from coupon/print verification"
```

---

## Self-review notes

- Spec coverage: geometry (T3), parts/openings/buttons (T4), battery (T5), tolerances+coupon (T1/T6/T7), OpenSCAD+`case/` layout (T2), print order (T6/T7), fallback holes (T4), README (T6). RST pinhole: pending Task 1's `has_rst_button` — if the answer is yes, add a 2mm hole in the reported edge's wall during Task 4.
- Honest placeholders: clip geometry (Task 5) and U-slot leg tuning (Task 4) are explicitly render-loop work with stated invariants, not pre-written blind — visual iteration is the test cycle for those steps.
- Type consistency: parameter names fixed in Task 1 and used verbatim throughout; `mode` values match the dispatch; `TOOLS` path constant everywhere.
