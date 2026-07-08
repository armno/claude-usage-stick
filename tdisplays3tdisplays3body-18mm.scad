// T-Display S3 case body, stretched from 13mm to 18mm height.
//
// Method: cut the original STL at y=7 (an empty band on all walls,
// between the oval port hole ending at y=6.4 and the front-wall
// recess starting at y=8), shift the top part +5mm, and fill the gap
// by extruding the y=7 wall cross-section.
//
// Exception: the square recess on the inner front wall
// (x 8.04..13.04, z 0..1, originally y 8..13) is extended all the
// way down to the open rim, i.e. it spans the full wall height in
// the stretched body (y 0..18).

stl = "tdisplays3tdisplays3body.stl";

cut_y = 7;      // cut plane through the empty wall band (6.4..8.0)
stretch = 5;    // 13mm -> 18mm
eps = 0.1;

// bounding volume helpers (model spans X -1.5..65.31, Z -27.5..1.5)
module below_cut() {
    intersection() {
        import(stl);
        translate([-10, -10, -40]) cube([90, 10 + cut_y, 50]);
    }
}

module above_cut() {
    intersection() {
        import(stl);
        translate([-10, cut_y, -40]) cube([90, 20, 50]);
    }
}

// 2D cross-section of the model at y=cut_y, in (x, -z) coordinates
module cross_section() {
    projection(cut = true)
        translate([0, 0, -cut_y])
        rotate([90, 0, 0])
        import(stl);
}

// gap filler: cross-section extruded across the new 5mm band.
// The section is constant over y 6.4..8.0, so overlapping eps into
// both halves is safe and avoids coincident-face artifacts.
module middle_band() {
    translate([0, cut_y - eps, 0])
        rotate([-90, 0, 0])
        linear_extrude(stretch + 2 * eps)
        cross_section();
}

// front-wall recess extension: the recess sits at y 13..18 after the
// shift; carve the same 5mm-wide, 1mm-deep channel down to y=1, the
// top of the rim skirt (lid seat). Stopping there keeps the bottom
// rim face solid - no hole through the open face.
module recess_extension() {
    translate([8.0437, 1, -eps])
        cube([5, 12 + eps + eps, 1 + eps]);
}

difference() {
    union() {
        below_cut();
        middle_band();
        translate([0, stretch, 0]) above_cut();
    }
    recess_extension();
}
