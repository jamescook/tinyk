# frozen_string_literal: true

module Teek
  # CPU-side RGBA pixel buffer backed by Tk's "photo image" format.
  #
  # Despite the name, this is really a raw pixel manipulation surface.
  # Tk has two built-in image types: "bitmap" (two colors + transparency)
  # and "photo" (full-color, 32-bit RGBA). The naming reflects Tk's
  # image type system, not the contents — a "photo" is just Tk's term
  # for a full-color pixel buffer.
  #
  # Think of it as a software framebuffer: you pack RGBA bytes, write
  # them in bulk, read them back, zoom/subsample, and blit to a canvas
  # or label for display. All work is CPU-driven — there is no GPU
  # acceleration.
  #
  # @see https://www.tcl-lang.org/man/tcl9.0/TkCmd/photo.html Tk photo image type
  # @see https://www.tcl-lang.org/man/tcl9.0/TkCmd/bitmap.html Tk bitmap image type
  # @see https://www.tcl-lang.org/man/tcl9.0/TkCmd/image.html Tk image command (lists all types)
  #
  # The C methods ({#put_block}, {#get_image}, {#get_pixel}, etc.) call
  # Tk_PhotoPutBlock / Tk_PhotoGetImage directly, bypassing Tcl string
  # parsing for much better performance than the Tcl-level +$photo put+
  # command. Designed for games, visualizations, and real-time drawing.
  #
  # @example Create and fill with red pixels
  #   photo = Teek::Photo.new(app, width: 100, height: 100)
  #   red = ([255, 0, 0, 255].pack('CCCC')) * (100 * 100)
  #   photo.put_block(red, 100, 100)
  #
  # @example Read pixels back
  #   result = photo.get_image
  #   r, g, b, a = result[:data][0, 4].unpack('CCCC')
  #
  # @example Zoom a small sprite
  #   sprite = Teek::Photo.new(app, width: 64, height: 64)
  #   # ... fill sprite pixels ...
  #   dest = Teek::Photo.new(app, width: 192, height: 192)
  #   dest.put_zoomed_block(sprite_data, 64, 64, zoom_x: 3, zoom_y: 3)
  #
  # @see https://www.tcl-lang.org/man/tcl8.6/TkLib/FindPhoto.htm Tk Photo C API
  class Photo
    attr_reader :app, :name

    @counter = 0

    class << self
      # @api private
      def next_name
        @counter += 1
        "teek_photo#{@counter}"
      end
    end

    # Create a new photo image.
    #
    # @param app [Teek::App] the application instance
    # @param name [String, nil] Tcl image name (auto-generated if nil)
    # @param width [Integer, nil] image width in pixels
    # @param height [Integer, nil] image height in pixels
    # @param file [String, nil] path to an image file to load
    # @param data [String, nil] base64-encoded image data
    # @param format [String, nil] image format (e.g. "png", "gif")
    # @param palette [String, nil] palette specification
    # @param gamma [Float, nil] gamma correction value
    def initialize(app, name: nil, width: nil, height: nil,
                   file: nil, data: nil, format: nil, palette: nil, gamma: nil)
      @app = app
      @name = name || self.class.next_name

      kwargs = {}
      kwargs[:width] = width if width
      kwargs[:height] = height if height
      kwargs[:file] = file if file
      kwargs[:data] = data if data
      kwargs[:format] = format if format
      kwargs[:palette] = palette if palette
      kwargs[:gamma] = gamma if gamma

      @app.command(:image, :create, :photo, @name, **kwargs)
    end

    # Write RGBA pixel data to the image.
    #
    # @param pixel_data [String] binary string, 4 bytes (RGBA) per pixel
    # @param width [Integer] width of the pixel block
    # @param height [Integer] height of the pixel block
    # @param x [Integer] destination X offset
    # @param y [Integer] destination Y offset
    # @param format [:rgba, :argb] pixel format
    # @param composite [:set, :overlay] compositing rule
    # @return [self]
    def put_block(pixel_data, width, height, x: 0, y: 0, format: :rgba, composite: :set)
      opts = { x: x, y: y, format: format, composite: composite }
      @app.interp.photo_put_block(@name, pixel_data, width, height, opts)
      self
    end

    # Write RGBA pixel data with zoom and subsample.
    #
    # Zoom replicates each pixel (zoom=3 makes each source pixel 3x3).
    # Subsample skips source pixels (subsample=2 takes every other pixel).
    #
    # @param pixel_data [String] binary string, 4 bytes (RGBA) per pixel
    # @param width [Integer] source width in pixels
    # @param height [Integer] source height in pixels
    # @param x [Integer] destination X offset
    # @param y [Integer] destination Y offset
    # @param zoom_x [Integer] horizontal zoom factor
    # @param zoom_y [Integer] vertical zoom factor
    # @param subsample_x [Integer] horizontal subsample factor
    # @param subsample_y [Integer] vertical subsample factor
    # @param format [:rgba, :argb] pixel format
    # @param composite [:set, :overlay] compositing rule
    # @return [self]
    def put_zoomed_block(pixel_data, width, height,
                         x: 0, y: 0, zoom_x: 1, zoom_y: 1,
                         subsample_x: 1, subsample_y: 1,
                         format: :rgba, composite: :set)
      opts = {
        x: x, y: y,
        zoom_x: zoom_x, zoom_y: zoom_y,
        subsample_x: subsample_x, subsample_y: subsample_y,
        format: format, composite: composite
      }
      @app.interp.photo_put_zoomed_block(@name, pixel_data, width, height, opts)
      self
    end

    # Read pixel data from the image.
    #
    # @param x [Integer] source X offset
    # @param y [Integer] source Y offset
    # @param width [Integer, nil] region width (nil for full image)
    # @param height [Integer, nil] region height (nil for full image)
    # @param unpack [Boolean] if true, return flat array of integers instead of binary string
    # @return [Hash] +{ data: String, width: Integer, height: Integer }+ or
    #   +{ pixels: Array<Integer>, width: Integer, height: Integer }+ if unpack is true
    def get_image(x: nil, y: nil, width: nil, height: nil, unpack: false)
      opts = { unpack: unpack }
      opts[:x] = x if x
      opts[:y] = y if y
      opts[:width] = width if width
      opts[:height] = height if height
      @app.interp.photo_get_image(@name, opts)
    end

    # Read a single pixel.
    #
    # @param x [Integer] X coordinate
    # @param y [Integer] Y coordinate
    # @return [Array<Integer>] [r, g, b, a] values (0-255)
    def get_pixel(x, y)
      @app.interp.photo_get_pixel(@name, x, y)
    end

    # Get image dimensions.
    #
    # @return [Array<Integer>] [width, height]
    def get_size
      @app.interp.photo_get_size(@name)
    end

    # Set image dimensions. May crop or add transparent pixels.
    #
    # @param width [Integer] new width
    # @param height [Integer] new height
    # @return [self]
    def set_size(width, height)
      @app.interp.photo_set_size(@name, width, height)
      self
    end

    # Expand image to at least the given dimensions. Will not shrink.
    #
    # @note Has no effect on photos created with explicit +width:+ / +height:+
    #   options. Only works on auto-sized photos (those whose size was set by
    #   writing pixel data). This is a Tk limitation.
    #
    # @param width [Integer] minimum width
    # @param height [Integer] minimum height
    # @return [self]
    def expand(width, height)
      @app.interp.photo_expand(@name, width, height)
      self
    end

    # Clear the image to fully transparent.
    #
    # @return [self]
    def blank
      @app.interp.photo_blank(@name)
      self
    end

    alias clear blank

    # Delete this photo image and free its resources.
    #
    # @return [void]
    def delete
      @app.tcl_eval("image delete #{@name}")
    end

    # Check if this photo image still exists.
    #
    # @return [Boolean]
    def exist?
      @app.tcl_eval("image type #{@name}") == 'photo'
    rescue Teek::TclError
      false
    end

    # @return [String] the Tcl image name
    def to_s
      @name
    end

    def inspect
      "#<Teek::Photo #{@name}>"
    end

    def ==(other)
      other.is_a?(Photo) ? @name == other.name : @name == other.to_s
    end
    alias eql? ==

    def hash
      @name.hash
    end
  end
end
