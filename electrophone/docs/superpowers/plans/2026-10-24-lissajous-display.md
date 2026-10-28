# Real-Time Lissajous Display Implementation Plan

Date: 2026-10-24

Design:
`docs/superpowers/specs/2026-10-24-lissajous-display-design.md`

## Success Criteria

- The Lissajous preview plots real mixed audio against a 48-sample delayed
  copy.
- A 262 Hz sine produces a visible closed trajectory.
- Automatic gain keeps low-volume trajectories visible without distorting the
  relative X/Y scale.
- Silence clears the next completed frame.
- Two bitmap banks prevent partially drawn frames from being displayed.
- The preview cycle includes Lissajous at the confirmed position.
- All existing 17 tests continue to pass.
- Gowin build fits GW5A-25 with zero timing violations at 50 MHz.

## Stage 1: Bitmap and Scope Test

1. Add `tb_lissajous_scope.vhd` at the public module seam.
2. Test a 262 Hz sine for a visible, closed trajectory.
3. Test automatic gain with a low-amplitude sine.
4. Test silence and display-bank switching.
5. Confirm the tests fail because `lissajous_scope` is absent.

Verification:

- Failures are limited to the missing module and its bitmap storage.

## Stage 2: Delay, Rasterization, and Auto-Gain

1. Add a 48-entry sample delay line.
2. Add two 96 by 96 bitmap banks.
3. Capture 1024 XY samples per frame.
4. Draw five-pixel crosses for each point.
5. Implement previous-frame peak auto-gain.
6. Add display-latched bank switching and sequential frame clearing.
7. Make scope tests pass.

Verification:

- Positive trajectory, silence, gain, and bank-switch tests pass.

## Stage 3: UI Integration

1. Add `PREVIEW_LISSAJOUS` to the preview type.
2. Insert it between Spectrum and Pressure.
3. Add the Lissajous title, axes, and trace rendering.
4. Wire bitmap read coordinates and the top-level audio sample.
5. Add controller and dashboard tests.

Verification:

- UI cycle and rendered-scene tests pass.
- The screenshot has a centered trace and no panel overlap.

## Stage 4: Integration and Build

1. Add all source files to the Gowin project.
2. Run the full GHDL regression.
3. Run Gowin synthesis, place-and-route, and timing analysis.
4. Inspect resource usage and Fmax.
5. Update README with behavior and measured results.

Verification:

- Full regression passes.
- GW5A-25 resources fit.
- Setup and hold violations are zero.
- Final bitstream is regenerated.
