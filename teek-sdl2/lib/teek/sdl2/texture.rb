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

      # @!method destroyed?
      #   @return [Boolean] whether this texture has been destroyed

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
