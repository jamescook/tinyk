#include "teek_sdl2.h"

/* ---------------------------------------------------------
 * Layer 1: Pure SDL2 surface management
 *
 * No Tk knowledge. Manages SDL2 windows, renderers, and
 * textures. Can be tested standalone.
 * --------------------------------------------------------- */

static VALUE cRenderer;
static VALUE cTexture;
static VALUE eSDL2Error;

/* Track whether SDL2 has been initialized */
static int sdl2_initialized = 0;

/* ---------------------------------------------------------
 * SDL2 lazy initialization
 * --------------------------------------------------------- */

void
ensure_sdl2_init(void)
{
    if (sdl2_initialized) return;

    if (SDL_Init(SDL_INIT_VIDEO) < 0) {
        rb_raise(rb_eRuntimeError, "SDL_Init failed: %s", SDL_GetError());
    }
    sdl2_initialized = 1;
}

/* ---------------------------------------------------------
 * Renderer (wraps SDL_Window + SDL_Renderer)
 * --------------------------------------------------------- */

static void
renderer_mark(void *ptr)
{
    (void)ptr;
}

static void
renderer_free(void *ptr)
{
    struct sdl2_renderer *r = ptr;
    if (!r->destroyed) {
        if (r->renderer) {
            SDL_DestroyRenderer(r->renderer);
            r->renderer = NULL;
        }
        if (r->window && r->owned_window) {
            SDL_DestroyWindow(r->window);
            r->window = NULL;
        }
        r->destroyed = 1;
    }
    xfree(r);
}

static size_t
renderer_memsize(const void *ptr)
{
    return sizeof(struct sdl2_renderer);
}

