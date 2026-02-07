# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestWidgetTracking < Minitest::Test
  include TinyKTestHelper

  def test_tracks_created_widgets
    assert_tk_app("should track created widgets", method(:app_tracks_created))
  end

  def app_tracks_created
    app.command(:button, ".b", text: "hello")
    app.command(:label, ".l", text: "world")
    app.command(:frame, ".f")

    raise "expected 3 widgets, got #{app.widgets.size}" unless app.widgets.size == 3
    raise "missing .b" unless app.widgets[".b"]
    raise ".b class wrong" unless app.widgets[".b"][:class] == "Button"
    raise ".l class wrong" unless app.widgets[".l"][:class] == "Label"
    raise ".f class wrong" unless app.widgets[".f"][:class] == "Frame"
  end

  def test_tracks_destroy
    assert_tk_app("should remove destroyed widgets", method(:app_tracks_destroy))
  end

  def app_tracks_destroy
    app.command(:button, ".b", text: "hello")
    app.command(:label, ".l", text: "world")
    raise "expected 2 widgets" unless app.widgets.size == 2

    app.tcl_eval("destroy .b")
    raise "expected 1 widget after destroy" unless app.widgets.size == 1
    raise ".b should be gone" if app.widgets[".b"]
    raise ".l should remain" unless app.widgets[".l"]
  end

  def test_tracking_disabled
    assert_tk_app("should not track when disabled", method(:app_tracking_disabled))
  end

  def app_tracking_disabled
    # Create a second app with tracking off
    app2 = TinyK::App.new(track_widgets: false)
    app2.tcl_eval("button .b -text hello")
    raise "expected empty widgets" unless app2.widgets.empty?
  end
end
