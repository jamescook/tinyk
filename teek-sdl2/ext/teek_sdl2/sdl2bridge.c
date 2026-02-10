#include "teek_sdl2.h"

/* ---------------------------------------------------------
 * Layer 2: Tk bridge
 *
 * Embeds an SDL2 window into a Tk frame using
 * SDL_CreateWindowFrom(). This is the only file that knows
 * about Tk's winfo id. It produces a Layer 1 Renderer.
 * --------------------------------------------------------- */

/*
 * Teek::SDL2.create_renderer_from_handle(native_handle) -> Renderer
 *
 * Creates an SDL2 window embedded in the native window identified by
 * native_handle (from Tk's 'winfo id'), then creates a GPU-accelerated
 * renderer on it.
 *
 * The Ruby Viewport class is responsible for getting the handle and
 * calling this. This C function just does the SDL2 work.
 */
static VALUE
bridge_create_renderer_from_handle(VALUE self, VALUE handle_val)
{
    ensure_sdl2_init();

    /*
     * Handle comes from Teek::Interp#native_window_handle as an Integer:
     *   macOS: NSWindow* pointer
     *   X11:   X Window ID
     *   Win:   HWND
     */
    void *native_handle = (void *)(uintptr_t)NUM2ULL(handle_val);

    if (!native_handle) {
        rb_raise(rb_eArgError, "invalid native handle (NULL)");
    }

    SDL_Window *window = SDL_CreateWindowFrom(native_handle);
    if (!window) {
        rb_raise(rb_eRuntimeError, "SDL_CreateWindowFrom failed: %s", SDL_GetError());
    }

    SDL_Renderer *sdl_ren = SDL_CreateRenderer(window, -1,
        SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (!sdl_ren) {
        /* Fall back to software if GPU not available */
        sdl_ren = SDL_CreateRenderer(window, -1, SDL_RENDERER_SOFTWARE);
    }
    if (!sdl_ren) {
        SDL_DestroyWindow(window);
        rb_raise(rb_eRuntimeError, "SDL_CreateRenderer failed: %s", SDL_GetError());
    }

    /* Wrap in a Renderer object (Layer 1) */
    VALUE klass = rb_const_get(mTeekSDL2, rb_intern("Renderer"));
    VALUE obj = rb_obj_alloc(klass);

    struct sdl2_renderer *r;
    TypedData_Get_Struct(obj, struct sdl2_renderer, &renderer_type, r);
    r->window = window;
    r->renderer = sdl_ren;
    r->owned_window = 0; /* Tk owns the parent window */
    r->destroyed = 0;

    return obj;
}

/*
 * C-level poll function — called directly from teek's event source
 * check proc via function pointer. No Ruby overhead.
 *
 * Signature: void (*)(void *client_data)
 */
static void
sdl2_event_check(void *client_data)
{
    (void)client_data;

    /*
     * Intentionally a no-op for now. SDL_PollEvent() on macOS pumps
     * the Cocoa run loop, which steals events from Tk and can freeze
     * other windows (e.g. the debug inspector).
     *
     * When we need SDL events (mouse/kb in the viewport), this will
     * be wired up carefully to avoid Cocoa event conflicts.
     */
}

/*
 * Teek::SDL2.poll_events -> Integer
 *
 * Manual pump for use outside the event source (e.g. testing).
 */
static VALUE
bridge_poll_events(VALUE self)
{
    SDL_Event event;
    int count = 0;

    while (SDL_PollEvent(&event)) {
        count++;
    }
    return INT2NUM(count);
}

/*
 * Teek::SDL2._event_check_fn_ptr -> Integer
 *
 * Returns the address of the C-level SDL2 event check function.
 * Passed to Teek._register_event_source for hot-path polling.
 */
static VALUE
bridge_event_check_fn_ptr(VALUE self)
{
    return ULL2NUM((uintptr_t)sdl2_event_check);
}

/*
 * Teek::SDL2.sdl_quit
 *
 * Shuts down SDL2 subsystems. Called at process exit.
 */
static VALUE
bridge_sdl_quit(VALUE self)
{
    SDL_Quit();
    return Qnil;
}

/* ---------------------------------------------------------
 * Init
 * --------------------------------------------------------- */

void
Init_sdl2bridge(VALUE mTeekSDL2)
{
    rb_define_module_function(mTeekSDL2, "create_renderer_from_handle",
                             bridge_create_renderer_from_handle, 1);
    rb_define_module_function(mTeekSDL2, "poll_events", bridge_poll_events, 0);
    rb_define_module_function(mTeekSDL2, "_event_check_fn_ptr", bridge_event_check_fn_ptr, 0);
    rb_define_module_function(mTeekSDL2, "sdl_quit", bridge_sdl_quit, 0);
}
