/*
 * tkeventsource.c - External event source integration via Tcl_CreateEventSource
 *
 * Allows other C extensions (e.g. teek-sdl2) to register poll callbacks
 * that run inside Tcl's event loop with zero Ruby overhead in the hot path.
 *
 * The consumer passes a C function pointer via a Ruby method call at
 * registration time. The Tcl event source setup/check procs call that
 * pointer directly — no rb_funcall, no method dispatch.
 */

#include "tcltkbridge.h"
#include <stdint.h>

static VALUE cEventSource;

/* ---------------------------------------------------------
 * Event source struct — wrapped as Ruby TypedData
 * --------------------------------------------------------- */

typedef void (*event_source_check_fn)(void *client_data);

struct event_source {
    event_source_check_fn check_fn;  /* C function pointer from consumer */
    void *client_data;               /* Opaque data from consumer */
    Tcl_Time max_block;              /* Max block time for setup proc */
    int registered;                  /* Whether Tcl event source is active */
};

/* Forward declarations */
static void es_setup_proc(ClientData cd, int flags);
static void es_check_proc(ClientData cd, int flags);

/* ---------------------------------------------------------
 * TypedData functions
 * --------------------------------------------------------- */

static void
event_source_free(void *ptr)
{
    struct event_source *es = ptr;
    if (es->registered) {
        Tcl_DeleteEventSource(es_setup_proc, es_check_proc, (ClientData)es);
        es->registered = 0;
    }
    xfree(es);
}

static size_t
event_source_memsize(const void *ptr)
{
    return sizeof(struct event_source);
}

static const rb_data_type_t event_source_type = {
    .wrap_struct_name = "Teek::EventSource",
    .function = {
        .dmark = NULL,  /* No Ruby VALUEs to mark */
        .dfree = event_source_free,
        .dsize = event_source_memsize,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

/* ---------------------------------------------------------
 * Tcl event source callbacks (hot path — pure C)
 * --------------------------------------------------------- */

/*
 * Setup proc: called before Tcl_WaitForEvent.
 * Caps the block time so our check proc runs frequently.
 */
static void
es_setup_proc(ClientData cd, int flags)
{
    struct event_source *es = (struct event_source *)cd;

    if (!(flags & TCL_FILE_EVENTS) && !(flags & TCL_ALL_EVENTS))
        return;

    Tcl_SetMaxBlockTime(&es->max_block);
}

/*
 * Check proc: called after Tcl_WaitForEvent returns.
 * Calls the consumer's C function pointer directly.
 * No rb_funcall, no Ruby method dispatch — just a function pointer call.
 */
static void
es_check_proc(ClientData cd, int flags)
{
    struct event_source *es = (struct event_source *)cd;

    if (!(flags & TCL_FILE_EVENTS) && !(flags & TCL_ALL_EVENTS))
        return;

    es->check_fn(es->client_data);
}

/* ---------------------------------------------------------
 * Ruby methods
 * --------------------------------------------------------- */

/*
 * Teek._register_event_source(check_fn_ptr, client_data_ptr, interval_ms) -> EventSource
 *
 * Registers a C function as a Tcl event source. The function will be called
 * on every event loop iteration with no Ruby overhead.
 *
 * check_fn_ptr:    Integer — address of a C function with signature void(*)(void*)
 * client_data_ptr: Integer — address passed to check_fn (0 for NULL)
 * interval_ms:     Integer — max block time in ms (e.g. 16 for ~60fps)
 *
 * Returns an opaque EventSource object. Hold a reference to keep it alive.
 * Call #unregister or let GC collect it to remove the event source.
 */
static VALUE
teek_register_event_source(VALUE self, VALUE fn_ptr, VALUE data_ptr, VALUE interval)
{
    struct event_source *es;
    VALUE obj;
    int ms;

    /* Validate */
    event_source_check_fn fn = (event_source_check_fn)(uintptr_t)NUM2ULL(fn_ptr);
    if (!fn) {
        rb_raise(rb_eArgError, "check_fn_ptr must not be NULL");
    }

    ms = NUM2INT(interval);
    if (ms < 1) ms = 1;

    /* Allocate and populate */
    obj = TypedData_Make_Struct(cEventSource, struct event_source, &event_source_type, es);
    es->check_fn = fn;
    es->client_data = (void *)(uintptr_t)NUM2ULL(data_ptr);
    es->max_block.sec = ms / 1000;
    es->max_block.usec = (ms % 1000) * 1000;
    es->registered = 0;

    /* Register with Tcl */
    Tcl_CreateEventSource(es_setup_proc, es_check_proc, (ClientData)es);
    es->registered = 1;

    return obj;
}

/*
 * EventSource#unregister -> nil
 *
 * Explicitly removes the event source from Tcl's notifier.
 * Safe to call multiple times.
 */
static VALUE
event_source_unregister(VALUE self)
{
    struct event_source *es;
    TypedData_Get_Struct(self, struct event_source, &event_source_type, es);

    if (es->registered) {
        Tcl_DeleteEventSource(es_setup_proc, es_check_proc, (ClientData)es);
        es->registered = 0;
    }
    return Qnil;
}

/*
 * EventSource#registered? -> true/false
 */
static VALUE
event_source_registered_p(VALUE self)
{
    struct event_source *es;
    TypedData_Get_Struct(self, struct event_source, &event_source_type, es);
    return es->registered ? Qtrue : Qfalse;
}

/* ---------------------------------------------------------
 * Init — called from Init_tcltklib
 * --------------------------------------------------------- */

static VALUE cEventSource;

void
Init_tkeventsource(VALUE mTeek)
{
    cEventSource = rb_define_class_under(mTeek, "EventSource", rb_cObject);
    rb_undef_alloc_func(cEventSource);  /* No Ruby-side new */

    rb_define_method(cEventSource, "unregister", event_source_unregister, 0);
    rb_define_method(cEventSource, "registered?", event_source_registered_p, 0);

    rb_define_module_function(mTeek, "_register_event_source",
                             teek_register_event_source, 3);
}
