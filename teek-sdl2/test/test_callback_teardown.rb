# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../test/tk_test_helper"

class TestCallbackTeardown < Minitest::Test
  include TeekTestHelper

  def test_viewport_destroy_no_bgerror
    assert_tk_app("destroying viewport does not trigger bgerror") do
      require "teek/sdl2"
      app.show
      app.update

      # Capture any bgerror that Tcl would normally show in a dialog
      app.set_variable("_bgerror_msg", "")
      app.tcl_eval('proc bgerror {msg} { set ::_bgerror_msg $msg }')

      vp = Teek::SDL2::Viewport.new(app, width: 200, height: 200)
      vp.pack
      app.update

      vp.render do |r|
        r.clear(30, 30, 30)
        r.fill(20, 20, 80, 60, r: 200, g: 50, b: 50)
      end

      vp.destroy
      app.update

      err = app.get_variable("_bgerror_msg")
      assert_equal "", err, "bgerror fired during viewport destroy: #{err}"
    end
  end
end
