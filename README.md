# Teek

A Ruby interface to Tcl/Tk.

## Callbacks

Register Ruby procs as Tcl callbacks using `app.register_callback`:

```ruby
app = Teek::App.new

cb = app.register_callback(proc { |*args|
  puts "clicked!"
})
app.tcl_eval("button .b -text Click -command {ruby_callback #{cb}}")
```

### Stopping event propagation

In `bind` handlers, you can stop an event from propagating to subsequent binding tags by throwing `:teek_break`:

```ruby
cb = app.register_callback(proc { |*|
  puts "handled - stop here"
  throw :teek_break
})
app.tcl_eval("bind .entry <Key-Return> {ruby_callback #{cb}}")
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

The debugger runs in the same interpreter as your app (as a Toplevel window) and filters its own widgets from `app.widgets`.
