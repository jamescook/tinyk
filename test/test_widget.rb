# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestWidget < Minitest::Test
  include TeekTestHelper

  def test_create_widget_returns_widget
    assert_tk_app("create_widget returns Widget", method(:app_create_widget_returns_widget))
  end

  def test_auto_naming
    assert_tk_app("auto-naming produces sequential paths", method(:app_auto_naming))
  end

  def test_auto_naming_with_parent
    assert_tk_app("auto-naming nests under parent", method(:app_auto_naming_with_parent))
  end

  def test_explicit_path
    assert_tk_app("explicit path is used as-is", method(:app_explicit_path))
  end

  def test_to_s
    assert_tk_app("to_s returns path", method(:app_to_s))
  end

  def test_command_delegates
    assert_tk_app("command delegates to app", method(:app_command_delegates))
  end

  def test_destroy_and_exist
    assert_tk_app("destroy and exist? work", method(:app_destroy_and_exist))
  end

  def test_interop_with_app_command
    assert_tk_app("widget works with app.command", method(:app_interop))
  end

  def test_widget_tracking
    assert_tk_app("widget tracking works with create_widget", method(:app_widget_tracking))
  end

  def test_pack_returns_self
    assert_tk_app("pack returns self for chaining", method(:app_pack_returns_self))
  end

  def test_grid_returns_self
    assert_tk_app("grid returns self for chaining", method(:app_grid_returns_self))
  end

  def test_bind_and_unbind
    assert_tk_app("bind and unbind delegate to app", method(:app_bind_and_unbind))
  end

  def test_inspect
    assert_tk_app("inspect shows class and path", method(:app_inspect))
  end

  def test_equality
    assert_tk_app("equality by path", method(:app_equality))
  end

  # -- app methods --

  def app_create_widget_returns_widget
    btn = app.create_widget('ttk::button', text: 'Hi')
    raise "expected Widget, got #{btn.class}" unless btn.is_a?(Teek::Widget)
    raise "expected app" unless btn.app == app
  end

  def app_auto_naming
    b1 = app.create_widget('ttk::button', text: 'A')
    b2 = app.create_widget('ttk::button', text: 'B')
    lbl = app.create_widget(:label, text: 'C')
    raise "expected .ttkbtn1, got #{b1.path}" unless b1.path == '.ttkbtn1'
    raise "expected .ttkbtn2, got #{b2.path}" unless b2.path == '.ttkbtn2'
    raise "expected .lbl1, got #{lbl.path}" unless lbl.path == '.lbl1'
  end

  def app_auto_naming_with_parent
    frm = app.create_widget('ttk::frame')
    btn = app.create_widget('ttk::button', parent: frm, text: 'Hi')
    raise "expected .ttkfrm1, got #{frm.path}" unless frm.path == '.ttkfrm1'
    raise "expected .ttkfrm1.ttkbtn1, got #{btn.path}" unless btn.path == '.ttkfrm1.ttkbtn1'
  end

  def app_explicit_path
    frm = app.create_widget('ttk::frame', '.myframe')
    raise "expected .myframe, got #{frm.path}" unless frm.path == '.myframe'
  end

  def app_to_s
    btn = app.create_widget('ttk::button', text: 'Hi')
    raise "to_s should return path" unless btn.to_s == btn.path
  end

  def app_command_delegates
    btn = app.create_widget('ttk::button', text: 'Original')
    btn.command(:configure, text: 'Updated')
    result = btn.command(:cget, '-text')
    raise "expected Updated, got #{result}" unless result == 'Updated'
  end

  def app_destroy_and_exist
    btn = app.create_widget('ttk::button', text: 'Hi')
    raise "should exist after creation" unless btn.exist?
    btn.destroy
    raise "should not exist after destroy" if btn.exist?
  end

  def app_interop
    btn = app.create_widget('ttk::button', text: 'Hi')
    app.command(:pack, btn, pady: 10)
    result = app.tcl_eval("winfo manager #{btn}")
    raise "expected pack, got #{result}" unless result == 'pack'
  end

  def app_widget_tracking
    btn = app.create_widget('ttk::button', text: 'Hi')
    app.update
    raise "widget should be tracked" unless app.widgets[btn.path]
    btn.destroy
    app.update
    raise "widget should be untracked" if app.widgets[btn.path]
  end

  def app_pack_returns_self
    btn = app.create_widget('ttk::button', text: 'Hi')
    result = btn.pack(pady: 10)
    raise "pack should return self" unless result.equal?(btn)
  end

  def app_grid_returns_self
    frm = app.create_widget('ttk::frame')
    frm.pack
    btn = app.create_widget('ttk::button', parent: frm, text: 'Hi')
    result = btn.grid(row: 0, column: 0)
    raise "grid should return self" unless result.equal?(btn)
  end

  def app_bind_and_unbind
    btn = app.create_widget('ttk::button', text: 'Hi')
    btn.pack
    bound = false
    btn.bind('Enter') { bound = true }
    app.tcl_eval("event generate #{btn} <Enter>")
    app.update
    raise "bind should have fired" unless bound
    btn.unbind('Enter')
    bound = false
    app.tcl_eval("event generate #{btn} <Enter>")
    app.update
    raise "unbind should have cleared binding" if bound
  end

  def app_inspect
    btn = app.create_widget('ttk::button', text: 'Hi')
    raise "inspect should contain path" unless btn.inspect.include?(btn.path)
    raise "inspect should contain Teek::Widget" unless btn.inspect.include?('Teek::Widget')
  end

  def app_equality
    btn = app.create_widget('ttk::button', text: 'Hi')
    raise "should == string path" unless btn == btn.path
    raise "should == same widget" unless btn == Teek::Widget.new(app, btn.path)
    raise "hash should match" unless btn.hash == btn.path.hash
  end
end
