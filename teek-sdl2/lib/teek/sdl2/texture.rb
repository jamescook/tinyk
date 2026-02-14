# frozen_string_literal: true

module Teek
  module SDL2
    # GPU-resident pixel buffer backed by an +SDL_Texture+.
    #
    # Textures are created through a {Renderer}, not directly instantiated.
    # Use the convenience constructors {.streaming} and {.target}, or call
    # {Renderer#create_texture} directly.
    #
    # ## C-defined methods
    #
    # These are defined in the C extension (+sdl2surface.c+):
    #
    # - {#update} — upload pixel data from a String
    # - {#width} — texture width in pixels
    # - {#height} — texture height in pixels
    # - {#blend_mode=} — set the texture blend mode
    # - {#blend_mode} — get the current blend mode
    # - {#destroy} — free GPU resources
    # - {#destroyed?} — check if the texture has been destroyed
    #
    # @example Create and update a streaming texture
    #   tex = Teek::SDL2::Texture.streaming(renderer, 256, 224)
    #   tex.update(pixel_data_string)
    #   renderer.copy(tex)
    #
    # @see Renderer#create_texture
    class Texture

      # @!method update(pixel_data)
      #   Upload pixel data to the texture. The data must be a binary String
      #   of ARGB8888 pixels (4 bytes per pixel, width * height * 4 total).
      #   @param pixel_data [String] raw pixel bytes
      #   @return [self]

      # @!method width
      #   @return [Integer] texture width in pixels

      # @!method height
      #   @return [Integer] texture height in pixels

      # @!method destroy
      #   Free this texture's GPU resources.
      #   @return [void]

      # @!method blend_mode=(mode)
      #   Set the blend mode used when this texture is drawn via {Renderer#copy}.
      #
      #   Built-in modes (Symbol):
      #   - +:none+  — no blending (copy pixels as-is)
      #   - +:blend+ — alpha blending (default for TTF-rendered textures)
      #   - +:add+   — additive blending
      #   - +:mod+   — color modulation
      #
      #   Pass an Integer from {SDL2.compose_blend_mode} for custom blend modes.
      #
      #   @param mode [Symbol, Integer] blend mode
      #   @return [Symbol, Integer] the mode that was set
      #   @see https://wiki.libsdl.org/SDL2/SDL_SetTextureBlendMode SDL_SetTextureBlendMode
      #
      #   @example Inverse/invert effect (shows opposite of background)
      #     inverse = Teek::SDL2.compose_blend_mode(
      #       :one_minus_dst_color, :one_minus_src_alpha, :add,
      #       :zero, :one, :add
      #     )
      #     white_text = font.render_text("Hello", 255, 255, 255)
      #     white_text.blend_mode = inverse

      # @!method blend_mode
      #   @return [Integer] current blend mode
      #   @see https://wiki.libsdl.org/SDL2/SDL_GetTextureBlendMode SDL_GetTextureBlendMode

      # @!method destroyed?
      #   @return [Boolean] whether this texture has been destroyed

      # Load an image file into a GPU texture via SDL2_image.
      #
      # @param renderer [Renderer] the renderer that owns this texture
      # @param path [String] path to an image file (PNG, JPG, BMP, etc.)
      # @return [Texture]
      #
      # @example
      #   sprite = Teek::SDL2::Texture.from_file(renderer, "assets/player.png")
      #   renderer.copy(sprite)
      def self.from_file(renderer, path)
        renderer.load_image(path)
      end

      # Create a streaming texture (lockable, CPU-updatable).
      #
      # @param renderer [Renderer] the renderer that owns this texture
      # @param width [Integer] width in pixels
      # @param height [Integer] height in pixels
      # @return [Texture]
      #
      # @example
      #   tex = Teek::SDL2::Texture.streaming(renderer, 256, 224)
      #   tex.update(rgba_string)
      def self.streaming(renderer, width, height)
        renderer.create_texture(width, height, :streaming)
      end

      # Create a target texture (can be rendered to via +SDL_SetRenderTarget+).
      #
      # @param renderer [Renderer] the renderer that owns this texture
      # @param width [Integer] width in pixels
      # @param height [Integer] height in pixels
      # @return [Texture]
      def self.target(renderer, width, height)
        renderer.create_texture(width, height, :target)
      end

      # @return [Array(Integer, Integer)] +[width, height]+
      def size
        [width, height]
      end
    end
  end
end
