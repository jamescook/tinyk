#include "teek_sdl2.h"
#include <SDL2/SDL_ttf.h>

/* ---------------------------------------------------------
 * SDL2_ttf font wrapper
 *
 * Renders text to SDL2 textures via TTF_RenderUTF8_Blended,
 * producing Texture objects compatible with the existing
 * Renderer#copy pipeline.
 * --------------------------------------------------------- */

static VALUE cFont;
static int ttf_initialized = 0;

static void
ensure_ttf_init(void)
{
    if (ttf_initialized) return;

    if (TTF_Init() < 0) {
        rb_raise(rb_eRuntimeError, "TTF_Init failed: %s", TTF_GetError());
    }
    ttf_initialized = 1;
}

/* ---------------------------------------------------------
 * Font (wraps TTF_Font)
 * --------------------------------------------------------- */

struct sdl2_font {
    TTF_Font *font;
    VALUE     renderer_obj; /* keep renderer alive for texture creation */
    int       destroyed;
};

static void
font_mark(void *ptr)
{
    struct sdl2_font *f = ptr;
    rb_gc_mark(f->renderer_obj);
}

static void
font_free(void *ptr)
{
    struct sdl2_font *f = ptr;
    if (!f->destroyed && f->font) {
        TTF_CloseFont(f->font);
        f->font = NULL;
        f->destroyed = 1;
    }
    xfree(f);
}

static size_t
font_memsize(const void *ptr)
{
    return sizeof(struct sdl2_font);
}

static const rb_data_type_t font_type = {
    .wrap_struct_name = "TeekSDL2::Font",
    .function = {
        .dmark = font_mark,
        .dfree = font_free,
        .dsize = font_memsize,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE
font_alloc(VALUE klass)
{
    struct sdl2_font *f;
    VALUE obj = TypedData_Make_Struct(klass, struct sdl2_font, &font_type, f);
    f->font = NULL;
    f->renderer_obj = Qnil;
    f->destroyed = 0;
    return obj;
}

static struct sdl2_font *
get_font(VALUE self)
{
    struct sdl2_font *f;
    TypedData_Get_Struct(self, struct sdl2_font, &font_type, f);
    if (f->destroyed || f->font == NULL) {
        rb_raise(rb_eRuntimeError, "font has been destroyed");
    }
    return f;
}

/*
 * Teek::SDL2::Font#initialize(renderer, path, size)
 *
 * Opens a TrueType font file at the given point size.
 * Keeps a reference to the renderer for texture creation.
 */
static VALUE
font_initialize(VALUE self, VALUE renderer_obj, VALUE path, VALUE size)
{
    struct sdl2_font *f;
    TypedData_Get_Struct(self, struct sdl2_font, &font_type, f);

    ensure_ttf_init();

    /* Validate renderer is alive */
    get_renderer(renderer_obj);

    StringValue(path);
    int pt_size = NUM2INT(size);

    TTF_Font *font = TTF_OpenFont(StringValueCStr(path), pt_size);
    if (!font) {
        rb_raise(rb_eRuntimeError, "TTF_OpenFont failed: %s", TTF_GetError());
    }

    f->font = font;
    f->renderer_obj = renderer_obj;
    return self;
}

/*
 * Teek::SDL2::Font#render_text(text, r, g, b, a=255) -> Texture
 *
 * Renders text to a new texture using TTF_RenderUTF8_Blended.
 * The returned texture has the exact dimensions of the rendered text.
 */
static VALUE
font_render_text(int argc, VALUE *argv, VALUE self)
{
    struct sdl2_font *f = get_font(self);
    struct sdl2_renderer *ren = get_renderer(f->renderer_obj);
    SDL_Color color;

    rb_check_arity(argc, 4, 5);
    const char *text = StringValueCStr(argv[0]);
    color.r = (Uint8)NUM2INT(argv[1]);
    color.g = (Uint8)NUM2INT(argv[2]);
    color.b = (Uint8)NUM2INT(argv[3]);
    color.a = (argc > 4) ? (Uint8)NUM2INT(argv[4]) : 255;

    SDL_Surface *surface = TTF_RenderUTF8_Blended(f->font, text, color);
    if (!surface) {
        rb_raise(rb_eRuntimeError, "TTF_RenderUTF8_Blended failed: %s", TTF_GetError());
    }

    SDL_Texture *texture = SDL_CreateTextureFromSurface(ren->renderer, surface);
    int w = surface->w;
    int h = surface->h;
    SDL_FreeSurface(surface);

    if (!texture) {
        rb_raise(rb_eRuntimeError, "SDL_CreateTextureFromSurface failed: %s", SDL_GetError());
    }

    /* Enable alpha blending on the text texture */
    SDL_SetTextureBlendMode(texture, SDL_BLENDMODE_BLEND);

    /* Wrap as a Texture object */
    VALUE klass = rb_const_get(mTeekSDL2, rb_intern("Texture"));
    VALUE obj = rb_obj_alloc(klass);

    struct sdl2_texture *t;
    TypedData_Get_Struct(obj, struct sdl2_texture, &texture_type, t);
    t->texture = texture;
    t->w = w;
    t->h = h;
    t->renderer_obj = f->renderer_obj;

    return obj;
}

/*
 * Teek::SDL2::Font#measure(text) -> [width, height]
 *
 * Returns the pixel dimensions the given text would occupy when rendered.
 */
static VALUE
font_measure(VALUE self, VALUE text_val)
{
    struct sdl2_font *f = get_font(self);
    const char *text = StringValueCStr(text_val);
    int w, h;

    if (TTF_SizeUTF8(f->font, text, &w, &h) != 0) {
        rb_raise(rb_eRuntimeError, "TTF_SizeUTF8 failed: %s", TTF_GetError());
    }

    return rb_ary_new_from_args(2, INT2NUM(w), INT2NUM(h));
}

/*
 * Teek::SDL2::Font#destroy
 */
static VALUE
font_destroy(VALUE self)
{
    struct sdl2_font *f;
    TypedData_Get_Struct(self, struct sdl2_font, &font_type, f);
    if (!f->destroyed && f->font) {
        TTF_CloseFont(f->font);
        f->font = NULL;
        f->destroyed = 1;
    }
    return Qnil;
}

/*
 * Teek::SDL2::Font#destroyed? -> true/false
 */
static VALUE
font_destroyed_p(VALUE self)
{
    struct sdl2_font *f;
    TypedData_Get_Struct(self, struct sdl2_font, &font_type, f);
    return f->destroyed ? Qtrue : Qfalse;
}

/* ---------------------------------------------------------
 * Init
 * --------------------------------------------------------- */

void
Init_sdl2text(VALUE mTeekSDL2)
{
    cFont = rb_define_class_under(mTeekSDL2, "Font", rb_cObject);
    rb_define_alloc_func(cFont, font_alloc);
    rb_define_method(cFont, "initialize", font_initialize, 3);
    rb_define_method(cFont, "render_text", font_render_text, -1);
    rb_define_method(cFont, "measure", font_measure, 1);
    rb_define_method(cFont, "destroy", font_destroy, 0);
    rb_define_method(cFont, "destroyed?", font_destroyed_p, 0);
}
