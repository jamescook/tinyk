# Changelog — teek-sdl2

> **Beta**: teek-sdl2 is functional but the API may change between minor versions.

All notable changes to teek-sdl2 will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Added

- `Teek::SDL2::AudioStream` — push-based real-time PCM audio output for emulators, synthesizers, and procedural audio. Supports `:s16`, `:f32`, and `:u8` sample formats with configurable frequency and channels
- SDL2_gfx drawing primitives on `Renderer` — many new methods for shapes and curves:
  - `fill_rounded_rect`, `draw_rounded_rect` — rectangles with rounded corners
  - `draw_circle`, `fill_circle`, `draw_aa_circle` — circles (aliased and anti-aliased)
  - `draw_ellipse`, `fill_ellipse`, `draw_aa_ellipse` — ellipses
  - `draw_arc`, `draw_pie`, `fill_pie` — arcs and pie slices
  - `draw_polygon`, `fill_polygon`, `draw_aa_polygon` — arbitrary polygons
  - `draw_trigon`, `fill_trigon`, `draw_aa_trigon` — triangles
  - `draw_bezier` — Bezier curves
  - `draw_aa_line`, `draw_thick_line` — anti-aliased and thick lines
  - `draw_pixel`, `draw_hline`, `draw_vline` — individual pixels and axis-aligned lines
- `Texture#blend_mode=` / `Texture#blend_mode` — get/set texture blend mode (`:none`, `:blend`, `:add`, `:mod`, or custom)
- `SDL2.compose_blend_mode` — create custom blend modes with configurable source/destination factors and operations
- `Viewport.new` accepts `vsync:` keyword (default `true`). Pass `false` for applications that manage their own frame pacing
- `Gamepad#guid` — controller GUID string for per-controller config persistence
- `Gamepad.update_state` — refresh controller state without pumping the platform event loop (avoids macOS Cocoa run loop stealing Tk events)
- `Font#ascent` — maximum pixel ascent for glyph cropping and text layout

### Changed

- `Font#render_text` now premultiplies alpha automatically, fixing transparent-region artifacts with custom blend modes
- `Renderer#fill_rect`, `draw_rect`, `draw_line` now auto-enable alpha blending when alpha < 255

### Fixed

- Gamepad events now fire even when the SDL2 window doesn't have focus (e.g. when a Tk settings window is active)

## [0.1.1] - 2026-02-11

### Added

- `Teek::SDL2::Gamepad` — Xbox-style controller input via SDL2's GameController API with polling, event callbacks, hot-plug, dead zone helper, and virtual gamepad for testing
- `Teek::SDL2::Sound` — short sound effect playback via SDL2_mixer (WAV, OGG, etc.)
- `Teek::SDL2::Music` — streaming music playback via SDL2_mixer (MP3, OGG, etc.) with play/pause/resume/stop and volume control
- `Teek::SDL2.start_audio_capture` / `stop_audio_capture` — record mixed audio output to WAV
- Gamepad viewer sample

### Fixed

- extconf.rb now detects UCRT vs MINGW64 Ruby and shows correct MSYS2 package names

## [0.1.0] - 2026-02-11

Initial release.

### Added

- `Teek::SDL2::Viewport` — embed an SDL2 GPU-accelerated surface inside a Tk frame via `SDL_CreateWindowFrom`
- `Teek::SDL2::Renderer` — draw commands: `clear`, `fill_rect`, `draw_rect`, `draw_line`, `copy`, `present`, plus keyword-arg wrappers `fill`, `outline`, `line`, `blit`
- `Renderer#read_pixels` — read GPU framebuffer as raw RGBA8888 bytes
- `Renderer#save_png` — save framebuffer to PNG via ImageMagick
- `Renderer#render` — block-based draw-and-present
- `Renderer#create_texture` — create ARGB8888 textures (static, streaming, or target access)
- `Renderer#load_image` — load PNG/JPG/BMP/WebP/GIF into GPU texture via SDL2_image
- `Renderer#output_size` — query renderer dimensions
- `Teek::SDL2::Texture` — GPU texture with `update`, `width`, `height`, `destroy`
- `Teek::SDL2::Font` — TTF font rendering to textures via SDL2_ttf
- `Viewport` keyboard input tracking — `key_down?`, `bind`, `focus`
- SDL2 event source integration with Tk mainloop
- Screenshot-based visual regression testing via `assert_sdl2_screenshot`
- SDL2 demo sample

[Unreleased]: https://github.com/jamescook/teek/compare/teek-sdl2-v0.1.1...HEAD
[0.1.1]: https://github.com/jamescook/teek/compare/teek-sdl2-v0.1.0...teek-sdl2-v0.1.1
[0.1.0]: https://github.com/jamescook/teek/releases/tag/teek-sdl2-v0.1.0
