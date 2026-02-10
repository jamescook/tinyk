# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../test/tk_test_helper"

class TestInput < Minitest::Test
  include TeekTestHelper

  def test_key_state_tracking
    assert_tk_app("key_down? tracks KeyPress/KeyRelease") do
      require "teek/sdl2"

      app.show
      app.update
      viewport = Teek::SDL2::Viewport.new(app, width: 200, height: 200)
      fp = viewport.frame.path
      app.tcl_eval("focus -force #{fp}")
      app.update

      assert_empty viewport.keys_down

      app.tcl_eval("event generate #{fp} <KeyPress> -keysym a")
      app.update
      assert viewport.key_down?('a')
      assert_includes viewport.keys_down, 'a'

      app.tcl_eval("event generate #{fp} <KeyRelease> -keysym a")
      app.update
      refute viewport.key_down?('a')
      assert_empty viewport.keys_down

      viewport.destroy
    end
  end

  def test_multiple_keys_down
    assert_tk_app("multiple keys tracked simultaneously") do
      require "teek/sdl2"

      app.show
      app.update
      viewport = Teek::SDL2::Viewport.new(app, width: 200, height: 200)
      fp = viewport.frame.path
      app.tcl_eval("focus -force #{fp}")
      app.update

      app.tcl_eval("event generate #{fp} <KeyPress> -keysym Left")
      app.update
      app.tcl_eval("event generate #{fp} <KeyPress> -keysym space")
      app.update

      assert viewport.key_down?('left')
      assert viewport.key_down?('space')
      assert_equal 2, viewport.keys_down.size

      app.tcl_eval("event generate #{fp} <KeyRelease> -keysym Left")
      app.update
      refute viewport.key_down?('left')
      assert viewport.key_down?('space')

      viewport.destroy
    end
  end

  def test_key_down_case_insensitive
    assert_tk_app("key_down? is case insensitive") do
      require "teek/sdl2"

      app.show
      app.update
      viewport = Teek::SDL2::Viewport.new(app, width: 200, height: 200)
      fp = viewport.frame.path
      app.tcl_eval("focus -force #{fp}")
      app.update

      app.tcl_eval("event generate #{fp} <KeyPress> -keysym Return")
      app.update
      assert viewport.key_down?('return')
      assert viewport.key_down?('Return')

      viewport.destroy
    end
  end

  def test_focus
    assert_tk_app("focus gives keyboard focus to viewport") do
      require "teek/sdl2"

      app.show
      app.update
      viewport = Teek::SDL2::Viewport.new(app, width: 200, height: 200)
      app.tcl_eval("focus -force #{viewport.frame.path}")
      app.update

      focused = app.tcl_eval('focus')
      assert_equal viewport.frame.path, focused

      viewport.destroy
    end
  end

  def test_bind_callback
    assert_tk_app("bind delivers events via callback") do
      require "teek/sdl2"

      app.show
      app.update
      viewport = Teek::SDL2::Viewport.new(app, width: 200, height: 200)
      fp = viewport.frame.path
      app.tcl_eval("focus -force #{fp}")
      app.update

      received = nil
      viewport.bind('KeyPress', :keysym) { |k| received = k }

      app.tcl_eval("event generate #{fp} <KeyPress> -keysym z")
      app.update
      assert_equal 'z', received

      viewport.destroy
    end
  end
end

class TestFont < Minitest::Test
  include TeekTestHelper

  def test_font_load_and_render
    assert_tk_app("font renders text to texture") do
      require "teek/sdl2"

      app.show
      app.update
      font_path = File.join(File.dirname(__FILE__), '..', 'assets', 'JetBrainsMonoNL-Regular.ttf')
      viewport = Teek::SDL2::Viewport.new(app, width: 200, height: 200)
      font = viewport.renderer.load_font(font_path, 16)

      tex = font.render_text("Hello", 255, 255, 255)
      assert_kind_of Teek::SDL2::Texture, tex
      assert tex.width > 0
      assert tex.height > 0

      tex.destroy
      font.destroy
      assert font.destroyed?
      viewport.destroy
    end
  end

  def test_draw_text_convenience
    assert_tk_app("draw_text renders and blits in one call") do
      require "teek/sdl2"

      app.show
      app.update
      font_path = File.join(File.dirname(__FILE__), '..', 'assets', 'JetBrainsMonoNL-Regular.ttf')
      viewport = Teek::SDL2::Viewport.new(app, width: 200, height: 200)
      font = viewport.renderer.load_font(font_path, 16)

      viewport.render do |r|
        r.clear(0, 0, 0)
        r.draw_text(10, 10, "Test", font: font, r: 255, g: 0, b: 0)
      end

      font.destroy
      viewport.destroy
    end
  end

  def test_font_bad_path_raises
    assert_tk_app("font raises on bad path") do
      require "teek/sdl2"

      app.show
      app.update
      viewport = Teek::SDL2::Viewport.new(app, width: 200, height: 200)

      assert_raises(RuntimeError) do
        viewport.renderer.load_font("/nonexistent/font.ttf", 16)
      end

      viewport.destroy
    end
  end
end
