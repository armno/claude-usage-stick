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
mode = "assembly"; // [assembly, board, front, back, clash, probe_board, probe_board_back, probe_battery, probe_seam]

/* [Board — from case/dimensions.md] */
pcb_l         = 62.0;  // measured 2026-07-03 (confirmed by published 62x26 spec)
pcb_w         = 27.0;  // measured
pcb_t         = 1.6;
disp_h        = 4.5;   // measured (glass sits 4.5 above PCB front — user confirmed net of pcb_t)
back_h        = 3.3;   // USB shell (tallest FACTORY rear part)
// The board shipped with soldered pin headers (~9.4mm pins out the back).
// DECISION (user, 2026-07-04): clip the pins flush with the header plastic.
// What remains: the 2.54mm plastic insulator strips + clipped stubs along
// both long edges — modeled conservatively as header_h-tall strips in
// board_mock; probe_board_back verifies the back shell clears them.
header_h      = 3.5;   // clipped-header residue above the PCB back face (2.54 plastic + stub)
header_l      = 34.0;  // strip length envelope (2x12 pins = 30.5, + slop), centered on the board
header_w      = 2.6;   // strip width, sitting flush at each long board edge
// act_* now describe the measured GLASS envelope (user measured glass edges,
// not lit pixels — dark UI background). The window is cut win_inset INSIDE
// this envelope so the bezel overlaps the glass border slightly; the lit area
// (~41.7 x 22.2 panel spec) sits well inside with ~1mm slack per side.
act_l         = 46.0;  // glass length, measured
act_w         = 25.0;  // glass width, measured
act_off_grove = 4.5;   // glass edge from Grove board edge, measured
act_off_bot   = 1.0;   // (pcb_w - act_w)/2 — glass centered across the board width
btn_spacing   = 18.5;  // measured (was a 15.0 guess)
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
switch_clr = 0.3;  // clearance around the side-switch cap in the button opening
win_inset  = 0.55; // window cut this far INSIDE the glass envelope (act_*) per
                   // side: bezel overlaps the glass border 0.55mm — hides the
                   // glass edge, keeps the window clear of the ledge strips
                   // (bottom ledge reaches pocket-y 1.5; window starts at
                   // act_off_bot + win_inset = 1.55), zero pixel-shadow risk.
glass_gap  = 0.3;  // gap between bezel inner face and display glass
seam_gap   = 1.5;  // seam offset behind the PCB back face
base_d     = 42.0; // wedge base depth (front edge to back wall; 42 so the battery bay, pushed back to clear the clipped headers, still fits ahead of the back wall)
chin       = 6.0;  // bottom bezel extension: pocket must clear the base AND the clipped-header bottom row (fz up to wall+glass_gap+disp_h+pcb_t+header_h = 11.9) must stay ≥0.4 above the base floor
usb_slot_w = 12.0; // fits the spec's ~12mm cable boot; hard ceiling ≈13.9 at btn_spacing 18.5 (user's boot unmeasured — coupon verifies)
section    = false; // cut-away view down the center for cavity inspection
clip_w     = 6.0;  // snap-clip arm width (along x)
clip_t     = 1.6;  // snap-clip arm wall thickness
clip_hook  = 1.2;  // snap-clip hook protrusion / engagement depth

/* [Hidden] */
$fn = 48;
eps = 0.01;

