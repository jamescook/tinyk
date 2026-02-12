# Changelog — teek-sdl2

> **Beta**: teek-sdl2 is functional but the API may change between minor versions.

All notable changes to teek-sdl2 will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

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
