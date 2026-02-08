# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestDebugger < Minitest::Test
  include TeekTestHelper

  def test_debugger_creates_window
    assert_tk_app("debugger creates window", method(:app_debugger_creates_window))
  end

  def app_debugger_creates_window
    app = Teek::App.new(debug: true)
    raise "debugger not created" unless app.debugger
    raise "debugger interp missing" unless app.debugger.interp

    # Debugger toplevel should exist
    result = app.tcl_eval('winfo exists .teek_debug')
    raise "debugger window doesn't exist" unless result == "1"

    # Notebook should exist
    result = app.tcl_eval('winfo exists .teek_debug.nb')
    raise "notebook doesn't exist" unless result == "1"
  end

  def test_debugger_tracks_widgets
    assert_tk_app("debugger tracks widget creation", method(:app_debugger_tracks_widgets))
  end

  def app_debugger_tracks_widgets
    app = Teek::App.new(debug: true)

    # Create some widgets in the app
    app.tcl_eval('wm deiconify .')
    app.tcl_eval('ttk::frame .f')
    app.tcl_eval('ttk::button .f.btn -text Hello')
    app.update

    # Check that they appear in the debugger tree
    exists_f = app.tcl_eval('.teek_debug.nb.widgets.tree exists .f')
    raise "frame not in debugger tree" unless exists_f == "1"

    exists_btn = app.tcl_eval('.teek_debug.nb.widgets.tree exists .f.btn')
    raise "button not in debugger tree" unless exists_btn == "1"
  end

  def test_debugger_tracks_destroy
    assert_tk_app("debugger tracks widget destruction", method(:app_debugger_tracks_destroy))
  end

  def app_debugger_tracks_destroy
    app = Teek::App.new(debug: true)

    app.tcl_eval('wm deiconify .')
    app.tcl_eval('ttk::button .btn -text Bye')
    app.update

    exists = app.tcl_eval('.teek_debug.nb.widgets.tree exists .btn')
    raise "button should be in tree" unless exists == "1"

    app.tcl_eval('destroy .btn')
    app.update

    exists = app.tcl_eval('.teek_debug.nb.widgets.tree exists .btn')
    raise "button should be removed from tree" unless exists == "0"
  end

  def test_debugger_show_hide
    assert_tk_app("debugger show/hide", method(:app_debugger_show_hide))
  end

  def app_debugger_show_hide
    app = Teek::App.new(debug: true)

    app.debugger.hide
    state = app.tcl_eval('wm state .teek_debug')
    raise "expected withdrawn, got #{state}" unless state == "withdrawn"

    app.debugger.show
    app.update
    state = app.tcl_eval('wm state .teek_debug')
    raise "expected normal, got #{state}" unless state == "normal"
  end

  def test_debugger_widgets_not_tracked
    assert_tk_app("debugger widgets filtered", method(:app_debugger_widgets_not_tracked))
  end

  def app_debugger_widgets_not_tracked
    app = Teek::App.new(debug: true)

    # Debugger widgets should not appear in app.widgets
    app.widgets.each_key do |path|
      raise "debugger widget #{path} leaked into app.widgets" if path.start_with?('.teek_debug')
    end
  end
end