// ── Derived ─────────────────────────────────────────────
face_w  = pcb_l + 2*(board_fit + wall);          // wedge width (x)
face_l  = pcb_w + 2*(board_fit + wall) + chin;   // bezel length along slope
wedge_h = face_l * sin(90 - tilt);               // wedge height
face_run = face_l * cos(90 - tilt);              // horizontal run of the face
// Board-pocket origin in face-frame coords (single source of truth,
// reused by Tasks 4-5). The chin pushes the pocket up off the bottom
// edge so it doesn't exit the wedge's zero-depth front corner.
px0     = wall + board_fit;
py0     = wall + board_fit + chin;
// Front-shell slice depth: seam sits seam_gap behind the PCB back face.
// Rear components (back_h tall — USB shell etc.) deliberately protrude
// past the seam into the back shell's cavity (sized in Task 5).
tray_d  = wall + glass_gap + disp_h + pcb_t + seam_gap;
wedge_d = base_d;
// Battery bay footprint (0.5mm slop per side); foam tape supplies retention.
// A raised retaining rib ring — NOT a recess: the back cavity is already
// hollow here (a recess cut would remove empty space), so the "bay" is walls.
bay_l = bat_l + 1;   // 41
bay_w = bat_w + 1;   // 21
bay_d = bat_t + 0.5; // 6.5  (nominal cell height + slop; used by asserts)
// Pocket inner edges in face-frame fy (single source; strips lie just outside).
pocket_fy0 = py0 - board_fit;                       // bottom inner edge (6.2)
pocket_fy1 = pocket_fy0 + (face_l - 2*wall - chin); // top inner edge (32.7)
// Face-slab XY overshoot pads, DERIVED from tilt: the slabs must reach the
// wedge top edge at seam depth (fy_top), else they stop short and a trench
// opens across the closed case's top face (fy_top grows as tilt increases,
// so fixed pads would silently reopen the trench at higher tilt). Front and
// back keep DIFFERENT pads (CGAL coincident-boundary rule — see face_slab).
fy_top    = (wedge_h + tray_d*cos(90 - tilt)) / sin(90 - tilt); // 38.52 @ tilt=25
pad_front = (fy_top - face_l) + 1.0;                            // 4.82  @ tilt=25
pad_back  = (fy_top - face_l) + 2.5;                            // 6.32  @ tilt=25

assert(wedge_d > face_run + wall, "base too shallow for the face slope");
// Battery bay (recomputed for base_d=40 / chin=4.2): the flat base region runs
// from the slope top (face_run) to the back-wall inner face (wedge_d-wall); it
// must hold the battery's width + slop. Binds at ~1.8mm margin.
assert(wedge_d - face_run - wall >= bay_w + 0.5, "base too shallow for battery bay");
assert(bay_d + wall < wedge_h/2, "battery bay deeper than the base region");
// Checks the cavity's actual front-bottom edge: wedge_cavity_front()
// starts at face-y = py0 - board_fit, not py0.
assert((py0 - board_fit)*sin(90 - tilt) - tray_d*cos(90 - tilt) >= wall - eps,
       "board pocket exits the wedge base - increase chin");

// ── Helpers ─────────────────────────────────────────────
// Face frame -> assembly frame. NOTE: the face frame is left-handed by
// design (x width-right, y up-slope, z INTO the case) — the mirror below
// makes that work. Never put chiral geometry (e.g. text) inside on_face().
module on_face() {
    rotate([90 - tilt, 0, 0]) mirror([0, 0, 1]) children();
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
    for (y = [0, pcb_w - header_w]) color("Purple")        // clipped pin headers,
        translate([(pcb_l - header_l)/2, y, disp_h + pcb_t]) // one strip per long edge
            cube([header_l, header_w, header_h]);
}
function act_off_grove_x() = act_off_grove;  // active area starts at Grove end

module battery_mock() {
    color("SteelBlue") cube([bat_l, bat_w, bat_t]);
}

// ── Wedge solid + shell split (Tasks 3-5) ───────────────
// Side profile in the y-z plane, extruded along x.
module wedge_outer() {
    rotate([90, 0, 90])           // put polygon's x=depth(y), y=height(z)
        linear_extrude(face_w)
            polygon([[0, 0], [wedge_d, 0], [wedge_d, wedge_h],
                     [face_run, wedge_h]]);
}

