# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../test/tk_test_helper"

class TestViewport < Minitest::Test
  include TeekTestHelper

  def test_viewport_creates_renderer
    assert_tk_app("viewport should create a renderer") do
      require "teek/sdl2"

      app.show
      app.update
      viewport = Teek::SDL2::Viewport.new(app, width: 200, height: 200)
      assert_kind_of Teek::SDL2::Renderer, viewport.renderer
      refute viewport.destroyed?
      viewport.destroy
      assert viewport.destroyed?
    end
  end

  def test_viewport_render_block
    assert_tk_app("render block should clear and present") do
      require "teek/sdl2"

      app.show
      app.update
      viewport = Teek::SDL2::Viewport.new(app, width: 200, height: 200)
      viewport.pack

      viewport.render do |r|
        r.clear(255, 0, 0)
        r.fill_rect(10, 10, 50, 50, 0, 255, 0)
      end

      viewport.destroy
    end
  end

  def test_viewport_event_source_lifecycle
    assert_tk_app("event source tracks viewport count") do
      require "teek/sdl2"

      app.show
      app.update
      assert_empty Teek::SDL2._viewports

      v1 = Teek::SDL2::Viewport.new(app, width: 100, height: 100)
      assert_equal 1, Teek::SDL2._viewports.size

      v2 = Teek::SDL2::Viewport.new(app, width: 100, height: 100)
      assert_equal 2, Teek::SDL2._viewports.size

      v1.destroy
      assert_equal 1, Teek::SDL2._viewports.size

      v2.destroy
      assert_empty Teek::SDL2._viewports
    end
  end

  def test_viewport_texture_workflow
    assert_tk_app("create texture, update pixels, blit") do
      require "teek/sdl2"

      app.show
      app.update
      viewport = Teek::SDL2::Viewport.new(app, width: 256, height: 224)
      viewport.pack

      tex = viewport.renderer.create_texture(256, 224, :streaming)
      assert_equal 256, tex.width
      assert_equal 224, tex.height

      # Red pixels (ARGB8888)
      pixels = ([0xFF, 0xFF, 0x00, 0x00].pack('C*') * (256 * 224))
      tex.update(pixels)

      viewport.render do |r|
        r.clear(0, 0, 0)
        r.copy(tex)
      end

      tex.destroy
      viewport.destroy
    end
  end
end
