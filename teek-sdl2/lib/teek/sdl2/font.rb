# frozen_string_literal: true

module Teek
  module SDL2
    # TrueType font for GPU-accelerated text rendering via SDL2_ttf.
    #
    # Fonts are loaded through {Renderer#load_font} and render text into
    # {Texture} objects that can be drawn with {Renderer#copy}.
    #
    # ## C-defined methods
    #
    # These are defined in the C extension (+sdl2text.c+):
    #
    # - {#render_text} — render a string to a new Texture
    # - {#measure} — measure text dimensions without rendering
    # - {#destroy} — close the font
    # - {#destroyed?} — check if the font has been closed
    #
    # @example Render text
    #   font = renderer.load_font("/path/to/font.ttf", 16)
    #   renderer.draw_text(10, 10, "Hello!", font: font, r: 255, g: 255, b: 255)
    #
    # @example Measure text for layout
    #   w, h = font.measure("Score: 100")
    #   # right-align at x = screen_width - w - padding
    #
    # @see Renderer#load_font
    # @see Renderer#draw_text
    class Font

      # @!method render_text(text, r, g, b, a = 255, premultiply = false)
      #   Render a string to a new {Texture} using +TTF_RenderUTF8_Blended+.
      #   The texture has the exact pixel dimensions of the rendered text.
      #
      #   When +premultiply+ is true, each pixel's RGB is multiplied by its
      #   alpha before creating the texture. This is required for custom blend
      #   modes (from {SDL2.compose_blend_mode}) that read source RGB
      #   independently of source alpha — without it, the "transparent"
      #   background of the text surface retains the foreground color,
      #   causing the entire texture rect to be visible.
      #
      #   @param text [String] the text to render (UTF-8)
      #   @param r [Integer] red (0–255)
      #   @param g [Integer] green (0–255)
      #   @param b [Integer] blue (0–255)
      #   @param a [Integer] alpha (0–255)
      #   @param premultiply [Boolean] premultiply alpha for custom blend modes
      #   @return [Texture] a new texture containing the rendered text
      #   @see https://wiki.libsdl.org/SDL2/SDL_ComposeCustomBlendMode SDL_ComposeCustomBlendMode

      # @!method measure(text)
      #   Measure the pixel dimensions the text would occupy when rendered.
      #   Does not create a texture — useful for layout calculations.
      #   @param text [String] the text to measure (UTF-8)
      #   @return [Array(Integer, Integer)] +[width, height]+

      # @!method destroy
      #   Close the font and free resources.
      #   @return [void]

      # @!method destroyed?
      #   @return [Boolean] whether this font has been closed
    end

    class Renderer
      # Load a TrueType font file at the given point size.
      #
      # @param path [String] path to a +.ttf+ or +.otf+ font file
      # @param size [Integer] point size
      # @return [Font]
      #
      # @example
      #   font = renderer.load_font("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 16)
      def load_font(path, size)
        Font.new(self, path, size)
      end

      # Render text and blit it at the given position in a single call.
      #
      # Creates a temporary texture, copies it to the renderer, then
      # destroys it. For repeated rendering of the same text, prefer
      # calling {Font#render_text} once and reusing the texture.
      #
      # @param x [Integer] left edge
      # @param y [Integer] top edge
      # @param text [String] the text to render (UTF-8)
      # @param font [Font] the font to use
      # @param r [Integer] red (0–255)
      # @param g [Integer] green (0–255)
      # @param b [Integer] blue (0–255)
      # @param a [Integer] alpha (0–255)
      # @return [self]
      #
      # @example
      #   renderer.draw_text(10, 10, "Hello!", font: font, r: 255, g: 255, b: 255)
      def draw_text(x, y, text, font:, r: 255, g: 255, b: 255, a: 255)
        tex = font.render_text(text, r, g, b, a)
        copy(tex, nil, [x, y, tex.width, tex.height])
        tex.destroy
        self
      end
    end
  end
end
