#include "teek_sdl2.h"

/* ---------------------------------------------------------
 * SDL2 GameController wrapper
 *
 * Provides gamepad discovery, button/axis polling, rumble,
 * and event callbacks. Uses SDL_GameController (not raw
 * Joystick) for automatic Xbox-style button mapping.
 * --------------------------------------------------------- */

static VALUE cGamepad;
static int gc_subsystem_initialized = 0;

/* Event callback procs (module-level) */
static VALUE cb_on_button  = Qnil;
static VALUE cb_on_axis    = Qnil;
static VALUE cb_on_added   = Qnil;
static VALUE cb_on_removed = Qnil;

/* Symbol table for buttons and axes */
static VALUE sym_a, sym_b, sym_x, sym_y;
static VALUE sym_back, sym_guide, sym_start;
static VALUE sym_left_stick, sym_right_stick;
static VALUE sym_left_shoulder, sym_right_shoulder;
static VALUE sym_dpad_up, sym_dpad_down, sym_dpad_left, sym_dpad_right;
/* Axes */
static VALUE sym_left_x, sym_left_y, sym_right_x, sym_right_y;
static VALUE sym_trigger_left, sym_trigger_right;

static void
ensure_gc_init(void)
{
    if (gc_subsystem_initialized) return;

    if (!(SDL_WasInit(SDL_INIT_GAMECONTROLLER) & SDL_INIT_GAMECONTROLLER)) {
        if (SDL_InitSubSystem(SDL_INIT_GAMECONTROLLER) < 0) {
            rb_raise(rb_eRuntimeError,
                     "SDL_InitSubSystem(GAMECONTROLLER) failed: %s",
                     SDL_GetError());
        }
    }
    gc_subsystem_initialized = 1;
}

/* ---------------------------------------------------------
 * Button/axis symbol mapping
 * --------------------------------------------------------- */

static VALUE
button_to_sym(SDL_GameControllerButton btn)
{
    switch (btn) {
    case SDL_CONTROLLER_BUTTON_A:              return sym_a;
    case SDL_CONTROLLER_BUTTON_B:              return sym_b;
    case SDL_CONTROLLER_BUTTON_X:              return sym_x;
    case SDL_CONTROLLER_BUTTON_Y:              return sym_y;
    case SDL_CONTROLLER_BUTTON_BACK:           return sym_back;
    case SDL_CONTROLLER_BUTTON_GUIDE:          return sym_guide;
    case SDL_CONTROLLER_BUTTON_START:          return sym_start;
    case SDL_CONTROLLER_BUTTON_LEFTSTICK:      return sym_left_stick;
    case SDL_CONTROLLER_BUTTON_RIGHTSTICK:      return sym_right_stick;
    case SDL_CONTROLLER_BUTTON_LEFTSHOULDER:   return sym_left_shoulder;
    case SDL_CONTROLLER_BUTTON_RIGHTSHOULDER:   return sym_right_shoulder;
    case SDL_CONTROLLER_BUTTON_DPAD_UP:        return sym_dpad_up;
    case SDL_CONTROLLER_BUTTON_DPAD_DOWN:      return sym_dpad_down;
    case SDL_CONTROLLER_BUTTON_DPAD_LEFT:      return sym_dpad_left;
    case SDL_CONTROLLER_BUTTON_DPAD_RIGHT:     return sym_dpad_right;
    default:                                    return Qnil;
    }
}

