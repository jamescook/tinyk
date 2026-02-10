# frozen_string_literal: true

# Sparse storage for pixel data - only stores non-default pixels.
# Memory efficient for layers with limited drawing.
#
# Stores pixels as 4-byte binary strings to avoid pack/unpack overhead
# when interfacing with TkPhotoImage#put_block.
#
class SparsePixelBuffer
  # Default: fully transparent
  DEFAULT_PIXEL = "\x00\x00\x00\x00".b.freeze
  PIXEL_SIZE = 4

  attr_reader :width, :height, :default_pixel

  def initialize(width, height, default: DEFAULT_PIXEL)
    @width = width
    @height = height
    @default_pixel = default.frozen? ? default : default.dup.freeze
    @pixels = {}  # {linear_index => 4-byte binary string}
    @bbox = nil   # [min_x, min_y, max_x, max_y] or nil if empty
  end

  def get_pixel(x, y)
    return nil if out_of_bounds?(x, y)
    @pixels[y * @width + x] || @default_pixel
  end

  def set_pixel(x, y, rgba_bytes)
    return if out_of_bounds?(x, y)

    key = y * @width + x

    if rgba_bytes == @default_pixel
      @pixels.delete(key)
      recalculate_bbox if @pixels.empty? || bbox_edge?(x, y)
    else
      @pixels[key] = rgba_bytes.frozen? ? rgba_bytes : rgba_bytes.dup
      expand_bbox(x, y)
    end
  end

  # Set pixel from RGBA integers (convenience method)
  def set_rgba(x, y, r, g, b, a = 255)
    set_pixel(x, y, [r, g, b, a].pack('CCCC'))
  end

  # Get pixel as RGBA integers (convenience method)
  def get_rgba(x, y)
    pixel = get_pixel(x, y)
    pixel&.unpack('CCCC')
  end

  def empty?
    @pixels.empty?
  end

  def pixel_count
    @pixels.size
  end

  def bbox
    @bbox&.dup
  end

  # Returns [x, y, width, height] for the bounding box
  def bbox_xywh
    return nil unless @bbox
    [@bbox[0], @bbox[1], @bbox[2] - @bbox[0] + 1, @bbox[3] - @bbox[1] + 1]
  end

  # Materialize a region to a contiguous RGBA buffer for put_block
  def materialize(x: 0, y: 0, width: @width, height: @height)
    # Clamp to valid region
    x = x.clamp(0, @width - 1)
    y = y.clamp(0, @height - 1)
    width = [width, @width - x].min
    height = [height, @height - y].min

    # Allocate buffer filled with default pixel
    buffer = (@default_pixel * (width * height)).dup

    # Patch in non-default pixels
    @pixels.each do |key, rgba|
      px = key % @width
      py = key / @width

      # Skip if outside requested region
      next unless px >= x && px < x + width && py >= y && py < y + height

      # Calculate offset in output buffer
      offset = ((py - y) * width + (px - x)) * PIXEL_SIZE
      buffer[offset, PIXEL_SIZE] = rgba
    end

    buffer
  end

  # Materialize only the bounding box (returns nil if empty)
  def materialize_bbox
    return nil if empty? || @bbox.nil?
    bx, by, bw, bh = bbox_xywh
    materialize(x: bx, y: by, width: bw, height: bh)
  end

  # Resize the buffer, preserving pixels that fit within new bounds
  def resize(new_width, new_height)
    return if new_width == @width && new_height == @height

    new_pixels = {}
    @pixels.each do |key, rgba|
      x = key % @width
      y = key / @width
      next if x >= new_width || y >= new_height
      new_pixels[y * new_width + x] = rgba
    end

    @width = new_width
    @height = new_height
    @pixels = new_pixels
    recalculate_bbox
  end

  # Clear all pixels
  def clear
    @pixels.clear
    @bbox = nil
  end

  # Create a full copy
  def dup
    copy = SparsePixelBuffer.new(@width, @height, default: @default_pixel)
    copy.instance_variable_set(:@pixels, @pixels.dup)
    copy.instance_variable_set(:@bbox, @bbox&.dup)
    copy
  end

  # Memory usage estimate in bytes
  def memory_usage
    # Hash overhead (~40 bytes) + per-entry (~50 bytes: key + value + hash bucket)
    40 + (@pixels.size * 50)
  end

  # Density as fraction of total pixels
  def density
    @pixels.size.to_f / (@width * @height)
  end

  # Iterate over non-default pixels
  def each_pixel
    return enum_for(:each_pixel) unless block_given?

    @pixels.each do |key, rgba|
      x = key % @width
      y = key / @width
      yield x, y, rgba
    end
  end

  private

  def out_of_bounds?(x, y)
    x < 0 || x >= @width || y < 0 || y >= @height
  end

  def expand_bbox(x, y)
    if @bbox.nil?
      @bbox = [x, y, x, y]
    else
      @bbox[0] = x if x < @bbox[0]
      @bbox[1] = y if y < @bbox[1]
      @bbox[2] = x if x > @bbox[2]
      @bbox[3] = y if y > @bbox[3]
    end
  end

  def bbox_edge?(x, y)
    return false unless @bbox
    x == @bbox[0] || x == @bbox[2] || y == @bbox[1] || y == @bbox[3]
  end

  def recalculate_bbox
    if @pixels.empty?
      @bbox = nil
      return
    end

    min_x = min_y = Float::INFINITY
    max_x = max_y = -Float::INFINITY

    @pixels.each_key do |key|
      x = key % @width
      y = key / @width
      min_x = x if x < min_x
      max_x = x if x > max_x
      min_y = y if y < min_y
      max_y = y if y > max_y
    end

    @bbox = [min_x, min_y, max_x, max_y]
  end
end
