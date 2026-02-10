#include "teek_sdl2.h"

VALUE mTeek;
VALUE mTeekSDL2;

/*
 * Teek::SDL2.sdl_version -> String
 *
 * Returns the linked SDL2 version as "major.minor.patch".
 */
static VALUE
teek_sdl2_version(VALUE self)
{
    SDL_version v;
    char buf[32];

    SDL_GetVersion(&v);
    snprintf(buf, sizeof(buf), "%d.%d.%d", v.major, v.minor, v.patch);
    return rb_str_new_cstr(buf);
}

/*
 * Teek::SDL2.sdl_compiled_version -> String
 *
 * Returns the SDL2 version this extension was compiled against.
 */
static VALUE
teek_sdl2_compiled_version(VALUE self)
{
    char buf[32];
    SDL_version v;

    SDL_VERSION(&v);
    snprintf(buf, sizeof(buf), "%d.%d.%d", v.major, v.minor, v.patch);
    return rb_str_new_cstr(buf);
}

void
Init_teek_sdl2(void)
{
    /* Teek module (may already exist from teek gem) */
    mTeek = rb_define_module("Teek");

    /* Teek::SDL2 module */
    mTeekSDL2 = rb_define_module_under(mTeek, "SDL2");

    /* Version queries */
    rb_define_module_function(mTeekSDL2, "sdl_version", teek_sdl2_version, 0);
    rb_define_module_function(mTeekSDL2, "sdl_compiled_version", teek_sdl2_compiled_version, 0);

    /* Layer 1: Pure SDL2 surface/renderer/texture */
    Init_sdl2surface(mTeekSDL2);

    /* Layer 2: Tk bridge (embedding, event routing) */
    Init_sdl2bridge(mTeekSDL2);

    /* Text rendering (SDL2_ttf) */
    Init_sdl2text(mTeekSDL2);

    /* Pixel format conversion helpers */
    Init_sdl2pixels(mTeekSDL2);
}
