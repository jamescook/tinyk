# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestPhoto < Minitest::Test
  include TeekTestHelper

  # ===========================================
  # Construction
  # ===========================================

  def test_auto_naming
    assert_tk_app("Photo auto-generates unique names") do
      p1 = Teek::Photo.new(app, width: 1, height: 1)
      p2 = Teek::Photo.new(app, width: 1, height: 1)
      refute_equal p1.name, p2.name
      assert_match(/\Ateek_photo\d+\z/, p1.name)
      assert_match(/\Ateek_photo\d+\z/, p2.name)
      p1.delete
      p2.delete
    end
  end

  def test_explicit_name
    assert_tk_app("Photo accepts explicit name") do
      p = Teek::Photo.new(app, name: 'my_test_photo', width: 10, height: 10)
      assert_equal 'my_test_photo', p.name
      assert_equal 'my_test_photo', p.to_s
      p.delete
    end
  end

  def test_constructor_with_dimensions
    assert_tk_app("Photo constructor sets dimensions") do
      p = Teek::Photo.new(app, width: 42, height: 17)
      w, h = p.get_size
      assert_equal 42, w
      assert_equal 17, h
      p.delete
    end
  end

  def test_exist_and_delete
    assert_tk_app("Photo exist? and delete") do
      p = Teek::Photo.new(app, width: 5, height: 5)
      assert p.exist?, "photo should exist after creation"
      p.delete
      refute p.exist?, "photo should not exist after delete"
    end
  end

  def test_inspect
    assert_tk_app("Photo inspect") do
      p = Teek::Photo.new(app, name: 'inspect_test', width: 1, height: 1)
      assert_equal '#<Teek::Photo inspect_test>', p.inspect
      p.delete
    end
  end

  # ===========================================
  # put_block + get_image round-trip
  # ===========================================

  def test_put_block_basic
    assert_tk_app("put_block writes pixels, get_image reads them back") do
      p = Teek::Photo.new(app, width: 10, height: 10)

      red_pixel = [255, 0, 0, 255].pack('CCCC')
      p.put_block(red_pixel * 100, 10, 10)

      result = p.get_image
      assert_equal 10, result[:width]
      assert_equal 10, result[:height]
      assert_equal 400, result[:data].bytesize

      # Check first pixel
      r, g, b, a = result[:data][0, 4].unpack('CCCC')
      assert_equal 255, r
      assert_equal 0, g
      assert_equal 0, b
      assert_equal 255, a

      # Check last pixel
      r, g, b, a = result[:data][-4, 4].unpack('CCCC')
      assert_equal 255, r
      assert_equal 0, g
      assert_equal 0, b
      assert_equal 255, a

      p.delete
    end
  end

  def test_put_block_with_offset
    assert_tk_app("put_block with offset writes to correct region") do
      p = Teek::Photo.new(app, width: 20, height: 20)

      # Fill with black
      black = [0, 0, 0, 255].pack('CCCC') * 400
      p.put_block(black, 20, 20)

      # Write 5x5 green block at (10, 10)
      green = [0, 255, 0, 255].pack('CCCC') * 25
      p.put_block(green, 5, 5, x: 10, y: 10)

      # Black outside the green block
      pixel = p.get_pixel(5, 5)
      assert_equal [0, 0, 0, 255], pixel

      # Green inside the block
      pixel = p.get_pixel(12, 12)
      assert_equal [0, 255, 0, 255], pixel

      # Edge of green block
      pixel = p.get_pixel(10, 10)
      assert_equal [0, 255, 0, 255], pixel

      # Just outside green block
      pixel = p.get_pixel(9, 10)
      assert_equal [0, 0, 0, 255], pixel

      p.delete
    end
  end

  def test_put_block_returns_self
    assert_tk_app("put_block returns self for chaining") do
      p = Teek::Photo.new(app, width: 2, height: 2)
      data = [255, 0, 0, 255].pack('CCCC') * 4
      result = p.put_block(data, 2, 2)
      assert_equal p.name, result.name
      p.delete
    end
  end

  # ===========================================
  # Validation
  # ===========================================

  def test_put_block_size_mismatch
    assert_tk_app("put_block rejects wrong data size") do
      p = Teek::Photo.new(app, width: 10, height: 10)

      err = assert_raises(ArgumentError) do
        p.put_block("too short", 10, 10)
      end
      assert_includes err.message, "size mismatch"

      p.delete
    end
  end

  def test_put_block_zero_dimensions
    assert_tk_app("put_block rejects zero dimensions") do
      p = Teek::Photo.new(app, width: 10, height: 10)

      err = assert_raises(ArgumentError) do
        p.put_block("", 0, 10)
      end
      assert_includes err.message, "positive"

      p.delete
    end
  end

  # ===========================================
  # Transparency
  # ===========================================

  def test_put_block_transparency
    assert_tk_app("put_block handles transparent pixels") do
      p = Teek::Photo.new(app, width: 10, height: 10)

      # Write fully transparent red pixels
      transparent = [255, 0, 0, 0].pack('CCCC') * 100
      p.put_block(transparent, 10, 10)

      pixel = p.get_pixel(5, 5)
      assert_equal 0, pixel[3], "alpha should be 0 (transparent)"
      assert_equal 255, pixel[0], "red channel should be preserved"

      p.delete
    end
  end

  # ===========================================
  # ARGB format
  # ===========================================

  def test_put_block_argb_format
    assert_tk_app("put_block ARGB format maps channels correctly") do
      p = Teek::Photo.new(app, width: 1, height: 1)

      # ARGB as little-endian 0xAARRGGBB: bytes are [B, G, R, A]
      argb_pixel = [0, 255, 0, 255].pack('CCCC')  # B=0, G=255, R=0, A=255
      p.put_block(argb_pixel, 1, 1, format: :argb)

      # Read back - should be R=0, G=255, B=0, A=255 (green)
      pixel = p.get_pixel(0, 0)
      assert_equal [0, 255, 0, 255], pixel

      p.delete
    end
  end

  def test_put_block_argb_red
    assert_tk_app("put_block ARGB red pixel") do
      p = Teek::Photo.new(app, width: 1, height: 1)

      # ARGB little-endian for red: B=0, G=0, R=255, A=255
      argb_pixel = [0, 0, 255, 255].pack('CCCC')
      p.put_block(argb_pixel, 1, 1, format: :argb)

      pixel = p.get_pixel(0, 0)
      assert_equal [255, 0, 0, 255], pixel

      p.delete
    end
  end

  # ===========================================
  # Composite rules
  # ===========================================

  def test_put_block_composite_set_overwrites
    assert_tk_app("composite :set overwrites existing pixels") do
      p = Teek::Photo.new(app, width: 1, height: 1)

      # Write opaque red
      p.put_block([255, 0, 0, 255].pack('CCCC'), 1, 1)

      # Overwrite with opaque blue using :set
      p.put_block([0, 0, 255, 255].pack('CCCC'), 1, 1, composite: :set)

      pixel = p.get_pixel(0, 0)
      assert_equal [0, 0, 255, 255], pixel

      p.delete
    end
  end

  def test_put_block_composite_overlay_blends
    assert_tk_app("composite :overlay alpha-blends over existing") do
      p = Teek::Photo.new(app, width: 1, height: 1)

      # Write opaque red background
      p.put_block([255, 0, 0, 255].pack('CCCC'), 1, 1)

      # Overlay 50% transparent green
      p.put_block([0, 255, 0, 128].pack('CCCC'), 1, 1, composite: :overlay)

      # Result should be a blend - not pure red, not pure green
      pixel = p.get_pixel(0, 0)
      # With overlay compositing, the green should mix with red
      # Exact values depend on Tk's blending, but red < 255 and green > 0
      assert pixel[0] < 255, "red channel should be reduced by blending (got #{pixel[0]})"
      assert pixel[1] > 0, "green channel should be present from overlay (got #{pixel[1]})"

      p.delete
    end
  end

  # ===========================================
  # put_zoomed_block
  # ===========================================

  def test_put_zoomed_block_basic
    assert_tk_app("put_zoomed_block 3x zoom") do
      p = Teek::Photo.new(app, width: 30, height: 30)

      # 10x10 red source
      red = [255, 0, 0, 255].pack('CCCC') * 100
      p.put_zoomed_block(red, 10, 10, zoom_x: 3, zoom_y: 3)

      # All positions should be red
      [[0, 0], [15, 15], [29, 29]].each do |x, y|
        pixel = p.get_pixel(x, y)
        assert_equal [255, 0, 0, 255], pixel, "expected red at (#{x},#{y})"
      end

      p.delete
    end
  end

  def test_put_zoomed_block_asymmetric
    assert_tk_app("put_zoomed_block asymmetric zoom") do
      # 1x1 source, zoom_x=4, zoom_y=2 → fills 4x2 region
      p = Teek::Photo.new(app, width: 10, height: 10)

      # Fill with black first
      p.put_block([0, 0, 0, 255].pack('CCCC') * 100, 10, 10)

      # 1x1 blue pixel, zoom 4x2
      blue = [0, 0, 255, 255].pack('CCCC')
      p.put_zoomed_block(blue, 1, 1, zoom_x: 4, zoom_y: 2)

      # Blue in zoomed region
      assert_equal [0, 0, 255, 255], p.get_pixel(0, 0)
      assert_equal [0, 0, 255, 255], p.get_pixel(3, 0)
      assert_equal [0, 0, 255, 255], p.get_pixel(0, 1)
      assert_equal [0, 0, 255, 255], p.get_pixel(3, 1)

      # Black outside zoomed region
      assert_equal [0, 0, 0, 255], p.get_pixel(4, 0)
      assert_equal [0, 0, 0, 255], p.get_pixel(0, 2)

      p.delete
    end
  end

  def test_put_zoomed_block_returns_self
    assert_tk_app("put_zoomed_block returns self") do
      p = Teek::Photo.new(app, width: 4, height: 4)
      data = [255, 0, 0, 255].pack('CCCC')
      result = p.put_zoomed_block(data, 1, 1, zoom_x: 4, zoom_y: 4)
      assert_equal p.name, result.name
      p.delete
    end
  end

  # ===========================================
  # get_image
  # ===========================================

  def test_get_image_unpack
    assert_tk_app("get_image unpack returns integer array") do
      p = Teek::Photo.new(app, width: 2, height: 1)

      # Red then green
      data = [255, 0, 0, 255, 0, 255, 0, 255].pack('C*')
      p.put_block(data, 2, 1)

      result = p.get_image(unpack: true)
      assert_equal 2, result[:width]
      assert_equal 1, result[:height]
      assert_nil result[:data], "unpack mode should not include :data"

      pixels = result[:pixels]
      assert_equal 8, pixels.size

      # First pixel: red
      assert_equal [255, 0, 0, 255], pixels[0, 4]
      # Second pixel: green
      assert_equal [0, 255, 0, 255], pixels[4, 4]

      p.delete
    end
  end

  def test_get_image_region
    assert_tk_app("get_image reads a sub-region") do
      p = Teek::Photo.new(app, width: 20, height: 20)

      # Fill with black
      p.put_block([0, 0, 0, 255].pack('CCCC') * 400, 20, 20)

      # Put green in bottom-right 10x10
      p.put_block([0, 255, 0, 255].pack('CCCC') * 100, 10, 10, x: 10, y: 10)

      # Read green quadrant
      result = p.get_image(x: 10, y: 10, width: 10, height: 10)
      assert_equal 10, result[:width]
      assert_equal 10, result[:height]
      r, g, b, a = result[:data][0, 4].unpack('CCCC')
      assert_equal [0, 255, 0, 255], [r, g, b, a]

      # Read black quadrant
      result = p.get_image(x: 0, y: 0, width: 10, height: 10)
      r, g, b, a = result[:data][0, 4].unpack('CCCC')
      assert_equal [0, 0, 0, 255], [r, g, b, a]

      p.delete
    end
  end

  # ===========================================
  # get_pixel
  # ===========================================

  def test_get_pixel
    assert_tk_app("get_pixel reads exact RGBA values") do
      p = Teek::Photo.new(app, width: 3, height: 1)

      # Red, green, blue pixels
      data = [255, 0, 0, 255, 0, 255, 0, 200, 0, 0, 255, 128].pack('C*')
      p.put_block(data, 3, 1)

      assert_equal [255, 0, 0, 255], p.get_pixel(0, 0)
      assert_equal [0, 255, 0, 200], p.get_pixel(1, 0)
      assert_equal [0, 0, 255, 128], p.get_pixel(2, 0)

      p.delete
    end
  end

  def test_get_pixel_out_of_bounds
    assert_tk_app("get_pixel rejects out-of-bounds coordinates") do
      p = Teek::Photo.new(app, width: 5, height: 5)
      p.put_block([0, 0, 0, 255].pack('CCCC') * 25, 5, 5)

      err = assert_raises(ArgumentError) do
        p.get_pixel(5, 0)
      end
      assert_includes err.message, "outside image bounds"

      err = assert_raises(ArgumentError) do
        p.get_pixel(0, 5)
      end
      assert_includes err.message, "outside image bounds"

      p.delete
    end
  end

  # ===========================================
  # get_size
  # ===========================================

  def test_get_size
    assert_tk_app("get_size returns correct dimensions") do
      [[10, 10], [100, 50], [1, 200]].each do |w, h|
        p = Teek::Photo.new(app, width: w, height: h)
        assert_equal [w, h], p.get_size
        p.delete
      end
    end
  end

  # ===========================================
  # set_size
  # ===========================================

  def test_set_size
    assert_tk_app("set_size changes dimensions") do
      p = Teek::Photo.new(app, width: 10, height: 10)
      assert_equal [10, 10], p.get_size

      p.set_size(20, 30)
      assert_equal [20, 30], p.get_size

      p.set_size(5, 5)
      assert_equal [5, 5], p.get_size

      p.delete
    end
  end

  def test_set_size_returns_self
    assert_tk_app("set_size returns self") do
      p = Teek::Photo.new(app, width: 10, height: 10)
      result = p.set_size(20, 20)
      assert_equal p.name, result.name
      p.delete
    end
  end

  # ===========================================
  # expand
  # ===========================================

  def test_expand_grows
    assert_tk_app("expand increases dimensions on auto-sized photo") do
      # Expand only works on photos WITHOUT explicit -width/-height
      # (Tk ignores expand when user declared a definite size)
      p = Teek::Photo.new(app)

      # Write 10x10 pixels - this sets the auto-size
      p.put_block([255, 0, 0, 255].pack('CCCC') * 100, 10, 10)
      assert_equal [10, 10], p.get_size

      p.expand(20, 30)
      w, h = p.get_size
      assert_operator w, :>=, 20, "width should be at least 20 after expand"
      assert_operator h, :>=, 30, "height should be at least 30 after expand"

      # Original pixels should still be intact
      pixel = p.get_pixel(5, 5)
      assert_equal [255, 0, 0, 255], pixel

      p.delete
    end
  end

  def test_expand_does_not_shrink
    assert_tk_app("expand does not shrink") do
      p = Teek::Photo.new(app)
      p.put_block([0, 0, 0, 255].pack('CCCC') * 400, 20, 20)

      p.expand(5, 5)
      w, h = p.get_size
      assert_operator w, :>=, 20
      assert_operator h, :>=, 20
      p.delete
    end
  end

  def test_expand_noop_on_explicit_size
    assert_tk_app("expand is no-op when photo has explicit -width/-height") do
      # Per Tk docs: expand has no effect if user declared a definite size
      p = Teek::Photo.new(app, width: 10, height: 10)
      p.expand(20, 20)
      assert_equal [10, 10], p.get_size
      p.delete
    end
  end

  def test_expand_returns_self
    assert_tk_app("expand returns self") do
      p = Teek::Photo.new(app, width: 10, height: 10)
      result = p.expand(20, 20)
      assert_equal p.name, result.name
      p.delete
    end
  end

  # ===========================================
  # blank / clear
  # ===========================================

  def test_blank
    assert_tk_app("blank clears image to transparent") do
      p = Teek::Photo.new(app, width: 10, height: 10)

      # Write red
      p.put_block([255, 0, 0, 255].pack('CCCC') * 100, 10, 10)
      pixel = p.get_pixel(5, 5)
      assert_equal [255, 0, 0, 255], pixel

      # Blank
      p.blank

      # After blank, pixels should be transparent (0,0,0,0)
      pixel = p.get_pixel(5, 5)
      assert_equal [0, 0, 0, 0], pixel

      p.delete
    end
  end

  def test_clear_alias
    assert_tk_app("clear is alias for blank") do
      p = Teek::Photo.new(app, width: 5, height: 5)
      p.put_block([255, 0, 0, 255].pack('CCCC') * 25, 5, 5)

      p.clear

      pixel = p.get_pixel(2, 2)
      assert_equal [0, 0, 0, 0], pixel

      p.delete
    end
  end

  def test_blank_returns_self
    assert_tk_app("blank returns self") do
      p = Teek::Photo.new(app, width: 5, height: 5)
      result = p.blank
      assert_equal p.name, result.name
      p.delete
    end
  end

  # ===========================================
  # Multi-color round-trip
  # ===========================================

  def test_multi_color_pattern
    assert_tk_app("write and read multi-color pattern") do
      p = Teek::Photo.new(app, width: 3, height: 2)

      # Row 1: red, green, blue
      # Row 2: white, black, yellow
      pixels = [
        255, 0, 0, 255,       # red
        0, 255, 0, 255,       # green
        0, 0, 255, 255,       # blue
        255, 255, 255, 255,   # white
        0, 0, 0, 255,         # black
        255, 255, 0, 255      # yellow
      ]
      p.put_block(pixels.pack('C*'), 3, 2)

      assert_equal [255, 0, 0, 255], p.get_pixel(0, 0)
      assert_equal [0, 255, 0, 255], p.get_pixel(1, 0)
      assert_equal [0, 0, 255, 255], p.get_pixel(2, 0)
      assert_equal [255, 255, 255, 255], p.get_pixel(0, 1)
      assert_equal [0, 0, 0, 255], p.get_pixel(1, 1)
      assert_equal [255, 255, 0, 255], p.get_pixel(2, 1)

      p.delete
    end
  end
end
