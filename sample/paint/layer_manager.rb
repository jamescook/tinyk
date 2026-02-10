# frozen_string_literal: true

require_relative 'layer'

# Manages a stack of layers for the paint application.
#
# Handles layer creation, ordering, and the concept of an "active" layer
# that receives drawing operations.
#
class LayerManager
  attr_reader :layers, :width, :height

  def initialize(app, canvas, width, height)
    @app = app
    @canvas = canvas
    @width = width
    @height = height
    @layers = []
    @active_index = 0

    # Create default background layer
    add_layer(name: "Background", background: true)
  end

  def active_layer
    @active_index ? @layers[@active_index] : nil
  end

  def active_layer=(layer)
    idx = @layers.index(layer)
    @active_index = idx if idx
  end

  def active_index
    @active_index
  end

  def active_index=(index)
    @active_index = index if index >= 0 && index < @layers.size
  end

  # Add a new layer at the top (or at specific index)
  def add_layer(name: nil, background: false, index: nil)
    name ||= "Layer #{@layers.size}"
    layer = Layer.new(@app, @canvas, @width, @height, name: name, background: background)

    if index
      @layers.insert(index, layer)
      # Adjust active index if needed
      @active_index += 1 if @active_index && index <= @active_index
    else
      @layers << layer
    end

    # New layer becomes active
    @active_index = @layers.index(layer)

    reorder_canvas_items
    layer
  end

  # Remove a layer
  def remove_layer(layer_or_index)
    layer = layer_or_index.is_a?(Layer) ? layer_or_index : @layers[layer_or_index]
    return nil unless layer
    return nil if layer.background? && @layers.size == 1  # Can't remove only background

    idx = @layers.index(layer)
    @layers.delete(layer)
    layer.destroy

    # Adjust active index
    if @active_index
      if @active_index == idx
        @active_index = [idx, @layers.size - 1].min
      elsif @active_index > idx
        @active_index -= 1
      end
    end

    layer
  end

  # Move layer up (towards top/front)
  def move_up(layer_or_index)
    idx = layer_or_index.is_a?(Layer) ? @layers.index(layer_or_index) : layer_or_index
    return false if idx.nil? || idx >= @layers.size - 1

    @layers[idx], @layers[idx + 1] = @layers[idx + 1], @layers[idx]
    @active_index = idx + 1 if @active_index == idx
    reorder_canvas_items
    true
  end

  # Move layer down (towards bottom/back)
  def move_down(layer_or_index)
    idx = layer_or_index.is_a?(Layer) ? @layers.index(layer_or_index) : layer_or_index
    return false if idx.nil? || idx <= 0

    @layers[idx], @layers[idx - 1] = @layers[idx - 1], @layers[idx]
    @active_index = idx - 1 if @active_index == idx
    reorder_canvas_items
    true
  end

  # Reorder all canvas items to match layer stack
  # Bottom of @layers array = back of canvas (lowest z-order)
  def reorder_canvas_items
    @layers.each_with_index do |layer, _idx|
      layer.raise_to_top
    end
  end

  # Resize all layers to new dimensions
  def resize(new_width, new_height)
    return if new_width == @width && new_height == @height

    @width = new_width
    @height = new_height
    @layers.each { |l| l.resize(new_width, new_height) }
  end

  # Find layer by name or id
  def find(name_or_id)
    @layers.find { |l| l.name == name_or_id || l.id == name_or_id }
  end

  # Refresh all layer displays
  def refresh_all
    @layers.each(&:refresh_display)
  end

  # Clear all layers
  def clear_all
    @layers.each(&:clear)
  end

  # Merge visible layers down to background (flatten)
  def flatten
    return if @layers.size <= 1

    bg = @layers.first
    bg_pixels = bg.pixels

    # Composite each layer on top (simple overwrite for now, no alpha blending)
    @layers[1..].each do |layer|
      next unless layer.visible

      layer.pixels.each_pixel do |x, y, rgba|
        # Simple overwrite (could add alpha blending later)
        a = rgba.unpack1('@3C')  # Get alpha byte
        bg_pixels.set_pixel(x, y, rgba) if a > 0
      end
    end

    # Remove all layers except background
    @layers[1..].each(&:destroy)
    @layers = [@layers.first]
    @active_index = 0

    bg.refresh_display
  end

  # Memory usage across all layers
  def memory_usage
    @layers.sum { |l| l.memory_usage[:total] }
  end

  # Debug info
  def to_s
    lines = ["LayerManager: #{@layers.size} layers, active=#{@active_index}"]
    @layers.each_with_index do |layer, idx|
      marker = idx == @active_index ? '>' : ' '
      vis = layer.visible ? 'V' : 'H'
      lines << "  #{marker}[#{idx}] #{vis} #{layer.name} (#{layer.pixels.pixel_count} px)"
    end
    lines.join("\n")
  end
end