// Slab of thickness t starting at depth d behind the face plane. `pad` is
// the XY overshoot. It is NOT merely "clipped away by wedge_outer() anyway":
// the top face of the closed case leans back, so at seam depth the wedge's
// top edge reaches face-frame fy_top (≈38.5 at tilt=25). The pad MUST push
// the slab past that, or the slab stops short of the top edge and opens a
// trench across the full top seam — so the overshoot is load-bearing at the
// top, and the pads are derived from tilt (pad_front/pad_back above).
// front_blank and back_blank pass DIFFERENT pad values (pad_front vs
// pad_back, 1.5 apart) so their slab cubes never share an exact coincident
// XY boundary; CGAL renders a spurious sliver at such boundaries even when
// the Z-ranges don't overlap.
module face_slab(d, t, pad = pad_front) {
    on_face() translate([-pad, -pad, d])
        cube([face_w + 2*pad, face_l + 2*pad, t]);
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
        // Kept region ends at tray_d - eps (not tray_d + eps as originally
        // drafted) so it stops just short of back_blank's start (tray_d) —
        // a hairline gap, not an overlap, so the two shells never clash.
        intersection() { wedge_outer(); face_slab(-eps, tray_d); }
        wedge_cavity_front();
    }
}

// Cavity portion inside the front slice: the board pocket volume.
// Starts at px0/py0 (not the raw wall offset) so the chin band below
// the pocket stays solid instead of being hollowed out.
module wedge_cavity_front() {
    on_face() translate([px0 - board_fit, py0 - board_fit, wall])
        cube([face_w - 2*wall, face_l - 2*wall - chin, tray_d]); // over-deep: trimmed by slab
}

module back_blank() {
    difference() {
        // Slab thickness is tray_d+1 (not tray_d) so the removed region's
        // far edge lands at tray_d, matching front_blank's kept boundary —
        // using just "tray_d" here left a ~1mm gap of double-claimed
        // material and made front_blank/back_blank overlap at the seam.
        // pad_back (vs front_blank's default pad_front): different XY
        // overshoot so the two slabs' cubes don't share a coincident
        // boundary, and both reach past the wedge top edge (fy_top) so
        // neither leaves a trench (pads derived from tilt).
        difference() { wedge_outer(); face_slab(-1, tray_d + 1, pad = pad_back); }
        wedge_cavity();
    }
}

module maybe_section() {
    if (section)
        difference() { children();
            translate([face_w/2, -5, -1]) cube([face_w, wedge_d + 10, wedge_h + 10]); }
    else children();
}

// ── Front shell features (Task 4) ───────────────────────
// Window: 45° chamfer from a large opening at the outer (visible, print-bed)
// face down to a tight opening (glass envelope minus win_inset) at the inner
// (cavity) face, tapering over exactly the wall thickness — self-supporting
// when printed face-down (bed = outer face, printing proceeds inward).
module screen_window() {
    on_face() translate([px0 + act_off_grove, py0 + act_off_bot, 0])
        hull() {
            // Inner opening: win_inset inside the glass envelope, cut
            // through into the cavity.
            translate([win_inset, win_inset, wall - eps])
                cube([act_l - 2*win_inset, act_w - 2*win_inset, 3]);
            // Outer opening: flared by `wall` per side beyond the inner
            // one, over the wall thickness — 45° outward chamfer.
            translate([win_inset - wall, win_inset - wall, -1])
                cube([act_l - 2*win_inset + 2*wall,
                      act_w - 2*win_inset + 2*wall, 1 + eps]);
        }
}

module usb_slot() {   // right wall, centered on board width; usb_slot_w x 7.
    // y-width matches the connector mock exactly, not +margin: the real
    // board only leaves 1mm between the USB footprint and each button, so a
    // wider cut merges with the button openings — margin is carried in
    // Z-height and X-depth instead.
    on_face() translate([face_w - wall - 1, py0 + pcb_w/2 - usb_slot_w/2,
                         wall + glass_gap + disp_h + pcb_t - 2])
        cube([wall + 2, usb_slot_w, 7]);
}

// One button opening — direct press. The T-Display S3 side-switch cap
// projects ~2mm past the PCB edge, to fx≈60.24: 1.74mm into the 2mm wall and
// only 0.26mm shy of the outer face. Any covering flap/nub is therefore
// impossible (a printed membrane could cover at most ~0.9mm of protrusion),
// which also made a living hinge meaningless — the cap itself is the button
// surface. Each opening clears the cap footprint (btn_w × (pcb_t+2)), grown
// by switch_clr per side, straight through the wall; the switch is pressed
// directly. Board∩shell stays empty (probe_board).
module button_cut(center_y) {
    on_face() translate([face_w - wall - 1,
                         center_y - btn_w/2 - switch_clr,
                         wall + glass_gap + disp_h - switch_clr])
        cube([wall + 2, btn_w + 2*switch_clr, pcb_t + 2 + 2*switch_clr]);
}