static SDL_GameControllerButton
sym_to_button(VALUE sym)
{
    if (sym == sym_a)              return SDL_CONTROLLER_BUTTON_A;
    if (sym == sym_b)              return SDL_CONTROLLER_BUTTON_B;
    if (sym == sym_x)              return SDL_CONTROLLER_BUTTON_X;
    if (sym == sym_y)              return SDL_CONTROLLER_BUTTON_Y;
    if (sym == sym_back)           return SDL_CONTROLLER_BUTTON_BACK;
    if (sym == sym_guide)          return SDL_CONTROLLER_BUTTON_GUIDE;
    if (sym == sym_start)          return SDL_CONTROLLER_BUTTON_START;
    if (sym == sym_left_stick)     return SDL_CONTROLLER_BUTTON_LEFTSTICK;
    if (sym == sym_right_stick)    return SDL_CONTROLLER_BUTTON_RIGHTSTICK;
    if (sym == sym_left_shoulder)  return SDL_CONTROLLER_BUTTON_LEFTSHOULDER;
    if (sym == sym_right_shoulder) return SDL_CONTROLLER_BUTTON_RIGHTSHOULDER;
    if (sym == sym_dpad_up)        return SDL_CONTROLLER_BUTTON_DPAD_UP;
    if (sym == sym_dpad_down)      return SDL_CONTROLLER_BUTTON_DPAD_DOWN;
    if (sym == sym_dpad_left)      return SDL_CONTROLLER_BUTTON_DPAD_LEFT;
    if (sym == sym_dpad_right)     return SDL_CONTROLLER_BUTTON_DPAD_RIGHT;
    return SDL_CONTROLLER_BUTTON_INVALID;
}

static VALUE
axis_to_sym(SDL_GameControllerAxis ax)
{
    switch (ax) {
    case SDL_CONTROLLER_AXIS_LEFTX:        return sym_left_x;
    case SDL_CONTROLLER_AXIS_LEFTY:        return sym_left_y;
    case SDL_CONTROLLER_AXIS_RIGHTX:       return sym_right_x;
    case SDL_CONTROLLER_AXIS_RIGHTY:       return sym_right_y;
    case SDL_CONTROLLER_AXIS_TRIGGERLEFT:  return sym_trigger_left;
    case SDL_CONTROLLER_AXIS_TRIGGERRIGHT: return sym_trigger_right;
    default:                                return Qnil;
    }
}

static SDL_GameControllerAxis
sym_to_axis(VALUE sym)
{
    if (sym == sym_left_x)        return SDL_CONTROLLER_AXIS_LEFTX;
    if (sym == sym_left_y)        return SDL_CONTROLLER_AXIS_LEFTY;
    if (sym == sym_right_x)       return SDL_CONTROLLER_AXIS_RIGHTX;
    if (sym == sym_right_y)       return SDL_CONTROLLER_AXIS_RIGHTY;
    if (sym == sym_trigger_left)  return SDL_CONTROLLER_AXIS_TRIGGERLEFT;
    if (sym == sym_trigger_right) return SDL_CONTROLLER_AXIS_TRIGGERRIGHT;
    return SDL_CONTROLLER_AXIS_INVALID;
}

/* ---------------------------------------------------------
 * Gamepad struct (wraps SDL_GameController)
 * --------------------------------------------------------- */

struct sdl2_gamepad {
    SDL_GameController *controller;
    SDL_JoystickID      instance_id;
    int                 destroyed;
};

static void
gamepad_free(void *ptr)
{
    struct sdl2_gamepad *gp = ptr;
    if (!gp->destroyed && gp->controller) {
        SDL_GameControllerClose(gp->controller);
        gp->controller = NULL;
        gp->destroyed = 1;
    }
    xfree(gp);
}

static size_t
gamepad_memsize(const void *ptr)
{
    return sizeof(struct sdl2_gamepad);
}

