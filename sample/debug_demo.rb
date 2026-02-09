# frozen_string_literal: true

# Demo of the Teek debugger window.
# Run: ruby -Ilib sample/debug_demo.rb

require 'teek'

app = Teek::App.new(debug: true)

# Show the main app window
app.show
app.set_window_title('Debug Demo App')
app.set_window_geometry('300x200')

# Create some widgets
frame = app.create_widget('ttk::frame')
app.command(:pack, frame, fill: :both, expand: 1, padx: 10, pady: 10)

lbl = app.create_widget('ttk::label', parent: frame, text: 'Hello from the app')
app.command(:pack, lbl, pady: 5)

ent = app.create_widget('ttk::entry', parent: frame)
app.command(:pack, ent, pady: 5)

# Button that creates more widgets dynamically
dynamic_widgets = []
add_btn = app.create_widget('ttk::button', parent: frame, text: 'Add Widget',
  command: proc { |*|
    btn = app.create_widget('ttk::button', parent: frame, text: "Button #{dynamic_widgets.size + 1}")
    app.command(:pack, btn, pady: 2)
    dynamic_widgets << btn
  })
app.command(:pack, add_btn, pady: 5)

# Button to destroy last widget
rm_btn = app.create_widget('ttk::button', parent: frame, text: 'Remove Widget',
  command: proc { |*|
    widget = dynamic_widgets.pop
    widget&.destroy
  })
app.command(:pack, rm_btn, pady: 5)

app.mainloop