// Ledge strips the board's display-side face rests on. They live at the
// board's SHORT ends now: the measured glass envelope (46 of 62 long, 25 of
// a 27 board width) leaves no usable PCB rim along the long edges — the
// original long-edge strips overlapped the glass by ~0.5mm and probe_board
// went solid (board could not seat). The bare front-face rim that actually
// exists is x < act_off_grove (antenna end) and x > act_off_grove + act_l
// (USB end); each strip stays glass_clr clear of the glass edge (absorbs
// board_fit shift + the ±0.5 caliper) and is oversized by ledge_bite INTO
// its end wall and the top/bottom walls: a strip that merely touches the
// cavity boundary sits on a CGAL coincident plane and stays a disconnected
// volume in the rendered solid — a real overlap fuses it.
ledge_bite = 0.15;
glass_clr  = 1.0;   // ledge keep-out from each glass edge
module ledges() {
    x_pairs = [ [px0 - board_fit - ledge_bite,                    // antenna end
                 px0 + act_off_grove - glass_clr],
                [px0 + act_off_grove + act_l + glass_clr,         // USB end
                 face_w - wall + ledge_bite] ];
    on_face() for (p = x_pairs)
        translate([p[0], py0 - board_fit - ledge_bite, wall])
            cube([p[1] - p[0],
                  pcb_w + 2*board_fit + 2*ledge_bite,
                  glass_gap + disp_h]);
}

// ── Back shell features (Task 5) ────────────────────────
// Retention: 2 bottom-strip rigid hooks only. The top clips were removed — in
// back.stl print orientation (base-down) they were unsupported islands starting
// at z=28 over an empty column (they'd have printed as spaghetti and endangered
// the whole part), and their seam-normal retention was ~zero anyway. The case is
// a friction-fit lid (see README): closure holds via the snug seam, the bottom
// hooks resisting shear/slide, and the foam-taped battery filling the cavity. A
// flexing cantilever tongue on the left END WALL engaging a front through-window
// is the documented v2 retention upgrade (printable both orientations) — not
// built here.
// The bottom seam sits at the base with no vertical room for a flexing
// cantilever (the board fills the pocket just above), so the bottom hooks are
// rigid: fused to the base-floor solid, each reaching a chamfered lip toward -y
// (toward the chin) into a slot in the front bottom strip. Closure is rotate-in:
// the chin slides under the hooks bottom-first, then the lid seats; the pry slot
// releases. Slots are grown by snap_fit so each clip sits inside a slot VOID in
// the closed pose -> front∩back stays empty. Plain rectangular posts + wedge
// lips, chamfered on the insertion side, no rounding.
clip_xs        = [ face_w/2 - 26, face_w/2 + 26 ];  // 2 bottom clips, pushed to the
// board's ends: the clipped-header bottom row sweeps through the old ±16
// positions behind the seam corner; at ±26 the hooks sit outside the
// header_l envelope (probe_board_back verifies)
// Bottom rigid retention hook sizing: the front's chin slides under the hooks
// bottom-first during the rotate-in close; the hook overhangs the chin's
// pocket-facing ramp so the chin cannot lift out.
clip_lift_bot  = 0.6;   // hook lip height above the seam corner (chin is close only here)
clip_foot_bot  = 1.5;   // post depth below the corner (into base-floor solid)

// Assembly-frame point of a face-frame seam corner (fx, fy) at the seam depth.
function seam_pt(fx, fy) = [ fx,
    fy*cos(90 - tilt) + tray_d*sin(90 - tilt),
    fy*sin(90 - tilt) - tray_d*cos(90 - tilt) ];

