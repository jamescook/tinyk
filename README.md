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