const rb_data_type_t renderer_type = {
    .wrap_struct_name = "TeekSDL2::Renderer",
    .function = {
        .dmark = renderer_mark,
        .dfree = renderer_free,
        .dsize = renderer_memsize,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE
renderer_alloc(VALUE klass)
{
    struct sdl2_renderer *r;
    VALUE obj = TypedData_Make_Struct(klass, struct sdl2_renderer, &renderer_type, r);
    r->window = NULL;
    r->renderer = NULL;
    r->owned_window = 0;
    r->destroyed = 0;
    return obj;
}

struct sdl2_renderer *
get_renderer(VALUE self)
{
    struct sdl2_renderer *r;
    TypedData_Get_Struct(self, struct sdl2_renderer, &renderer_type, r);
    if (r->destroyed || r->renderer == NULL) {
        rb_raise(eSDL2Error, "renderer has been destroyed");
    }
    return r;
}

/*
 * Teek::SDL2::Renderer#clear(r=0, g=0, b=0, a=255)
 */
static VALUE
renderer_clear(int argc, VALUE *argv, VALUE self)
{
    struct sdl2_renderer *ren = get_renderer(self);
    Uint8 r = 0, g = 0, b = 0, a = 255;

    if (argc > 0) r = (Uint8)NUM2INT(argv[0]);
    if (argc > 1) g = (Uint8)NUM2INT(argv[1]);
    if (argc > 2) b = (Uint8)NUM2INT(argv[2]);
    if (argc > 3) a = (Uint8)NUM2INT(argv[3]);

    SDL_SetRenderDrawColor(ren->renderer, r, g, b, a);
    SDL_RenderClear(ren->renderer);
    return self;
}

/*
 * Teek::SDL2::Renderer#present
 */
static VALUE
renderer_present(VALUE self)
{
    struct sdl2_renderer *ren = get_renderer(self);
    SDL_RenderPresent(ren->renderer);
    return self;
}

/*
 * Teek::SDL2::Renderer#fill_rect(x, y, w, h, r, g, b, a=255)
 */
static VALUE
renderer_fill_rect(int argc, VALUE *argv, VALUE self)
{
    struct sdl2_renderer *ren = get_renderer(self);
    SDL_Rect rect;
    Uint8 r, g, b, a = 255;

    rb_check_arity(argc, 7, 8);
    rect.x = NUM2INT(argv[0]);
    rect.y = NUM2INT(argv[1]);
    rect.w = NUM2INT(argv[2]);
    rect.h = NUM2INT(argv[3]);
    r = (Uint8)NUM2INT(argv[4]);
    g = (Uint8)NUM2INT(argv[5]);
    b = (Uint8)NUM2INT(argv[6]);
    if (argc > 7) a = (Uint8)NUM2INT(argv[7]);

    SDL_SetRenderDrawColor(ren->renderer, r, g, b, a);
    SDL_RenderFillRect(ren->renderer, &rect);
    return self;
}

/*
 * Teek::SDL2::Renderer#draw_rect(x, y, w, h, r, g, b, a=255)
 */
static VALUE
renderer_draw_rect(int argc, VALUE *argv, VALUE self)
{
    struct sdl2_renderer *ren = get_renderer(self);
    SDL_Rect rect;
    Uint8 r, g, b, a = 255;

    rb_check_arity(argc, 7, 8);
    rect.x = NUM2INT(argv[0]);
    rect.y = NUM2INT(argv[1]);
    rect.w = NUM2INT(argv[2]);
    rect.h = NUM2INT(argv[3]);
    r = (Uint8)NUM2INT(argv[4]);
    g = (Uint8)NUM2INT(argv[5]);
    b = (Uint8)NUM2INT(argv[6]);
    if (argc > 7) a = (Uint8)NUM2INT(argv[7]);

    SDL_SetRenderDrawColor(ren->renderer, r, g, b, a);
    SDL_RenderDrawRect(ren->renderer, &rect);
    return self;
}

/*
 * Teek::SDL2::Renderer#draw_line(x1, y1, x2, y2, r, g, b, a=255)
 */
static VALUE
renderer_draw_line(int argc, VALUE *argv, VALUE self)
{
    struct sdl2_renderer *ren = get_renderer(self);
    Uint8 r, g, b, a = 255;

    rb_check_arity(argc, 7, 8);
    r = (Uint8)NUM2INT(argv[4]);
    g = (Uint8)NUM2INT(argv[5]);
    b = (Uint8)NUM2INT(argv[6]);
    if (argc > 7) a = (Uint8)NUM2INT(argv[7]);

    SDL_SetRenderDrawColor(ren->renderer, r, g, b, a);
    SDL_RenderDrawLine(ren->renderer,
                       NUM2INT(argv[0]), NUM2INT(argv[1]),
                       NUM2INT(argv[2]), NUM2INT(argv[3]));
    return self;
}

/*
 * Teek::SDL2::Renderer#output_size -> [w, h]
 */
static VALUE
renderer_output_size(VALUE self)
{
    struct sdl2_renderer *ren = get_renderer(self);
    int w, h;

    if (SDL_GetRendererOutputSize(ren->renderer, &w, &h) != 0) {
        rb_raise(eSDL2Error, "SDL_GetRendererOutputSize: %s", SDL_GetError());
    }
    return rb_ary_new_from_args(2, INT2NUM(w), INT2NUM(h));
}

/*
 * Teek::SDL2::Renderer#read_pixels -> String (RGBA bytes)
 *
 * Reads the current renderer contents as raw RGBA pixel data.
 * Returns a binary String of width*height*4 bytes.
 * Call after rendering but before present for consistent results.
 */
static VALUE
renderer_read_pixels(VALUE self)
{
    struct sdl2_renderer *ren = get_renderer(self);
    int w, h;

    if (SDL_GetRendererOutputSize(ren->renderer, &w, &h) != 0) {
        rb_raise(eSDL2Error, "SDL_GetRendererOutputSize: %s", SDL_GetError());
    }

    long size = (long)w * h * 4;
    VALUE buf = rb_str_buf_new(size);
    rb_str_set_len(buf, size);

    if (SDL_RenderReadPixels(ren->renderer, NULL, SDL_PIXELFORMAT_RGBA8888,
                             RSTRING_PTR(buf), w * 4) != 0) {
        rb_raise(eSDL2Error, "SDL_RenderReadPixels: %s", SDL_GetError());
    }

    return buf;
}

/*
 * Teek::SDL2::Renderer#destroy
 */
static VALUE
renderer_destroy(VALUE self)
{
    struct sdl2_renderer *r;
    TypedData_Get_Struct(self, struct sdl2_renderer, &renderer_type, r);
    if (!r->destroyed) {
        if (r->renderer) {
            SDL_DestroyRenderer(r->renderer);
            r->renderer = NULL;
        }
        if (r->window && r->owned_window) {
            SDL_DestroyWindow(r->window);
            r->window = NULL;
        }
        r->destroyed = 1;
    }
    return Qnil;
}

/*
 * Teek::SDL2::Renderer#destroyed? -> true/false
 */
static VALUE
renderer_destroyed_p(VALUE self)
{
    struct sdl2_renderer *r;
    TypedData_Get_Struct(self, struct sdl2_renderer, &renderer_type, r);
    return r->destroyed ? Qtrue : Qfalse;
}

/* ---------------------------------------------------------
 * Texture (wraps SDL_Texture)
 *
 * struct sdl2_texture is defined in teek_sdl2.h so sdl2text.c
 * can create Texture objects from TTF-rendered surfaces.
 * --------------------------------------------------------- */

static void
texture_mark(void *ptr)
{
    struct sdl2_texture *t = ptr;
    rb_gc_mark(t->renderer_obj);
}

static void
texture_free(void *ptr)
{
    struct sdl2_texture *t = ptr;
    if (!t->destroyed && t->texture) {
        SDL_DestroyTexture(t->texture);
        t->texture = NULL;
        t->destroyed = 1;
    }
    xfree(t);
}

static size_t
texture_memsize(const void *ptr)
{
    return sizeof(struct sdl2_texture);
}

const rb_data_type_t texture_type = {
    .wrap_struct_name = "TeekSDL2::Texture",
    .function = {
        .dmark = texture_mark,
        .dfree = texture_free,
        .dsize = texture_memsize,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE
texture_alloc(VALUE klass)
{
    struct sdl2_texture *t;
    VALUE obj = TypedData_Make_Struct(klass, struct sdl2_texture, &texture_type, t);
    t->texture = NULL;
    t->w = 0;
    t->h = 0;
    t->destroyed = 0;
    t->renderer_obj = Qnil;
    return obj;
}

static struct sdl2_texture *
get_texture(VALUE self)
{
    struct sdl2_texture *t;
    TypedData_Get_Struct(self, struct sdl2_texture, &texture_type, t);
    if (t->destroyed || t->texture == NULL) {
        rb_raise(eSDL2Error, "texture has been destroyed");
    }
    return t;
}

/*
 * Teek::SDL2::Renderer#create_texture(w, h, access=:streaming)
 *
 * Creates an ARGB8888 texture. Access modes:
 *   :static    - rarely updated
 *   :streaming - frequently updated (lock/unlock)
 *   :target    - can be used as render target
 */
static VALUE
renderer_create_texture(int argc, VALUE *argv, VALUE self)
{
    struct sdl2_renderer *ren = get_renderer(self);
    int w, h;
    int access = SDL_TEXTUREACCESS_STREAMING;

    rb_check_arity(argc, 2, 3);
    w = NUM2INT(argv[0]);
    h = NUM2INT(argv[1]);

    if (argc > 2 && !NIL_P(argv[2])) {
        ID sym = SYM2ID(argv[2]);
        if (sym == rb_intern("static"))
            access = SDL_TEXTUREACCESS_STATIC;
        else if (sym == rb_intern("streaming"))
            access = SDL_TEXTUREACCESS_STREAMING;
        else if (sym == rb_intern("target"))
            access = SDL_TEXTUREACCESS_TARGET;
        else
            rb_raise(rb_eArgError, "unknown access mode (use :static, :streaming, or :target)");
    }

    SDL_Texture *tex = SDL_CreateTexture(ren->renderer,
                                         SDL_PIXELFORMAT_ARGB8888,
                                         access, w, h);
    if (!tex) {
        rb_raise(eSDL2Error, "SDL_CreateTexture: %s", SDL_GetError());
    }

    VALUE obj = texture_alloc(cTexture);
    struct sdl2_texture *t;
    TypedData_Get_Struct(obj, struct sdl2_texture, &texture_type, t);
    t->texture = tex;
    t->w = w;
    t->h = h;
    t->renderer_obj = self;
    return obj;
}

/*
 * Teek::SDL2::Texture#update(pixels)
 *
 * Updates the entire texture with pixel data.
 * pixels must be a String of w*h*4 bytes (ARGB8888).
 */
static VALUE
texture_update(VALUE self, VALUE pixels)
{
    struct sdl2_texture *t = get_texture(self);
    Check_Type(pixels, T_STRING);

    long expected = (long)t->w * t->h * 4;
    if (RSTRING_LEN(pixels) != expected) {
        rb_raise(rb_eArgError, "pixel data must be %ld bytes (got %ld)",
                 expected, RSTRING_LEN(pixels));
    }

    int pitch = t->w * 4;
    if (SDL_UpdateTexture(t->texture, NULL, RSTRING_PTR(pixels), pitch) != 0) {
        rb_raise(eSDL2Error, "SDL_UpdateTexture: %s", SDL_GetError());
    }
    return self;
}

/*
 * Teek::SDL2::Renderer#copy(texture, src_rect=nil, dst_rect=nil)
 *
 * Copies texture to the renderer. Rects are [x, y, w, h] arrays or nil for full area.
 */
static VALUE
renderer_copy(int argc, VALUE *argv, VALUE self)
{
    struct sdl2_renderer *ren = get_renderer(self);
    VALUE tex_obj, src_rect_obj, dst_rect_obj;
    SDL_Rect src, dst, *srcp = NULL, *dstp = NULL;

    rb_scan_args(argc, argv, "12", &tex_obj, &src_rect_obj, &dst_rect_obj);

    struct sdl2_texture *t = get_texture(tex_obj);

    if (!NIL_P(src_rect_obj)) {
        Check_Type(src_rect_obj, T_ARRAY);
        src.x = NUM2INT(rb_ary_entry(src_rect_obj, 0));
        src.y = NUM2INT(rb_ary_entry(src_rect_obj, 1));
        src.w = NUM2INT(rb_ary_entry(src_rect_obj, 2));
        src.h = NUM2INT(rb_ary_entry(src_rect_obj, 3));
        srcp = &src;
    }

    if (!NIL_P(dst_rect_obj)) {
        Check_Type(dst_rect_obj, T_ARRAY);
        dst.x = NUM2INT(rb_ary_entry(dst_rect_obj, 0));
        dst.y = NUM2INT(rb_ary_entry(dst_rect_obj, 1));
        dst.w = NUM2INT(rb_ary_entry(dst_rect_obj, 2));
        dst.h = NUM2INT(rb_ary_entry(dst_rect_obj, 3));
        dstp = &dst;
    }

    if (SDL_RenderCopy(ren->renderer, t->texture, srcp, dstp) != 0) {
        rb_raise(eSDL2Error, "SDL_RenderCopy: %s", SDL_GetError());
    }
    return self;
}

/*
 * Teek::SDL2::Texture#width -> Integer
 */
static VALUE
texture_width(VALUE self)
{
    return INT2NUM(get_texture(self)->w);
}

/*
 * Teek::SDL2::Texture#height -> Integer
 */
static VALUE
texture_height(VALUE self)
{
    return INT2NUM(get_texture(self)->h);
}

/*
 * Teek::SDL2::Texture#destroy
 */
static VALUE
texture_destroy(VALUE self)
{
    struct sdl2_texture *t;
    TypedData_Get_Struct(self, struct sdl2_texture, &texture_type, t);
    if (!t->destroyed && t->texture) {
        SDL_DestroyTexture(t->texture);
        t->texture = NULL;
        t->destroyed = 1;
    }
    return Qnil;
}

/*
 * Teek::SDL2::Texture#destroyed? -> true/false
 */
static VALUE
texture_destroyed_p(VALUE self)
{
    struct sdl2_texture *t;
    TypedData_Get_Struct(self, struct sdl2_texture, &texture_type, t);
    return t->destroyed ? Qtrue : Qfalse;
}

/* ---------------------------------------------------------
 * Blend factor / operation helpers
 * --------------------------------------------------------- */

static SDL_BlendFactor
sym_to_blend_factor(VALUE sym)
{
    ID id = SYM2ID(sym);
    if (id == rb_intern("zero"))                return SDL_BLENDFACTOR_ZERO;
    if (id == rb_intern("one"))                 return SDL_BLENDFACTOR_ONE;
    if (id == rb_intern("src_color"))           return SDL_BLENDFACTOR_SRC_COLOR;
    if (id == rb_intern("one_minus_src_color")) return SDL_BLENDFACTOR_ONE_MINUS_SRC_COLOR;
    if (id == rb_intern("src_alpha"))           return SDL_BLENDFACTOR_SRC_ALPHA;
    if (id == rb_intern("one_minus_src_alpha")) return SDL_BLENDFACTOR_ONE_MINUS_SRC_ALPHA;
    if (id == rb_intern("dst_color"))           return SDL_BLENDFACTOR_DST_COLOR;
    if (id == rb_intern("one_minus_dst_color")) return SDL_BLENDFACTOR_ONE_MINUS_DST_COLOR;
    if (id == rb_intern("dst_alpha"))           return SDL_BLENDFACTOR_DST_ALPHA;
    if (id == rb_intern("one_minus_dst_alpha")) return SDL_BLENDFACTOR_ONE_MINUS_DST_ALPHA;
    rb_raise(rb_eArgError,
             "unknown blend factor (use :zero, :one, :src_color, "
             ":one_minus_src_color, :src_alpha, :one_minus_src_alpha, "
             ":dst_color, :one_minus_dst_color, :dst_alpha, :one_minus_dst_alpha)");
    return 0; /* unreachable */
}

static SDL_BlendOperation
sym_to_blend_operation(VALUE sym)
{
    ID id = SYM2ID(sym);
    if (id == rb_intern("add"))              return SDL_BLENDOPERATION_ADD;
    if (id == rb_intern("subtract"))         return SDL_BLENDOPERATION_SUBTRACT;
    if (id == rb_intern("rev_subtract"))     return SDL_BLENDOPERATION_REV_SUBTRACT;
    if (id == rb_intern("minimum"))          return SDL_BLENDOPERATION_MINIMUM;
    if (id == rb_intern("maximum"))          return SDL_BLENDOPERATION_MAXIMUM;
    rb_raise(rb_eArgError,
             "unknown blend operation (use :add, :subtract, :rev_subtract, "
             ":minimum, :maximum)");
    return 0; /* unreachable */
}

/*
 * Teek::SDL2::Texture#blend_mode=(mode)
 *
 * Sets the texture blend mode. mode can be a Symbol for built-in
 * modes or an Integer from compose_blend_mode for custom modes:
 *   :none  - no blending
 *   :blend - alpha blending (default for TTF textures)
 *   :add   - additive blending
 *   :mod   - color modulate
 *   Integer - custom blend mode from Teek::SDL2.compose_blend_mode
 */
static VALUE
texture_set_blend_mode(VALUE self, VALUE mode)
{
    struct sdl2_texture *t = get_texture(self);
    SDL_BlendMode bm;

    if (FIXNUM_P(mode)) {
        bm = (SDL_BlendMode)NUM2INT(mode);
    } else if (SYMBOL_P(mode)) {
        ID id = SYM2ID(mode);
        if (id == rb_intern("none"))       bm = SDL_BLENDMODE_NONE;
        else if (id == rb_intern("blend")) bm = SDL_BLENDMODE_BLEND;
        else if (id == rb_intern("add"))   bm = SDL_BLENDMODE_ADD;
        else if (id == rb_intern("mod"))   bm = SDL_BLENDMODE_MOD;
        else rb_raise(rb_eArgError, "unknown blend mode (use :none, :blend, :add, :mod, or Integer)");
    } else {
        rb_raise(rb_eTypeError, "expected Symbol or Integer for blend_mode");
    }

    if (SDL_SetTextureBlendMode(t->texture, bm) != 0) {
        rb_raise(eSDL2Error, "SDL_SetTextureBlendMode: %s", SDL_GetError());
    }
    return mode;
}

/*
 * Teek::SDL2::Texture#blend_mode -> Integer
 *
 * Returns the current blend mode as an integer.
 */
static VALUE
texture_get_blend_mode(VALUE self)
{
    struct sdl2_texture *t = get_texture(self);
    SDL_BlendMode bm;

    if (SDL_GetTextureBlendMode(t->texture, &bm) != 0) {
        rb_raise(eSDL2Error, "SDL_GetTextureBlendMode: %s", SDL_GetError());
    }
    return INT2NUM((int)bm);
}

/*
 * Teek::SDL2.compose_blend_mode(src_color, dst_color, color_op,
 *                                src_alpha, dst_alpha, alpha_op) -> Integer
 *
 * Creates a custom blend mode via SDL_ComposeCustomBlendMode.
 * Returns an Integer suitable for Texture#blend_mode=.
 *
 * Factors: :zero, :one, :src_color, :one_minus_src_color,
 *   :src_alpha, :one_minus_src_alpha, :dst_color,
 *   :one_minus_dst_color, :dst_alpha, :one_minus_dst_alpha
 *
 * Operations: :add, :subtract, :rev_subtract, :minimum, :maximum
 */
static VALUE
sdl2_compose_blend_mode(VALUE self,
                        VALUE src_color, VALUE dst_color, VALUE color_op,
                        VALUE src_alpha, VALUE dst_alpha, VALUE alpha_op)
{
    SDL_BlendMode bm = SDL_ComposeCustomBlendMode(
        sym_to_blend_factor(src_color),
        sym_to_blend_factor(dst_color),
        sym_to_blend_operation(color_op),
        sym_to_blend_factor(src_alpha),
        sym_to_blend_factor(dst_alpha),
        sym_to_blend_operation(alpha_op)
    );
    return INT2NUM((int)bm);
}

/* ---------------------------------------------------------
 * Init
 * --------------------------------------------------------- */

void
Init_sdl2surface(VALUE mTeekSDL2)
{
    eSDL2Error = rb_define_class_under(mTeekSDL2, "Error", rb_eRuntimeError);

    /* Renderer */
    cRenderer = rb_define_class_under(mTeekSDL2, "Renderer", rb_cObject);
    rb_define_alloc_func(cRenderer, renderer_alloc);
    rb_define_method(cRenderer, "clear", renderer_clear, -1);
    rb_define_method(cRenderer, "present", renderer_present, 0);
    rb_define_method(cRenderer, "fill_rect", renderer_fill_rect, -1);
    rb_define_method(cRenderer, "draw_rect", renderer_draw_rect, -1);
    rb_define_method(cRenderer, "draw_line", renderer_draw_line, -1);
    rb_define_method(cRenderer, "output_size", renderer_output_size, 0);
    rb_define_method(cRenderer, "read_pixels", renderer_read_pixels, 0);
    rb_define_method(cRenderer, "create_texture", renderer_create_texture, -1);
    rb_define_method(cRenderer, "copy", renderer_copy, -1);
    rb_define_method(cRenderer, "destroy", renderer_destroy, 0);
    rb_define_method(cRenderer, "destroyed?", renderer_destroyed_p, 0);

    /* Texture */
    cTexture = rb_define_class_under(mTeekSDL2, "Texture", rb_cObject);
    rb_define_alloc_func(cTexture, texture_alloc);
    rb_define_method(cTexture, "update", texture_update, 1);
    rb_define_method(cTexture, "width", texture_width, 0);
    rb_define_method(cTexture, "height", texture_height, 0);
    rb_define_method(cTexture, "blend_mode=", texture_set_blend_mode, 1);
    rb_define_method(cTexture, "blend_mode", texture_get_blend_mode, 0);
    rb_define_method(cTexture, "destroy", texture_destroy, 0);
    rb_define_method(cTexture, "destroyed?", texture_destroyed_p, 0);

    /* Module-level blend mode composition */
    rb_define_module_function(mTeekSDL2, "compose_blend_mode", sdl2_compose_blend_mode, 6);
}
