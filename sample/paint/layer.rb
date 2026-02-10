# frozen_string_literal: true

require_relative 'sparse_pixel_buffer'

# A drawing layer with both pixel (raster) and canvas item (vector) sub-layers.
#
# Pixels are stored sparsely for memory efficiency. The Teek::Photo is
# created lazily when first needed.
#
# Canvas items belonging to this layer are tracked so they can be
# shown/hidden together and properly ordered in the z-stack.
#
class Layer
  attr_reader :id, :name, :pixels, :items
  attr_accessor :visible, :opacity

  # White opaque pixel for background layer
  WHITE_PIXEL = "\xFF\xFF\xFF\xFF".b.freeze
  # Transparent pixel for overlay layers
  TRANSPARENT_PIXEL = "\x00\x00\x00\x00".b.freeze

  def initialize(app, canvas, width, height, name: "Layer", background: false)
    @id = object_id.to_s(16)
    @app = app
    @canvas = canvas
    @width = width
    @height = height
    @name = name
    @visible = true
    @opacity = 1.0

    # Pixel sub-layer (sparse storage)
    default = background ? WHITE_PIXEL : TRANSPARENT_PIXEL
    @pixels = SparsePixelBuffer.new(width, height, default: default)
    @background = background

    # For background layer, we need to fill initially
    if background
      # Don't actually store all pixels - the default handles it
      # Just mark that we need a photo
      @needs_photo = true
    end

    # Photo image for display (lazily created)
    @photo = nil
    @photo_item = nil

    # Canvas items belonging to this layer
    @items = []
  end

  def background?
    @background
  end

  # Ensure photo image exists and is on canvas
  def ensure_photo!
    return @photo if @photo

    @photo = Teek::Photo.new(@app, width: @width, height: @height)
    @photo_item = @app.command(@canvas, :create, :image, 0, 0,
                               image: @photo.name, anchor: :nw)

    # For background layer, fill with default color immediately
    if @background
      buffer = @pixels.default_pixel * (@width * @height)
      @photo.put_block(buffer, @width, @height)
    end

    @photo
  end

  # Update the photo display from pixel buffer
  def refresh_display
    return unless @visible

    if @pixels.empty? && !@background
      # Nothing to display, hide photo if it exists
      if @photo_item
        @app.command(@canvas, :itemconfigure, @photo_item, state: :hidden)
      end
      return
    end

    ensure_photo!
    @app.command(@canvas, :itemconfigure, @photo_item, state: :normal)

    if @background || @pixels.density > 0.25
      # Dense or background: update entire photo
      buffer = @pixels.materialize
      @photo.put_block(buffer, @width, @height)
    else
      # Sparse: only update bounding box region
      bbox = @pixels.bbox_xywh
      return unless bbox

      buffer = @pixels.materialize_bbox
      @photo.put_block(buffer, bbox[2], bbox[3], x: bbox[0], y: bbox[1])
    end
  end

  # Update just a region of the photo (for incremental updates)
  def refresh_region(x, y, width, height)
    return unless @visible
    ensure_photo!

    buffer = @pixels.materialize(x: x, y: y, width: width, height: height)
    @photo.put_block(buffer, width, height, x: x, y: y)
  end

  # Pixel operations (delegate to sparse buffer)
  def get_pixel(x, y)
    @pixels.get_pixel(x, y)
  end

  def set_pixel(x, y, rgba_bytes)
    @pixels.set_pixel(x, y, rgba_bytes)
  end

  def get_rgba(x, y)
    @pixels.get_rgba(x, y)
  end

  def set_rgba(x, y, r, g, b, a = 255)
    @pixels.set_rgba(x, y, r, g, b, a)
  end

  # Canvas item operations
  def add_item(item)
    @items << item
    item
  end

  def remove_item(item)
    @items.delete(item)
    @app.command(@canvas, :delete, item)
  end

  def clear_items
    @items.each { |item| @app.command(@canvas, :delete, item) }
    @items.clear
  end

  # Visibility
  def show
    @visible = true
    if @photo_item
      @app.command(@canvas, :itemconfigure, @photo_item, state: :normal)
    end
    @items.each { |item| @app.command(@canvas, :itemconfigure, item, state: :normal) }
  end

  def hide
    @visible = false
    if @photo_item
      @app.command(@canvas, :itemconfigure, @photo_item, state: :hidden)
    end
    @items.each { |item| @app.command(@canvas, :itemconfigure, item, state: :hidden) }
  end

  def toggle_visibility
    @visible ? hide : show
  end

  # Z-ordering - raise this layer above another
  def raise_above(other_layer)
    if other_layer.photo_item
      @app.command(@canvas, :raise, @photo_item, other_layer.photo_item) if @photo_item
    end
    # Raise all our items above their items
    other_top_item = other_layer.items.last
    if other_top_item
      @items.each { |item| @app.command(@canvas, :raise, item, other_top_item) }
    end
  end

  # Raise to top of canvas
  def raise_to_top
    @app.command(@canvas, :raise, @photo_item) if @photo_item
    @items.each { |item| @app.command(@canvas, :raise, item) }
  end

  # Lower to bottom of canvas
  def lower_to_bottom
    @items.reverse_each { |item| @app.command(@canvas, :lower, item) }
    @app.command(@canvas, :lower, @photo_item) if @photo_item
  end

  # Resize layer to new dimensions
  def resize(new_width, new_height)
    return if new_width == @width && new_height == @height

    @width = new_width
    @height = new_height
    @pixels.resize(new_width, new_height)

    if @photo
      @photo.set_size(new_width, new_height)
      refresh_display
    end
  end

  # Clear everything
  def clear
    @pixels.clear
    clear_items
    if @photo && @background
      # Reset background to default color
      buffer = @pixels.default_pixel * (@width * @height)
      @photo.put_block(buffer, @width, @height)
    elsif @photo
      # Clear to transparent
      if @photo_item
        @app.command(@canvas, :itemconfigure, @photo_item, state: :hidden)
      end
    end
  end

  # Memory usage
  def memory_usage
    pixels_mem = @pixels.memory_usage
    photo_mem = @photo ? (@width * @height * 4) : 0
    items_mem = @items.size * 100  # Rough estimate per item
    {
      pixels: pixels_mem,
      photo: photo_mem,
      items: items_mem,
      total: pixels_mem + photo_mem + items_mem
    }
  end

  # For undo system - snapshot current pixel state
  def snapshot_pixels
    @pixels.dup
  end

  # For undo system - restore pixel state
  def restore_pixels(snapshot)
    @pixels = snapshot.dup
    refresh_display
  end

  # Destroy the layer
  def destroy
    clear_items
    @app.command(@canvas, :delete, @photo_item) if @photo_item
    @photo&.delete
    @photo = nil
    @photo_item = nil
  end

  protected

  attr_reader :photo_item
end