static const rb_data_type_t gamepad_type = {
    .wrap_struct_name = "TeekSDL2::Gamepad",
    .function = {
        .dmark = NULL,
        .dfree = gamepad_free,
        .dsize = gamepad_memsize,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE
gamepad_alloc(VALUE klass)
{
    struct sdl2_gamepad *gp;
    VALUE obj = TypedData_Make_Struct(klass, struct sdl2_gamepad, &gamepad_type, gp);
    gp->controller = NULL;
    gp->instance_id = -1;
    gp->destroyed = 0;
    return obj;
}

static struct sdl2_gamepad *
get_gamepad(VALUE self)
{
    struct sdl2_gamepad *gp;
    TypedData_Get_Struct(self, struct sdl2_gamepad, &gamepad_type, gp);
    if (gp->destroyed || gp->controller == NULL) {
        rb_raise(rb_eRuntimeError, "gamepad has been closed");
    }
    return gp;
}

/* ---------------------------------------------------------
 * Gamepad class methods
 * --------------------------------------------------------- */

/*
 * Teek::SDL2::Gamepad.init_subsystem
 *
 * Explicitly initializes the gamepad subsystem. Called automatically
 * by other methods, but can be called early for hot-plug detection.
 */
static VALUE
gamepad_s_init_subsystem(VALUE klass)
{
    ensure_gc_init();
    return Qnil;
}

/*
 * Teek::SDL2::Gamepad.shutdown_subsystem
 *
 * Shuts down the gamepad subsystem. Existing Gamepad objects become invalid.
 */
static VALUE
gamepad_s_shutdown_subsystem(VALUE klass)
{
    if (gc_subsystem_initialized) {
        SDL_QuitSubSystem(SDL_INIT_GAMECONTROLLER);
        gc_subsystem_initialized = 0;
    }
    return Qnil;
}

/*
 * Teek::SDL2::Gamepad.count -> Integer
 *
 * Returns the number of connected gamepads (devices recognized as
 * game controllers by SDL2).
 */
static VALUE
gamepad_s_count(VALUE klass)
{
    int n, count = 0;

    ensure_gc_init();
    n = SDL_NumJoysticks();
    for (int i = 0; i < n; i++) {
        if (SDL_IsGameController(i))
            count++;
    }
    return INT2NUM(count);
}

/*
 * Teek::SDL2::Gamepad.open(index) -> Gamepad
 *
 * Opens the gamepad at the given device index.
 * Raises ArgumentError if index is negative.
 * Raises RuntimeError if the index is out of range or the device
 * cannot be opened.
 */
static VALUE
gamepad_s_open(VALUE klass, VALUE idx_val)
{
    int idx;
    SDL_GameController *ctrl;
    SDL_Joystick *joy;
    struct sdl2_gamepad *gp;
    VALUE obj;

    ensure_gc_init();
    idx = NUM2INT(idx_val);

    if (idx < 0) {
        rb_raise(rb_eArgError, "gamepad index must be non-negative, got %d", idx);
    }

    if (idx >= SDL_NumJoysticks()) {
        rb_raise(rb_eRuntimeError,
                 "gamepad index %d out of range (only %d joystick(s) connected)",
                 idx, SDL_NumJoysticks());
    }

    if (!SDL_IsGameController(idx)) {
        rb_raise(rb_eRuntimeError,
                 "device at index %d is not a game controller", idx);
    }

    ctrl = SDL_GameControllerOpen(idx);
    if (!ctrl) {
        rb_raise(rb_eRuntimeError,
                 "failed to open gamepad at index %d: %s",
                 idx, SDL_GetError());
    }

    obj = gamepad_alloc(klass);
    TypedData_Get_Struct(obj, struct sdl2_gamepad, &gamepad_type, gp);
    gp->controller = ctrl;

    joy = SDL_GameControllerGetJoystick(ctrl);
    gp->instance_id = SDL_JoystickInstanceID(joy);

    return obj;
}

/*
 * Teek::SDL2::Gamepad.first -> Gamepad or nil
 *
 * Opens the first available gamepad, or returns nil if none connected.
 */
static VALUE
gamepad_s_first(VALUE klass)
{
    int n;

    ensure_gc_init();
    n = SDL_NumJoysticks();
    for (int i = 0; i < n; i++) {
        if (SDL_IsGameController(i)) {
            return gamepad_s_open(klass, INT2NUM(i));
        }
    }
    return Qnil;
}

/*
 * Teek::SDL2::Gamepad.all -> Array of Gamepad
 *
 * Opens and returns all connected gamepads.
 */
static VALUE
gamepad_s_all(VALUE klass)
{
    int n;
    VALUE ary;

    ensure_gc_init();
    ary = rb_ary_new();
    n = SDL_NumJoysticks();
    for (int i = 0; i < n; i++) {
        if (SDL_IsGameController(i)) {
            rb_ary_push(ary, gamepad_s_open(klass, INT2NUM(i)));
        }
    }
    return ary;
}

/* ---------------------------------------------------------
 * Gamepad instance methods
 * --------------------------------------------------------- */

/*
 * Gamepad#name -> String
 *
 * Returns the human-readable name of the controller.
 */
static VALUE
gamepad_name(VALUE self)
{
    struct sdl2_gamepad *gp = get_gamepad(self);
    const char *name = SDL_GameControllerName(gp->controller);
    if (!name) return rb_str_new_cstr("Unknown");
    return rb_str_new_cstr(name);
}

/*
 * Gamepad#attached? -> true or false
 *
 * Returns true if the controller is still physically connected.
 */
static VALUE
gamepad_attached_p(VALUE self)
{
    struct sdl2_gamepad *gp = get_gamepad(self);
    return SDL_GameControllerGetAttached(gp->controller) ? Qtrue : Qfalse;
}

/*
 * Gamepad#button?(sym) -> true or false
 *
 * Returns true if the given button is currently pressed.
 * Valid symbols: :a, :b, :x, :y, :back, :guide, :start,
 * :left_stick, :right_stick, :left_shoulder, :right_shoulder,
 * :dpad_up, :dpad_down, :dpad_left, :dpad_right
 */
static VALUE
gamepad_button_p(VALUE self, VALUE btn_sym)
{
    struct sdl2_gamepad *gp = get_gamepad(self);
    SDL_GameControllerButton btn;

    Check_Type(btn_sym, T_SYMBOL);
    btn = sym_to_button(btn_sym);
    if (btn == SDL_CONTROLLER_BUTTON_INVALID) {
        rb_raise(rb_eArgError, "unknown button: %"PRIsVALUE, btn_sym);
    }

    return SDL_GameControllerGetButton(gp->controller, btn) ? Qtrue : Qfalse;
}

/*
 * Gamepad#axis(sym) -> Integer
 *
 * Returns the current value of an analog axis.
 * Stick axes: -32768..32767
 * Trigger axes: 0..32767
 * Valid symbols: :left_x, :left_y, :right_x, :right_y,
 * :trigger_left, :trigger_right
 */
static VALUE
gamepad_axis(VALUE self, VALUE axis_sym)
{
    struct sdl2_gamepad *gp = get_gamepad(self);
    SDL_GameControllerAxis ax;
    Sint16 val;

    Check_Type(axis_sym, T_SYMBOL);
    ax = sym_to_axis(axis_sym);
    if (ax == SDL_CONTROLLER_AXIS_INVALID) {
        rb_raise(rb_eArgError, "unknown axis: %"PRIsVALUE, axis_sym);
    }

    val = SDL_GameControllerGetAxis(gp->controller, ax);
    return INT2NUM(val);
}

/*
 * Gamepad#instance_id -> Integer
 *
 * Returns the SDL joystick instance ID for this controller.
 * Useful for matching with event callbacks.
 */
static VALUE
gamepad_instance_id(VALUE self)
{
    struct sdl2_gamepad *gp = get_gamepad(self);
    return INT2NUM(gp->instance_id);
}

/*
 * Gamepad#rumble(low_freq, high_freq, duration_ms) -> true or false
 *
 * Triggers haptic feedback (rumble). Returns true on success.
 * low_freq and high_freq are 0..65535, duration_ms is milliseconds.
 */
static VALUE
gamepad_rumble(VALUE self, VALUE low, VALUE high, VALUE duration)
{
    struct sdl2_gamepad *gp = get_gamepad(self);
    Uint16 lo = (Uint16)NUM2UINT(low);
    Uint16 hi = (Uint16)NUM2UINT(high);
    Uint32 ms = (Uint32)NUM2UINT(duration);

    int rc = SDL_GameControllerRumble(gp->controller, lo, hi, ms);
    return rc == 0 ? Qtrue : Qfalse;
}

/*
 * Gamepad#close -> nil
 * Gamepad#destroy -> nil
 *
 * Closes the controller. Further method calls will raise.
 */
static VALUE
gamepad_close(VALUE self)
{
    struct sdl2_gamepad *gp;
    TypedData_Get_Struct(self, struct sdl2_gamepad, &gamepad_type, gp);

    if (!gp->destroyed && gp->controller) {
        SDL_GameControllerClose(gp->controller);
        gp->controller = NULL;
        gp->destroyed = 1;
    }
    return Qnil;
}

/*
 * Gamepad#closed? -> true or false
 * Gamepad#destroyed? -> true or false
 */
static VALUE
gamepad_closed_p(VALUE self)
{
    struct sdl2_gamepad *gp;
    TypedData_Get_Struct(self, struct sdl2_gamepad, &gamepad_type, gp);
    return (gp->destroyed || gp->controller == NULL) ? Qtrue : Qfalse;
}

/* ---------------------------------------------------------
 * Event polling
 *
 * Gamepad.poll_events processes SDL events and dispatches
 * to registered Ruby callbacks. Designed to be called from
 * a Tcl timer or game loop.
 * --------------------------------------------------------- */

/*
 * Gamepad.poll_events -> Integer
 *
 * Pumps SDL events and dispatches gamepad-related events to
 * registered callbacks. Returns the number of events processed.
 * Call this periodically (e.g. every 16ms) for responsive input.
 */
static VALUE
gamepad_s_poll_events(VALUE klass)
{
    SDL_Event ev;
    int count = 0;

    if (!gc_subsystem_initialized) return INT2NUM(0);

    while (SDL_PollEvent(&ev)) {
        switch (ev.type) {
        case SDL_CONTROLLERBUTTONDOWN:
        case SDL_CONTROLLERBUTTONUP:
            if (cb_on_button != Qnil) {
                VALUE btn = button_to_sym((SDL_GameControllerButton)ev.cbutton.button);
                if (btn != Qnil) {
                    VALUE pressed = (ev.type == SDL_CONTROLLERBUTTONDOWN) ? Qtrue : Qfalse;
                    VALUE args[3];
                    args[0] = INT2NUM(ev.cbutton.which);
                    args[1] = btn;
                    args[2] = pressed;
                    rb_proc_call_with_block(cb_on_button, 3, args, Qnil);
                }
            }
            count++;
            break;

        case SDL_CONTROLLERAXISMOTION:
            if (cb_on_axis != Qnil) {
                VALUE ax = axis_to_sym((SDL_GameControllerAxis)ev.caxis.axis);
                if (ax != Qnil) {
                    VALUE args[3];
                    args[0] = INT2NUM(ev.caxis.which);
                    args[1] = ax;
                    args[2] = INT2NUM(ev.caxis.value);
                    rb_proc_call_with_block(cb_on_axis, 3, args, Qnil);
                }
            }
            count++;
            break;

        case SDL_CONTROLLERDEVICEADDED:
            if (cb_on_added != Qnil) {
                VALUE args[1];
                args[0] = INT2NUM(ev.cdevice.which);
                rb_proc_call_with_block(cb_on_added, 1, args, Qnil);
            }
            count++;
            break;

        case SDL_CONTROLLERDEVICEREMOVED:
            if (cb_on_removed != Qnil) {
                VALUE args[1];
                args[0] = INT2NUM(ev.cdevice.which);
                rb_proc_call_with_block(cb_on_removed, 1, args, Qnil);
            }
            count++;
            break;

        default:
            break;
        }
    }
    return INT2NUM(count);
}

/* ---------------------------------------------------------
 * Callback registration
 * --------------------------------------------------------- */

/*
 * Gamepad.on_button { |instance_id, button_sym, pressed| ... }
 *
 * Registers a callback for button press/release events.
 */
static VALUE
gamepad_s_on_button(VALUE klass)
{
    rb_need_block();
    cb_on_button = rb_block_proc();
    return Qnil;
}

/*
 * Gamepad.on_axis { |instance_id, axis_sym, value| ... }
 *
 * Registers a callback for axis motion events.
 */
static VALUE
gamepad_s_on_axis(VALUE klass)
{
    rb_need_block();
    cb_on_axis = rb_block_proc();
    return Qnil;
}

/*
 * Gamepad.on_added { |device_index| ... }
 *
 * Registers a callback for when a new gamepad is connected.
 */
static VALUE
gamepad_s_on_added(VALUE klass)
{
    rb_need_block();
    cb_on_added = rb_block_proc();
    return Qnil;
}

/*
 * Gamepad.on_removed { |instance_id| ... }
 *
 * Registers a callback for when a gamepad is disconnected.
 */
static VALUE
gamepad_s_on_removed(VALUE klass)
{
    rb_need_block();
    cb_on_removed = rb_block_proc();
    return Qnil;
}

/* ---------------------------------------------------------
 * Virtual gamepad (for testing without physical hardware)
 *
 * Uses SDL_JoystickAttachVirtualEx (SDL 2.24+) to create a
 * software gamepad that can be opened, polled, and have
 * button/axis state set programmatically.
 * --------------------------------------------------------- */

static int virtual_device_index = -1;

/*
 * Gamepad.attach_virtual -> Integer
 *
 * Creates a virtual gamepad device. Returns the device index
 * which can be passed to Gamepad.open. Call detach_virtual
 * when done. Raises if a virtual device is already attached.
 */
static VALUE
gamepad_s_attach_virtual(VALUE klass)
{
    SDL_VirtualJoystickDesc desc;
    int idx;

    ensure_gc_init();

    if (virtual_device_index >= 0) {
        rb_raise(rb_eRuntimeError, "virtual gamepad already attached");
    }

    SDL_zero(desc);
    desc.version    = SDL_VIRTUAL_JOYSTICK_DESC_VERSION;
    desc.type       = SDL_JOYSTICK_TYPE_GAMECONTROLLER;
    desc.naxes      = SDL_CONTROLLER_AXIS_MAX;
    desc.nbuttons   = SDL_CONTROLLER_BUTTON_MAX;
    desc.nhats      = 0;
    desc.vendor_id  = 0;
    desc.product_id = 0;
    desc.name       = "Teek Virtual Gamepad";

    idx = SDL_JoystickAttachVirtualEx(&desc);
    if (idx < 0) {
        rb_raise(rb_eRuntimeError,
                 "failed to attach virtual gamepad: %s", SDL_GetError());
    }
    virtual_device_index = idx;
    return INT2NUM(idx);
}

/*
 * Gamepad.detach_virtual -> nil
 *
 * Removes the virtual gamepad device created by attach_virtual.
 */
static VALUE
gamepad_s_detach_virtual(VALUE klass)
{
    if (virtual_device_index >= 0) {
        SDL_JoystickDetachVirtual(virtual_device_index);
        virtual_device_index = -1;
    }
    return Qnil;
}

/*
 * Gamepad.virtual_device_index -> Integer or nil
 *
 * Returns the device index of the virtual gamepad, or nil if
 * no virtual device is attached.
 */
static VALUE
gamepad_s_virtual_device_index(VALUE klass)
{
    if (virtual_device_index < 0) return Qnil;
    return INT2NUM(virtual_device_index);
}

/*
 * Gamepad#set_virtual_button(button_sym, pressed) -> nil
 *
 * Sets the state of a button on a virtual gamepad.
 * Only works on gamepads opened from a virtual device.
 */
static VALUE
gamepad_set_virtual_button(VALUE self, VALUE btn_sym, VALUE pressed)
{
    struct sdl2_gamepad *gp = get_gamepad(self);
    SDL_Joystick *joy;
    SDL_GameControllerButton btn;
    Uint8 state;

    Check_Type(btn_sym, T_SYMBOL);
    btn = sym_to_button(btn_sym);
    if (btn == SDL_CONTROLLER_BUTTON_INVALID) {
        rb_raise(rb_eArgError, "unknown button: %"PRIsVALUE, btn_sym);
    }

    joy = SDL_GameControllerGetJoystick(gp->controller);
    state = RTEST(pressed) ? SDL_PRESSED : SDL_RELEASED;

    if (SDL_JoystickSetVirtualButton(joy, btn, state) < 0) {
        rb_raise(rb_eRuntimeError, "failed to set virtual button: %s",
                 SDL_GetError());
    }
    return Qnil;
}

/*
 * Gamepad#set_virtual_axis(axis_sym, value) -> nil
 *
 * Sets the value of an axis on a virtual gamepad.
 * Only works on gamepads opened from a virtual device.
 * Stick axes: -32768..32767, trigger axes: 0..32767.
 */
static VALUE
gamepad_set_virtual_axis(VALUE self, VALUE axis_sym, VALUE val)
{
    struct sdl2_gamepad *gp = get_gamepad(self);
    SDL_Joystick *joy;
    SDL_GameControllerAxis ax;
    Sint16 v;

    Check_Type(axis_sym, T_SYMBOL);
    ax = sym_to_axis(axis_sym);
    if (ax == SDL_CONTROLLER_AXIS_INVALID) {
        rb_raise(rb_eArgError, "unknown axis: %"PRIsVALUE, axis_sym);
    }

    joy = SDL_GameControllerGetJoystick(gp->controller);
    v = (Sint16)NUM2INT(val);

    if (SDL_JoystickSetVirtualAxis(joy, ax, v) < 0) {
        rb_raise(rb_eRuntimeError, "failed to set virtual axis: %s",
                 SDL_GetError());
    }
    return Qnil;
}

/* ---------------------------------------------------------
 * Buttons / Axes constant arrays (for introspection)
 * --------------------------------------------------------- */

/*
 * Gamepad::BUTTONS -> Array of Symbol
 *
 * Returns the list of valid button symbols.
 */
static VALUE
gamepad_s_buttons(VALUE klass)
{
    VALUE ary = rb_ary_new_capa(15);
    rb_ary_push(ary, sym_a);
    rb_ary_push(ary, sym_b);
    rb_ary_push(ary, sym_x);
    rb_ary_push(ary, sym_y);
    rb_ary_push(ary, sym_back);
    rb_ary_push(ary, sym_guide);
    rb_ary_push(ary, sym_start);
    rb_ary_push(ary, sym_left_stick);
    rb_ary_push(ary, sym_right_stick);
    rb_ary_push(ary, sym_left_shoulder);
    rb_ary_push(ary, sym_right_shoulder);
    rb_ary_push(ary, sym_dpad_up);
    rb_ary_push(ary, sym_dpad_down);
    rb_ary_push(ary, sym_dpad_left);
    rb_ary_push(ary, sym_dpad_right);
    return ary;
}

/*
 * Gamepad::AXES -> Array of Symbol
 *
 * Returns the list of valid axis symbols.
 */
static VALUE
gamepad_s_axes(VALUE klass)
{
    VALUE ary = rb_ary_new_capa(6);
    rb_ary_push(ary, sym_left_x);
    rb_ary_push(ary, sym_left_y);
    rb_ary_push(ary, sym_right_x);
    rb_ary_push(ary, sym_right_y);
    rb_ary_push(ary, sym_trigger_left);
    rb_ary_push(ary, sym_trigger_right);
    return ary;
}

/* ---------------------------------------------------------
 * Init
 * --------------------------------------------------------- */

void
Init_sdl2gamepad(VALUE mTeekSDL2)
{
    /* Intern symbols once */
    sym_a              = ID2SYM(rb_intern("a"));
    sym_b              = ID2SYM(rb_intern("b"));
    sym_x              = ID2SYM(rb_intern("x"));
    sym_y              = ID2SYM(rb_intern("y"));
    sym_back           = ID2SYM(rb_intern("back"));
    sym_guide          = ID2SYM(rb_intern("guide"));
    sym_start          = ID2SYM(rb_intern("start"));
    sym_left_stick     = ID2SYM(rb_intern("left_stick"));
    sym_right_stick    = ID2SYM(rb_intern("right_stick"));
    sym_left_shoulder  = ID2SYM(rb_intern("left_shoulder"));
    sym_right_shoulder = ID2SYM(rb_intern("right_shoulder"));
    sym_dpad_up        = ID2SYM(rb_intern("dpad_up"));
    sym_dpad_down      = ID2SYM(rb_intern("dpad_down"));
    sym_dpad_left      = ID2SYM(rb_intern("dpad_left"));
    sym_dpad_right     = ID2SYM(rb_intern("dpad_right"));

    sym_left_x         = ID2SYM(rb_intern("left_x"));
    sym_left_y         = ID2SYM(rb_intern("left_y"));
    sym_right_x        = ID2SYM(rb_intern("right_x"));
    sym_right_y        = ID2SYM(rb_intern("right_y"));
    sym_trigger_left   = ID2SYM(rb_intern("trigger_left"));
    sym_trigger_right  = ID2SYM(rb_intern("trigger_right"));

    /* Protect callback procs from GC */
    rb_gc_register_address(&cb_on_button);
    rb_gc_register_address(&cb_on_axis);
    rb_gc_register_address(&cb_on_added);
    rb_gc_register_address(&cb_on_removed);

    /* Gamepad class */
    cGamepad = rb_define_class_under(mTeekSDL2, "Gamepad", rb_cObject);
    rb_define_alloc_func(cGamepad, gamepad_alloc);

    /* Class methods */
    rb_define_singleton_method(cGamepad, "init_subsystem",
                               gamepad_s_init_subsystem, 0);
    rb_define_singleton_method(cGamepad, "shutdown_subsystem",
                               gamepad_s_shutdown_subsystem, 0);
    rb_define_singleton_method(cGamepad, "count", gamepad_s_count, 0);
    rb_define_singleton_method(cGamepad, "open", gamepad_s_open, 1);
    rb_define_singleton_method(cGamepad, "first", gamepad_s_first, 0);
    rb_define_singleton_method(cGamepad, "all", gamepad_s_all, 0);
    rb_define_singleton_method(cGamepad, "poll_events",
                               gamepad_s_poll_events, 0);
    rb_define_singleton_method(cGamepad, "buttons", gamepad_s_buttons, 0);
    rb_define_singleton_method(cGamepad, "axes", gamepad_s_axes, 0);

    /* Virtual gamepad (for testing) */
    rb_define_singleton_method(cGamepad, "attach_virtual",
                               gamepad_s_attach_virtual, 0);
    rb_define_singleton_method(cGamepad, "detach_virtual",
                               gamepad_s_detach_virtual, 0);
    rb_define_singleton_method(cGamepad, "virtual_device_index",
                               gamepad_s_virtual_device_index, 0);

    /* Event callbacks */
    rb_define_singleton_method(cGamepad, "on_button", gamepad_s_on_button, 0);
    rb_define_singleton_method(cGamepad, "on_axis", gamepad_s_on_axis, 0);
    rb_define_singleton_method(cGamepad, "on_added", gamepad_s_on_added, 0);
    rb_define_singleton_method(cGamepad, "on_removed", gamepad_s_on_removed, 0);

    /* Instance methods */
    rb_define_method(cGamepad, "name", gamepad_name, 0);
    rb_define_method(cGamepad, "attached?", gamepad_attached_p, 0);
    rb_define_method(cGamepad, "button?", gamepad_button_p, 1);
    rb_define_method(cGamepad, "axis", gamepad_axis, 1);
    rb_define_method(cGamepad, "instance_id", gamepad_instance_id, 0);
    rb_define_method(cGamepad, "rumble", gamepad_rumble, 3);
    rb_define_method(cGamepad, "close", gamepad_close, 0);
    rb_define_method(cGamepad, "destroy", gamepad_close, 0);
    rb_define_method(cGamepad, "closed?", gamepad_closed_p, 0);
    rb_define_method(cGamepad, "destroyed?", gamepad_closed_p, 0);

    /* Virtual gamepad instance methods */
    rb_define_method(cGamepad, "set_virtual_button",
                     gamepad_set_virtual_button, 2);
    rb_define_method(cGamepad, "set_virtual_axis",
                     gamepad_set_virtual_axis, 2);
}
