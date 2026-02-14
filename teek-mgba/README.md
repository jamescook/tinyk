# teek-mgba

A GBA emulator frontend powered by [teek](https://github.com/jamescook/teek) and libmgba.

Wraps libmgba's mCore C API and provides a full-featured player with SDL2
video/audio rendering, keyboard and gamepad input, save states, and a
Tk-based settings UI.

## Features

- GBA emulation via libmgba
- SDL2 video rendering with configurable window scale (1x-4x)
- SDL2 audio with volume control and mute
- Keyboard and gamepad input with remappable controls
- Quick save/load and 10-slot save state picker with thumbnails
- Turbo/fast-forward mode
- ROM info viewer
- Persistent user configuration

## Language Support

The UI supports multiple languages via YAML-based locale files. The active
language is auto-detected from the system environment (`LANG`) or can be
set manually in the config.

Currently supported:

| Language | Code |
|----------|------|
| English  | `en` |
| Japanese | `ja` |

To force a specific language:

```ruby
Teek::MGBA.user_config.locale = 'ja'
```

Adding a new language: create `lib/teek/mgba/locales/<code>.yml` following
the structure in `en.yml`.

## License

MIT. See [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES) for bundled font licenses.
