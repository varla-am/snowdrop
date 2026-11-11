# ADR-0042: Vinyl desktop wallpaper

## Status

Accepted

## Context

A turntable-style wallpaper (a vinyl record that turns while music plays, with the
cover as its label) has to stay on screen all day, so its cost matters more than
anything else about it. A WidgetKit widget cannot animate continuously, and a
SwiftUI `repeatForever` rotation makes the app re-render on every display refresh
(see ADR-0040).

## Decision

- `VinylWallpaperController` owns one borderless, opaque window at
  `desktopWindow + 1` (above the system wallpaper, below the desktop icons) on
  every Desktop, ignoring the mouse. It is toggled from the Window menu and
  restored at launch.
- `VinylWallpaperView` is layers only. The record (grooves, label, spindle hole) and
  the highlight are rendered once into bitmaps per track or size change; the
  backdrop is a 24 px copy of the cover stretched with smooth filtering, which reads
  as a blur without a blur filter. The record turns with a repeating
  `CABasicAnimation` at 33 1/3 rpm (1.8 s per turn) at 30 Hz, so the render server
  does the work.
- `VinylSpinPolicy` holds the animation still, by removing it and keeping the
  angle, when music is paused, when the window is fully covered
  (`occlusionState`), when the display sleeps, or when Reduce Motion is on. Low
  Power Mode lowers the rate to 15 Hz.

## Consequences

- Paused or covered, the wallpaper costs nothing: the layers are static.
- Playing and uncovered, the app does no per-frame work; only the GPU rotates a
  texture at 30 Hz.
- Only the primary display is covered, and only music (not YouTube video) drives it.
- Not measured on hardware yet; the Activity Monitor and Energy numbers should be
  added here once checked on battery.

## Update: a desk drawn live, day and night, Cmd+H

The wallpaper window sets `canHide = false`, so Cmd+H no longer hides it.

Two earlier attempts were dropped. A SceneKit 3D scene could not reach a photographic look. A Blender
render with pre-rendered tonearm poses looked good but the swing was not smooth: cross-fading poses
ghosted, and the shadow baked into each pose flickered. Rendering also took half an hour per change.

The wallpaper is now a desk seen from above, drawn live from Core Graphics and Core Animation layers,
with no image assets: a brushed-metal top (generated once), the cover in its sleeve, a record with
grooves and track gaps, and a tonearm.

- Only the label, which carries the cover, turns; the grooves and a conic-gradient highlight are
  symmetric and stay put, as on a real record. `VinylSpinDynamics` keeps the spin-up and coast-down.
- The tonearm is one layer rotated about its pivot by `VinylArmMotion` (eased, 1.7 s down, 1.3 s up). Its
  shadow is a blurred silhouette rotated about the same pivot and offset by how high the arm is lifted,
  so it cannot fall out of step with the arm.
- Day and night are two backgrounds cross-faded over six seconds, with shadow strength following.
  `VinylDaySchedule` decides when (default night 22:00 to 07:00); settings are in Appearance, under
  "Vinyl wallpaper": Automatic, Day or Night. A timer is armed for the next change and re-armed after a
  clock, time-zone or wake event.
- A display link runs only while something moves (60 fps, 30 in Low Power Mode); an idle wallpaper uses
  no GPU.
