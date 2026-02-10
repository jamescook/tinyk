# frozen_string_literal: true

module Teek
  module SDL2
    # GPU-accelerated 2D renderer backed by SDL2.
    #
    # Renderer wraps an +SDL_Renderer+ and provides both low-level
    # positional-arg methods (defined in C) and higher-level Ruby
    # convenience wrappers with keyword arguments.
    #
    # You don't create a Renderer directly — it's created automatically
    # by {Viewport} and accessible via {Viewport#renderer}.
    #
    # ## C-defined methods
    #
    # These are defined in the C extension (+sdl2surface.c+) and available
    # on every Renderer instance:
    #
    # - {#clear} — clear the rendering target
    # - {#present} — flip the back buffer to screen
    # - {#fill_rect} — draw a filled rectangle
    # - {#draw_rect} — draw a rectangle outline
    # - {#draw_line} — draw a line
    # - {#copy} — copy a texture to the rendering target
    # - {#create_texture} — create a new texture
    # - {#output_size} — query the renderer output dimensions
    # - {#destroy} — destroy the renderer
    # - {#destroyed?} — check if the renderer has been destroyed
    #
    # @see Viewport
    # @see Texture
    class Renderer

      # @!method clear(r = 0, g = 0, b = 0, a = 255)
      #   Clear the entire rendering target with the given color.
      #   @param r [Integer] red (0–255)
      #   @param g [Integer] green (0–255)
      #   @param b [Integer] blue (0–255)
      #   @param a [Integer] alpha (0–255)
      #   @return [self]

      # @!method present
      #   Present the back buffer to the screen. Called automatically by {#render}.
      #   @return [self]

      # @!method fill_rect(x, y, w, h, r, g, b, a = 255)
      #   Draw a filled rectangle.
      #   @param x [Integer] left edge
      #   @param y [Integer] top edge
      #   @param w [Integer] width
      #   @param h [Integer] height
      #   @param r [Integer] red (0–255)
      #   @param g [Integer] green (0–255)
      #   @param b [Integer] blue (0–255)
      #   @param a [Integer] alpha (0–255)
      #   @return [self]

      # @!method draw_rect(x, y, w, h, r, g, b, a = 255)
      #   Draw a rectangle outline.
      #   @param x [Integer] left edge
      #   @param y [Integer] top edge
      #   @param w [Integer] width
      #   @param h [Integer] height
      #   @param r [Integer] red (0–255)
      #   @param g [Integer] green (0–255)
      #   @param b [Integer] blue (0–255)
      #   @param a [Integer] alpha (0–255)
      #   @return [self]

      # @!method draw_line(x1, y1, x2, y2, r, g, b, a = 255)
      #   Draw a line between two points.
      #   @param x1 [Integer] start x
      #   @param y1 [Integer] start y
      #   @param x2 [Integer] end x
      #   @param y2 [Integer] end y
      #   @param r [Integer] red (0–255)
      #   @param g [Integer] green (0–255)
      #   @param b [Integer] blue (0–255)
      #   @param a [Integer] alpha (0–255)
      #   @return [self]

      # @!method copy(texture, src_rect = nil, dst_rect = nil)
      #   Copy a texture (or portion of it) to the rendering target.
      #   @param texture [Texture] the source texture
      #   @param src_rect [Array(Integer, Integer, Integer, Integer), nil]
      #     source rectangle +[x, y, w, h]+ or +nil+ for entire texture
      #   @param dst_rect [Array(Integer, Integer, Integer, Integer), nil]
      #     destination rectangle +[x, y, w, h]+ or +nil+ for entire target
      #   @return [self]

      # @!method create_texture(width, height, access = :static)
      #   Create a new texture owned by this renderer.
      #   @param width [Integer] texture width in pixels
      #   @param height [Integer] texture height in pixels
      #   @param access [Symbol] +:static+, +:streaming+, or +:target+
      #   @return [Texture]

      # @!method output_size
      #   Query the renderer's output dimensions.
      #   @return [Array(Integer, Integer)] +[width, height]+

      # @!method destroy
      #   Destroy this renderer and free GPU resources.
      #   @return [void]

      # @!method destroyed?
      #   @return [Boolean] whether this renderer has been destroyed

      # Yield self for a drawing block, then present.
      #
      # @yield [renderer] draw commands
      # @yieldparam renderer [Renderer]
      # @return [self]
      #
      # @example
      #   renderer.render do |r|
      #     r.clear(0, 0, 0)
      #     r.fill(10, 10, 100, 100, r: 255, g: 0, b: 0)
      #   end
      def render
        yield self
        present
        self
      end

      # Draw a filled rectangle (keyword-arg wrapper for {#fill_rect}).
      #
      # @param x [Integer] left edge
      # @param y [Integer] top edge
      # @param w [Integer] width
      # @param h [Integer] height
      # @param r [Integer] red (0–255)
      # @param g [Integer] green (0–255)
      # @param b [Integer] blue (0–255)
      # @param a [Integer] alpha (0–255)
      # @return [self]
      def fill(x, y, w, h, r:, g:, b:, a: 255)
        fill_rect(x, y, w, h, r, g, b, a)
      end

      # Draw a rectangle outline (keyword-arg wrapper for {#draw_rect}).
      #
      # @param x [Integer] left edge
      # @param y [Integer] top edge
      # @param w [Integer] width
      # @param h [Integer] height
      # @param r [Integer] red (0–255)
      # @param g [Integer] green (0–255)
      # @param b [Integer] blue (0–255)
      # @param a [Integer] alpha (0–255)
      # @return [self]
      def outline(x, y, w, h, r:, g:, b:, a: 255)
        draw_rect(x, y, w, h, r, g, b, a)
      end

      # Draw a line (keyword-arg wrapper for {#draw_line}).
      #
      # @param x1 [Integer] start x
      # @param y1 [Integer] start y
      # @param x2 [Integer] end x
      # @param y2 [Integer] end y
      # @param r [Integer] red (0–255)
      # @param g [Integer] green (0–255)
      # @param b [Integer] blue (0–255)
      # @param a [Integer] alpha (0–255)
      # @return [self]
      def line(x1, y1, x2, y2, r:, g:, b:, a: 255)
        draw_line(x1, y1, x2, y2, r, g, b, a)
      end

      # Copy a texture (keyword-arg wrapper for {#copy}).
      #
      # @param texture [Texture] the source texture
      # @param src [Array(Integer, Integer, Integer, Integer), nil]
      #   source rectangle +[x, y, w, h]+ or +nil+ for entire texture
      # @param dst [Array(Integer, Integer, Integer, Integer), nil]
      #   destination rectangle +[x, y, w, h]+ or +nil+ for entire target
      # @return [self]
      def blit(texture, src: nil, dst: nil)
        copy(texture, src, dst)
      end
    end
  end
end
