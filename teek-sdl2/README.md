# Teek::SDL2

GPU-accelerated 2D rendering for [Teek](https://github.com/jamescook/teek) via SDL2.

Embeds an SDL2 hardware-accelerated surface inside a Tk window. Draw with the GPU while keeping full access to Tk widgets, menus, dialogs, and layout.

## Quick Start

```ruby
require 'teek'
require 'teek/sdl2'

app = Teek::App.new
app.set_window_title('SDL2 Demo')

viewport = Teek::SDL2::Viewport.new(app, width: 800, height: 600)
viewport.pack(fill: :both, expand: true)

viewport.render do |r|
  r.clear(0, 0, 0)
  r.fill_rect(100, 100, 200, 150, 255, 0, 0)
  r.draw_rect(100, 100, 200, 150, 255, 255, 255)
end

app.mainloop
```

## Features

- **Viewport** -- SDL2 renderer embedded in a Tk frame
- **Renderer** -- hardware-accelerated drawing (rectangles, lines, textures)
- **Texture** -- streaming, static, and render-target textures
- **Image loading** -- PNG, JPG, BMP, WebP, GIF, and more via SDL2_image
- **Font** -- TrueType text rendering and measurement via SDL2_ttf
- **Keyboard input** -- poll key state with `viewport.key_down?('space')`
- **Audio** -- sound effects and music playback via SDL2_mixer, with WAV capture
- **Gamepad** -- Xbox-style controller input with polling, events, and hot-plug

## Image Loading

```ruby
# Load an image file directly into a GPU texture
sprite = renderer.load_image("assets/player.png")
renderer.copy(sprite, nil, [x, y, sprite.width, sprite.height])

# Or use the Texture convenience constructor
bg = Teek::SDL2::Texture.from_file(renderer, "assets/background.jpg")
```

Supports PNG, JPG, BMP, GIF, WebP, TGA, and other formats via SDL2_image.

## Textures

```ruby
# Streaming texture for dynamic pixel data (e.g. emulators, video)
tex = Teek::SDL2::Texture.streaming(renderer, 256, 224)
tex.update(pixel_data)   # ARGB8888, 4 bytes per pixel
renderer.copy(tex)

# Copy a sub-region
renderer.copy(tex, [0, 0, 128, 112], [100, 100, 256, 224])
```

## Text Rendering

```ruby
font = renderer.load_font("/path/to/font.ttf", 16)

# One-shot draw
renderer.draw_text(10, 10, "Score: 100", font: font, r: 255, g: 255, b: 255)

# Measure for layout
w, h = font.measure("Score: 100")
```

## Keyboard Input

```ruby
# Tk keysym names, lowercase
viewport.key_down?('left')
viewport.key_down?('space')
viewport.key_down?('a')

# Or bind events directly
viewport.bind('KeyPress', :keysym) { |key| puts key }
```

## Audio

Sound effects and music playback via SDL2_mixer.

```ruby
# Short sound effects (can overlap)
click = Teek::SDL2::Sound.new("click.wav")
click.play
click.play(volume: 64)   # half volume

# Streaming music (one track at a time)
music = Teek::SDL2::Music.new("background.mp3")
music.play               # loops forever
music.volume = 64
music.pause
music.resume
music.stop
```

Audio capture is available for recording the mixed output to a WAV file:

```ruby
Teek::SDL2.start_audio_capture("/tmp/output.wav")
# ... play sounds and music ...
Teek::SDL2.stop_audio_capture
```

## Gamepad

Xbox-style controller input via SDL2's GameController API. Works with Xbox, PlayStation, Switch Pro, and most modern controllers out of the box.

```ruby
Teek::SDL2::Gamepad.init_subsystem

# Polling
gp = Teek::SDL2::Gamepad.first
if gp
  puts gp.name
  puts "A pressed: #{gp.button?(:a)}"
  puts "Left stick X: #{gp.axis(:left_x)}"
  gp.close
end

# Event-driven
Teek::SDL2::Gamepad.on_button { |id, btn, pressed| puts "#{btn} #{pressed}" }
Teek::SDL2::Gamepad.on_axis   { |id, axis, value| puts "#{axis}: #{value}" }
Teek::SDL2::Gamepad.on_added  { |idx| puts "Connected" }
Teek::SDL2::Gamepad.on_removed { |id| puts "Disconnected" }

# In your game loop
Teek::SDL2::Gamepad.poll_events
```

Buttons: `:a`, `:b`, `:x`, `:y`, `:back`, `:start`, `:guide`, `:dpad_up`, `:dpad_down`, `:dpad_left`, `:dpad_right`, `:left_shoulder`, `:right_shoulder`, `:left_stick`, `:right_stick`

Axes: `:left_x`, `:left_y`, `:right_x`, `:right_y`, `:trigger_left`, `:trigger_right`

```ruby
# Dead zone helper
Teek::SDL2::Gamepad.apply_dead_zone(gp.axis(:left_x))         # default threshold: 8000
Teek::SDL2::Gamepad.apply_dead_zone(gp.axis(:left_x), 4000)   # custom threshold

# Constants
Teek::SDL2::Gamepad::AXIS_MIN      # => -32768
Teek::SDL2::Gamepad::AXIS_MAX      # =>  32767
Teek::SDL2::Gamepad::TRIGGER_MIN   # =>  0
Teek::SDL2::Gamepad::TRIGGER_MAX   # =>  32767
Teek::SDL2::Gamepad::DEAD_ZONE     # =>  8000

# Virtual gamepad for testing without hardware
idx = Teek::SDL2::Gamepad.attach_virtual
gp = Teek::SDL2::Gamepad.open(idx)
gp.set_virtual_button(:a, true)
gp.set_virtual_axis(:left_x, 16000)
Teek::SDL2::Gamepad.poll_events
Teek::SDL2::Gamepad.detach_virtual
```

## Requirements

- [teek](https://github.com/jamescook/teek) >= 0.1.0
- SDL2 development headers
- SDL2_image development headers (for image loading)
- SDL2_ttf development headers (for text rendering)
- SDL2_mixer development headers (for audio)

### macOS

```sh
brew install sdl2 sdl2_image sdl2_ttf sdl2_mixer
```

### Ubuntu/Debian

```sh
apt-get install libsdl2-dev libsdl2-image-dev libsdl2-ttf-dev libsdl2-mixer-dev
```

### Windows

SDL2 headers are needed at compile time. See the [SDL2 download page](https://github.com/libsdl-org/SDL/releases) for development libraries.

## Installation

```sh
gem install teek-sdl2
```

Or in your Gemfile:

```ruby
gem 'teek-sdl2'
```

## License

MIT
