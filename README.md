# Teek

A Ruby interface to Tcl/Tk.

[API Documentation](https://jamescook.github.io/teek/)

## Quick Start

```ruby
require 'teek'

app = Teek::App.new

app.show
app.set_window_title('Hello Teek')

# Create widgets with the command helper — Ruby values are auto-quoted,
# symbols pass through bare, and procs become callbacks
app.command('ttk::label', '.lbl', text: 'Hello, world!')
app.command(:pack, '.lbl', pady: 10)

app.command('ttk::button', '.btn', text: 'Click me', command: proc {
  app.command('.lbl', :configure, text: 'Clicked!')
})
app.command(:pack, '.btn', pady: 10)

app.mainloop
```

## Widgets

`create_widget` returns a `Teek::Widget` — a thin wrapper that holds the widget path and provides convenience methods. Paths are auto-generated from the widget type.

```ruby
btn = app.create_widget('ttk::button', text: 'Click me')
btn.pack(pady: 10)

btn.command(:configure, text: 'Updated')  # widget subcommand
btn.destroy
```

Nest widgets under a parent:

```ruby
frame = app.create_widget('ttk::frame')
frame.pack(fill: :both, expand: 1)

label = app.create_widget('ttk::label', parent: frame, text: 'Hello')
label.pack(pady: 5)
```

Widgets work anywhere a path string is expected (via `to_s`):

```ruby
app.command(:pack, btn, pady: 10)       # equivalent to btn.pack(pady: 10)
app.tcl_eval("#{btn} configure -text New")  # string interpolation works
```

The raw `app.command` approach still works for cases where you don't need a wrapper:

```ruby
app.command('ttk::label', '.mylabel', text: 'Direct')
app.command(:pack, '.mylabel')
```

## Callbacks

Pass a `proc` to `command` and it becomes a Tcl callback automatically:

```ruby
app = Teek::App.new

app.command(:button, '.b', text: 'Click', command: proc { puts "clicked!" })
```

Use `bind` for event bindings with optional substitutions:

```ruby
app.bind('.b', 'Enter') { puts "hovered" }
app.bind('.c', 'Button-1', :x, :y) { |x, y| puts "#{x},#{y}" }
```

### Stopping event propagation

In `bind` handlers, you can stop an event from propagating to subsequent binding tags by throwing `:teek_break`:

```ruby
app.bind('.entry', 'KeyPress', :keysym) { |key|
  puts "handled #{key} - stop here"
  throw :teek_break
}
```

This is equivalent to Tcl's `break` command in a bind script.

Two other control flow signals are available for advanced use:

- `throw :teek_continue` - skip remaining bind scripts for this event (Tcl `continue`)
- `throw :teek_return` - return from the current Tcl proc (Tcl `return`)

### Errors in callbacks

If a callback raises a Ruby exception, it becomes a Tcl error. The exception message is preserved and can be caught on the Tcl side with `catch`.

## List operations

Convert between Ruby arrays and Tcl list strings:

```ruby
# Ruby array → Tcl list string (properly quoted)
Teek.make_list("hello world", "foo", "bar baz")
# => "{hello world} foo {bar baz}"

# Tcl list string → Ruby array
Teek.split_list("{hello world} foo {bar baz}")
# => ["hello world", "foo", "bar baz"]
```

Also available as `app.make_list` and `app.split_list` on an interpreter instance.

## Boolean conversion

Convert between Tcl boolean strings and Ruby booleans:

```ruby
# Tcl boolean string → Ruby bool
Teek.tcl_to_bool("yes")   # => true
Teek.tcl_to_bool("0")     # => false

# Ruby bool → Tcl boolean string
Teek.bool_to_tcl(true)    # => "1"
Teek.bool_to_tcl(nil)     # => "0"
```

`tcl_to_bool` recognizes all Tcl boolean forms: `true`/`false`, `yes`/`no`, `on`/`off`, `1`/`0`, and numeric values (case-insensitive).

## Tcl Packages

Load external Tcl packages (BWidget, tkimg, etc.):

```ruby
app.require_package('BWidget')
app.require_package('BWidget', '1.9')  # with version constraint
```

For packages in non-standard locations:

```ruby
app.add_package_path('/path/to/packages')
app.require_package('mypackage')
```

Query what's available:

```ruby
app.package_names          # => ["Tk", "BWidget", ...]
app.package_present?('Tk') # => true
app.package_versions('Tk') # => ["9.0.1"]
```

## Debugger

Pass `debug: true` to open a debugger window alongside your app:

```ruby
app = Teek::App.new(debug: true)
```

Or set the `TEEK_DEBUG` environment variable to enable it without changing code.

The debugger provides three tabs:

- **Widgets** — live tree of all widgets with a detail panel showing configuration
- **Variables** — all global Tcl variables with search/filter, auto-refreshes every second
- **Watches** — right-click or double-click a variable to watch it; tracks last 50 values with timestamps

The debugger runs in the same interpreter as your app (as a [Toplevel](https://www.tcl-lang.org/man/tcl8.6/TkCmd/toplevel.htm) window) and filters its own widgets from `app.widgets`.

## Background Work

Tk applications need to keep the UI responsive while doing CPU-intensive work. The `Teek.background_work` API runs work in a background Ractor with automatic UI integration.

**This API is designed for Ruby 4.x.** Ractors on Ruby 3.x lack shareable procs, making them impractical for our use case. A `:thread` mode exists but is rarely beneficial — Ruby threads share the GVL, so thread-based background work often performs *worse* than running inline unless the work involves non-blocking I/O.

```ruby
app = Teek::App.new
app.show
app.set_variable('::progress', 0)

log = app.create_widget(:text, width: 60, height: 10)
log.pack(fill: :both, expand: 1, padx: 10, pady: 5)

app.create_widget('ttk::progressbar', variable: '::progress', maximum: 100)
  .pack(fill: :x, padx: 10, pady: 5)

files = Dir.glob('**/*').select { |f| File.file?(f) }

task = Teek::BackgroundWork.new(app, files) do |t, data|
  # Background work goes here - this block cannot access Tk
  data.each_with_index do |file, i|
    t.check_pause
    hash = Digest::SHA256.file(file).hexdigest
    t.yield({ file: file, hash: hash, pct: (i + 1) * 100 / data.size })
  end
end.on_progress do |msg|
  # This block can access Tk
  log.command(:insert, :end, "#{msg[:file]}: #{msg[:hash]}\n")
  log.command(:see, :end)
  app.set_variable('::progress', msg[:pct])
end.on_done do
  # This block can also access Tk
  log.command(:insert, :end, "Done!\n")
end

# Control the task
task.pause   # Pause work (resumes at next t.check_pause)
task.resume  # Resume paused work
task.stop    # Stop completely
```

The work block runs in a background Ractor and cannot access Tk directly. Use `t.yield()` to send results to `on_progress`, which runs on the main thread where Tk is available. Callbacks (`on_progress`, `on_done`) can be chained in any order.

See [`sample/threading_demo.rb`](sample/threading_demo.rb) for a complete file hasher example.