// Bottom rigid hook: short post on the back rim + lip overhanging -y (toward
// the chin), chamfered on the underside for the rotate-in close.
module bot_clip(A) {
    zt = A[2] + clip_lift_bot;
    zb = A[2] - clip_foot_bot;
    translate([A[0] - clip_w/2, A[1], zb]) cube([clip_w, clip_t, zt - zb]);
    hull() {                                             // lip toward -y, chamfer under
        translate([A[0] - clip_w/2, A[1] - clip_hook, zt - eps])
            cube([clip_w, clip_hook + clip_t, eps]);     // top of lip (full reach)
        translate([A[0] - clip_w/2, A[1], zt - clip_hook - eps])
            cube([clip_w, clip_t, eps]);                 // chamfer down to arm face
    }
}
module bot_slot(A) {
    zt = A[2] + clip_lift_bot;
    zb = A[2] - clip_foot_bot;
    // clear the whole post + lip envelope (grown by snap_fit) from the chin
    translate([A[0] - clip_w/2 - snap_fit, A[1] - clip_hook - snap_fit, zb - 1])
        cube([clip_w + 2*snap_fit, clip_hook + clip_t + 2*snap_fit,
              (zt - zb) + 1 + snap_fit]);
}

module clips()      { for (x = clip_xs) bot_clip(seam_pt(x, pocket_fy0)); }
module clip_slots() { for (x = clip_xs) bot_slot(seam_pt(x, pocket_fy0)); }

// Battery retaining rib ring on the base floor (0.5mm slop/side). Bites 0.2mm
// into the floor so it fuses (see ledge_bite precedent). Gap in the seam-facing
// (-y) wall passes the JST lead. (The former jst_channel guide walls are gone:
// their hardcoded y=12 start landed in front of the deepened seam AND inside
// the clipped-header sweep — clash + probe_board_back both flagged them — and
// the measured 86mm lead has so much slack that the bay gap alone guides it.)
rib_t = 1.5; rib_h = 3.0;
bay_x0 = (face_w - bay_l)/2;
bay_y0 = face_run + 1.6;          // pushed back: the clipped-header bottom row's
                                  // deepest corner sweeps to y≈15.4 in front of
                                  // the old rib position (probe_board_back)
jst_gx = face_w/2 + bay_l/2 - 8;  // 42.75  (gap x-start, over the JST corner)
module battery_bay() {
    difference() {
        translate([bay_x0 - rib_t, bay_y0 - rib_t, wall - 0.2])
            cube([bay_l + 2*rib_t, bay_w + 2*rib_t, rib_h + 0.2]);
        translate([bay_x0, bay_y0, wall - 0.2 - eps])
            cube([bay_l, bay_w, rib_h + 0.4]);                       // interior
        translate([jst_gx, bay_y0 - rib_t - eps, wall - 0.2 - eps])
            cube([6, rib_t + 2*eps, rib_h + 0.4]);                   // JST gap
    }
}
// Seam reliefs: rear-side components protrude past the seam into the back shell
// (USB shell fz~6.7-10, buttons fz~5.1-8.7 vs seam tray_d=8.2) and the USB
// cable/boot needs a path. Cut the back rim aligned with usb_slot() + behind
// each button opening. Unlike the FRONT usb_slot (which must stay usb_slot_w
// to clear the button openings), the back reliefs have no such neighbour, so
// they carry +1mm margin per side to over-clear the components (a relief exactly
// the component width leaves a coincident-boundary sliver — verified by probe).
rlf_m = 1.0;   // relief margin per side
module seam_reliefs() {
    on_face() translate([face_w - wall - 2, py0 + pcb_w/2 - usb_slot_w/2 - rlf_m, tray_d - 0.6])
        cube([wall + 3, usb_slot_w + 2*rlf_m, back_h + 3]);          // USB + boot
    for (s = [-1, 1])
        on_face() translate([face_w - wall - 2,
                             py0 + pcb_w/2 + s*btn_spacing/2 - (btn_w + 2)/2 - rlf_m, tray_d - 0.6])
            cube([wall + 3, btn_w + 2 + 2*rlf_m, 3]);                // button relief
}

// Pry slot: finger/spudger access notch, centered on the bottom seam edge.
module pry_slot() {
    on_face() translate([face_w/2 - 3, pocket_fy0 - 2, tray_d - 2])
        cube([6, 4, 3]);
}

