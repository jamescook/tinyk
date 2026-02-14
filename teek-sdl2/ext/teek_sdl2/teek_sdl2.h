#ifndef TEEK_SDL2_H
#define TEEK_SDL2_H

#include <ruby.h>
#include <SDL2/SDL.h>
#include <stdint.h>

/* Module and class references */
extern VALUE mTeek;
extern VALUE mTeekSDL2;

/* Shared struct — used by both surface and bridge layers */
struct sdl2_renderer {
    SDL_Window   *window;
    SDL_Renderer *renderer;
    int           owned_window; /* 1 if we created the window, 0 if from foreign handle */
    int           destroyed;
};

/* Renderer */
extern const rb_data_type_t renderer_type;
struct sdl2_renderer *get_renderer(VALUE self);
void ensure_sdl2_init(void);

/* Texture — shared so sdl2text.c can create Texture objects from TTF surfaces */
struct sdl2_texture {
    SDL_Texture *texture;
    int          w;
    int          h;
    int          destroyed;
    VALUE        renderer_obj; /* prevent GC of parent renderer */
};

extern const rb_data_type_t texture_type;

/*
 * C extension is split into three concerns:
 *
 * 1. SDL2 surface layer (pure SDL2, no Tk knowledge):
 *    - sdl2surface.c: SDL_Init, SDL_CreateWindow, SDL_CreateRenderer,
 *      texture management, render commands, cleanup
 *    - Knows nothing about Tk frames or winfo id
 *
 * 2. Tk bridge layer (connects SDL2 surface to a Tk frame):
 *    - sdl2bridge.c: SDL_CreateWindowFrom(winfo_id), resize sync,
 *      event routing between Tk and SDL2
 *    - Depends on surface layer, talks to Tk via teek's interp
 *
 * 3. Text rendering (SDL2_ttf):
 *    - sdl2text.c: Font loading, text-to-texture rendering
 *    - Produces Texture objects compatible with Renderer#copy
 *
 * This separation means the SDL2 surface/renderer code is testable
 * and usable without Tk, and the Tk-specific embedding logic is
 * isolated in the bridge.
 */
void Init_sdl2surface(VALUE mTeekSDL2);
void Init_sdl2bridge(VALUE mTeekSDL2);
void Init_sdl2text(VALUE mTeekSDL2);
void Init_sdl2pixels(VALUE mTeekSDL2);
void Init_sdl2image(VALUE mTeekSDL2);
void Init_sdl2mixer(VALUE mTeekSDL2);
void Init_sdl2audio(VALUE mTeekSDL2);
void Init_sdl2gamepad(VALUE mTeekSDL2);

#endif /* TEEK_SDL2_H */
