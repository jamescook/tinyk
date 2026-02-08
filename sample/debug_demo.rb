# frozen_string_literal: true

# Demo of the Teek debugger window.
# Run: ruby -Ilib sample/debug_demo.rb

require 'teek'

app = Teek::App.new(debug: true)

# Show the main app window
app.tcl_eval('wm deiconify .')
app.tcl_eval('wm title . "Debug Demo App"')
app.tcl_eval('wm geometry . 300x200')

# Create some widgets
app.tcl_eval('ttk::frame .f')
app.tcl_eval('pack .f -fill both -expand 1 -padx 10 -pady 10')

app.tcl_eval('ttk::label .f.lbl -text "Hello from the app"')
app.tcl_eval('pack .f.lbl -pady 5')

app.tcl_eval('ttk::entry .f.ent')
app.tcl_eval('pack .f.ent -pady 5')

# Button that creates more widgets dynamically
counter = 0
cb = app.register_callback(proc { |*|
  counter += 1
  app.tcl_eval("ttk::button .f.btn#{counter} -text {Button #{counter}}")
  app.tcl_eval("pack .f.btn#{counter} -pady 2")
})
app.tcl_eval("ttk::button .f.add -text {Add Widget} -command {ruby_callback #{cb}}")
app.tcl_eval('pack .f.add -pady 5')

# Button to destroy last widget
rm_cb = app.register_callback(proc { |*|
  if counter > 0
    app.tcl_eval("destroy .f.btn#{counter}")
    counter -= 1
  end
})
app.tcl_eval("ttk::button .f.rm -text {Remove Widget} -command {ruby_callback #{rm_cb}}")
app.tcl_eval('pack .f.rm -pady 5')

app.mainloop