module front_shell() {
    maybe_section() union() {
        difference() {
            front_blank();
            screen_window();
            usb_slot();
            for (s = [-1, 1]) button_cut(py0 + pcb_w/2 + s*btn_spacing/2);
            clip_slots();
        }
        ledges();
    }
}
module back_shell() {
    maybe_section() difference() {
        union() { back_blank(); clips(); battery_bay(); }
        seam_reliefs();
        pry_slot();
    }
}
// No separate test-fit coupon: the front shell is already only tray_d
// (8.2mm) deep and contains everything a coupon would test (board pocket,
// window, USB slot, button openings) — a truncated coupon came out
// geometrically identical to front_shell(), so front.stl IS the coupon.
// Print it first; see case/README.md for the test-fit checklist.

// Print-bed orientation for front_shell(): rotates the tilted bezel
// face down flat onto z=0 for slicing. PURE ROTATION about the assembly x
// axis only (no mirror()) — chirality of the solid is unchanged, only its
// pose is. Equivalent to the two-step rotate([180,0,0]) rotate([-(90-tilt),0,0])
// (both rotations share the x axis, so they just add: 180 + tilt-90 = 90+tilt).
// Empirically confirmed (case/previews/orient/): the bezel face lands flat at
// z=0 with the rest of the shell at z>=0, and a top view shows the USB/button
// wall on the same (+x, right) side as the assembly reference — not mirrored.
module print_orient() {
    rotate([90 + tilt, 0, 0]) children();
}

// ── Render dispatch ─────────────────────────────────────
if (mode == "board") {
    board_mock();
    translate([wall + 5, -35, 0]) battery_mock();
} else if (mode == "front") {
    print_orient() front_shell();
} else if (mode == "back") {
    back_shell();          // already base-down at z>=0 in the assembly frame
} else if (mode == "clash") {
    // Full shells (clips + slots): the clips slide into oversized slot VOIDS,
    // so the true intersection must stay EMPTY.
    intersection() { front_shell(); back_shell(); }
} else if (mode == "probe_board") {
    // Expected EMPTY: the board, placed exactly as in assembly, must not
    // intersect the front shell (no PCB/switch-cap/USB interpenetration).
    intersection() {
        on_face() translate([px0, py0, wall + glass_gap]) board_mock();
        front_shell();
    }
} else if (mode == "probe_board_back") {
    // Expected EMPTY: the board — including the clipped-header strips —
    // must not intersect the BACK shell (base floor, battery-bay ribs,
    // JST guides, bottom hooks, seam rim). Added when the pin-header
    // decision landed: probe_board alone only ever checked the front.
    intersection() {
        on_face() translate([px0, py0, wall + glass_gap]) board_mock();
        back_shell();
    }
} else if (mode == "probe_battery") {
    // Expected EMPTY: the battery, placed exactly as in assembly, must not
    // intersect the back shell (bay ribs clear the cell + slop).
    intersection() {
        translate([bay_x0 + 0.5, bay_y0 + 0.5, wall]) battery_mock();
        back_shell();
    }
} else if (mode == "probe_seam") {
    // Closed-case top-seam trench test. Expected EMPTY: a thin box lying in
    // the outer top wall, in the band where a top-seam trench would open
    // (just in front of the seam line), must be fully filled by the two
    // shells — any leftover is the reopened top trench. Tilt-aware: the box
    // is keyed off the seam line's top-face intercept (seam_top_y, ≈23.7 at
    // tilt=25) and stops 1.5mm short of it so it never picks up the
    // intentional 0.01mm inter-shell hairline gap (which leans back by
    // ~1.2mm over the box height even at tilt=40); a real trench shows as
    // tens of mm³.
    seam_top_y = fy_top*cos(90 - tilt) + tray_d*sin(90 - tilt);
    difference() {
        translate([3, seam_top_y - 7.5, wedge_h - 1.4])
            cube([face_w - 6, 6, 1.3]);
        front_shell();
        back_shell();
    }
} else { // assembly
    front_shell();
    back_shell();
    on_face() translate([px0, py0, wall + glass_gap])
        board_mock();
    translate([(face_w - bat_l)/2, face_run + 1, wall])
        battery_mock();
}
