/*
 * tcltkbridge.c - Minimal Ruby/Tcl/Tk bridge
 *
 * Design goals:
 * - Thin C layer, logic in Ruby
 * - Clear method names (tcl_eval, tcl_invoke, etc.)
 * - Modern Ruby (3.2+), Tcl/Tk (8.6+)
 * - Always use stubs for version flexibility
 */

/* Stubs are enabled via extconf.rb (-DUSE_TCL_STUBS -DUSE_TK_STUBS) */

#include "ruby.h"
#include "ruby/encoding.h"
#include "ruby/thread.h"
#include <tcl.h>
#include <tk.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <dlfcn.h>
#endif

/* Tcl 8.x/9.x compatibility (Tcl_Size, etc.) */
#include "tcl9compat.h"

/* Shared types and function declarations */
#include "tcltkbridge.h"

/*
 * Bootstrap helpers: call Tcl functions before stubs are initialized.
 *
 * Tcl 9.0 pre-initializes tclStubsPtr, but Tcl 8.6 does not.
 * When tclStubsPtr is NULL, Tcl_CreateInterp() and Tcl_FindExecutable()
 * crash because they're macros that dereference tclStubsPtr.
 * We use dlsym/GetProcAddress to get the real function pointers and call them directly.
 */

#ifdef _WIN32
/* Windows: Get function from loaded Tcl DLL */
static void *get_tcl_proc(const char *name)
{
    /* Try common Tcl DLL names */
    static const char *dll_names[] = {"tcl86.dll", "tcl90.dll", "tcl86t.dll", "tcl90t.dll", NULL};
    HMODULE hmod;
    void *proc;
    int i;

    for (i = 0; dll_names[i]; i++) {
        hmod = GetModuleHandleA(dll_names[i]);
        if (hmod) {
            proc = (void *)GetProcAddress(hmod, name);
            if (proc) return proc;
        }
    }
    return NULL;
}
#endif

static void
find_executable_bootstrap(const char *argv0)
{
    if (tclStubsPtr != NULL) {
        Tcl_FindExecutable(argv0);
        return;
    }

    void (*real_find_executable)(const char *);
#ifdef _WIN32
    real_find_executable = (void (*)(const char *))get_tcl_proc("Tcl_FindExecutable");
#else
    real_find_executable = dlsym(RTLD_DEFAULT, "Tcl_FindExecutable");
#endif
    if (real_find_executable) {
        real_find_executable(argv0);
    }
}

static Tcl_Interp *
create_interp_bootstrap(void)
{
    if (tclStubsPtr != NULL) {
        return Tcl_CreateInterp();
    }

    Tcl_Interp *(*real_create_interp)(void);
#ifdef _WIN32
    real_create_interp = (Tcl_Interp *(*)(void))get_tcl_proc("Tcl_CreateInterp");
#else
    real_create_interp = dlsym(RTLD_DEFAULT, "Tcl_CreateInterp");
#endif
    if (!real_create_interp) {
        return NULL;
    }
    return real_create_interp();
}

/*
 * Version strings for Tcl_InitStubs/Tk_InitStubs.
 * Must match the major version we compiled against - Tcl's version
 * satisfaction requires same major number (9.x won't satisfy "8.6").
 * TCL_VERSION/TK_VERSION are defined in tcl.h/tk.h at compile time.
 */

/* Module and class handles */
static VALUE mTeek;
static VALUE cInterp;
VALUE eTclError;  /* Non-static: shared with tkphoto.c */

/* Track if stubs have been initialized (once per process) */
static int tcl_stubs_initialized = 0;

/* Track live interpreter instances for multi-interp safety checks */
static VALUE live_instances;  /* Ruby Array of live Teek::Interp objects */

/* Forward declaration for Tcl callback command */
static int ruby_callback_proc(ClientData, Tcl_Interp *, int, Tcl_Obj *const *);
static int ruby_eval_proc(ClientData, Tcl_Interp *, int, Tcl_Obj *const *);
static void interp_deleted_callback(ClientData, Tcl_Interp *);

/* Default timer interval for thread-aware mainloop (ms) */
/* 16ms ≈ 60fps - balances UI responsiveness with scheduler contention */
#define DEFAULT_TIMER_INTERVAL_MS 16

/* Global timer interval for TclTkLib.mainloop (mutable) */
static int g_thread_timer_ms = DEFAULT_TIMER_INTERVAL_MS;

/* struct tcltk_interp is defined in tcltkbridge.h */

/* ---------------------------------------------------------
 * Thread-safe event for cross-thread execution
 *
 * Background threads cannot safely call Tcl/Tk directly.
 * Uses Tcl's native Tcl_ThreadQueueEvent mechanism.
 *
 * Design: Command data is stored in Ruby objects (GC-protected in
 * thread_queue). The Tcl event just triggers execution.
 * --------------------------------------------------------- */

struct ruby_thread_event {
    Tcl_Event event;           /* Must be first - Tcl casts to this */
    struct tcltk_interp *tip;  /* Interpreter context */
};

/* Ruby Queue class for thread synchronization */
static VALUE cQueue = Qundef;

/* Track callback depth for unsafe operation detection */
static int rbtk_callback_depth = 0;

/* Callback control flow exceptions - for signaling break/continue/return to Tcl */
static VALUE eCallbackBreak;
static VALUE eCallbackContinue;
static VALUE eCallbackReturn;

/* ---------------------------------------------------------
 * Memory management
 * --------------------------------------------------------- */

static void
interp_mark(void *ptr)
{
    struct tcltk_interp *tip = ptr;
    rb_gc_mark(tip->callbacks);    /* Mark callback procs so GC doesn't collect them */
    rb_gc_mark(tip->thread_queue); /* Mark procs queued from other threads */
}

static void
interp_free(void *ptr)
{
    struct tcltk_interp *tip = ptr;
    if (tip->interp && !tip->deleted) {
        Tcl_DeleteInterp(tip->interp);
    }
    xfree(tip);
}

/* ---------------------------------------------------------
 * Callback invoked by Tcl when an interpreter is deleted
 *
 * This is registered via Tcl_CallWhenDeleted so that when Tcl
 * internally deletes an interpreter (e.g., via `interp delete`),
 * we update our Ruby-side state to reflect the deletion.
 * Without this, the Ruby object would think the interp is still
 * valid and using it would crash.
 * --------------------------------------------------------- */
static void
interp_deleted_callback(ClientData clientData, Tcl_Interp *interp)
{
    struct tcltk_interp *tip = (struct tcltk_interp *)clientData;
    tip->deleted = 1;
    tip->interp = NULL;  /* Don't hold stale pointer */
}

static size_t
interp_memsize(const void *ptr)
{
    return sizeof(struct tcltk_interp);
}

/* Non-static: shared with tkphoto.c */
const rb_data_type_t interp_type = {
    .wrap_struct_name = "TclTkBridge::Interp",
    .function = {
        .dmark = interp_mark,
        .dfree = interp_free,
        .dsize = interp_memsize,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE
interp_alloc(VALUE klass)
{
    struct tcltk_interp *tip;
    VALUE obj = TypedData_Make_Struct(klass, struct tcltk_interp, &interp_type, tip);
    tip->interp = NULL;
    tip->deleted = 0;
    tip->callbacks = rb_hash_new();
    tip->thread_queue = rb_ary_new();
    tip->next_id = 1;
    tip->timer_interval_ms = DEFAULT_TIMER_INTERVAL_MS;
    tip->main_thread_id = NULL;
    return obj;
}

/* Non-static: shared with tkphoto.c */
struct tcltk_interp *
get_interp(VALUE self)
{
    struct tcltk_interp *tip;
    TypedData_Get_Struct(self, struct tcltk_interp, &interp_type, tip);
    if (tip->deleted || tip->interp == NULL) {
        rb_raise(eTclError, "interpreter has been deleted");
    }
    return tip;
}

/* ---------------------------------------------------------
 * Interp#initialize(name=nil, opts={}) - Create Tcl interp and load Tk
 *
 * Arguments:
 *   name - Ignored (legacy compatibility)
 *   opts - Options hash
 *
 * Options:
 *   :thread_timer_ms - Timer interval for thread-aware mainloop (default: 5)
 *                      Controls how often Ruby threads get a chance to run
 *                      during Tk.mainloop.
 *
 *                      Tradeoffs:
 *                      - 1ms:  Very responsive threads, higher CPU when idle
 *                      - 5ms:  Good balance (default)
 *                      - 10ms: Lower CPU, slight thread latency
 *                      - 20ms: Minimal CPU, noticeable latency for threads
 *                      - 0:    Disable timer (threads won't run during mainloop)
 *
 * Initialization order (verified empirically on Tcl/Tk 9.0.3):
 * 1. Tcl_FindExecutable - sets up internal paths (NOT stubbed)
 * 2. Tcl_CreateInterp - create interpreter (NOT stubbed)
 * 3. Tcl_InitStubs - bootstrap stubs table
 * 4. Set argc/argv/argv0 - Tk_Init reads these
 * 5. Tcl_Init - load Tcl runtime
 * 6. Tk_Init - load Tk runtime (NOT stubbed - must come BEFORE Tk_InitStubs!)
 * 7. Tk_InitStubs - bootstrap Tk stubs table (AFTER Tk_Init)
 *
 * CRITICAL: Tk_Init before Tk_InitStubs. Tk_InitStubs internally calls
 * Tk_Init if not already done, causing "window already exists" error
 * if you then call Tk_Init yourself.
 * --------------------------------------------------------- */

static VALUE
interp_initialize(int argc, VALUE *argv, VALUE self)
{
    struct tcltk_interp *tip;
    const char *tcl_version;
    const char *tk_version;
    VALUE name, opts, val;

    TypedData_Get_Struct(self, struct tcltk_interp, &interp_type, tip);

    /* Parse legacy (name, opts) or new (opts) argument forms */
    rb_scan_args(argc, argv, "02", &name, &opts);
    /* name is ignored - kept for legacy compatibility */

    /* Check for options in opts hash */
    if (!NIL_P(opts) && TYPE(opts) == T_HASH) {
        val = rb_hash_aref(opts, ID2SYM(rb_intern("thread_timer_ms")));
        if (!NIL_P(val)) {
            int ms = NUM2INT(val);
            if (ms < 0) {
                rb_raise(rb_eArgError, "thread_timer_ms must be >= 0 (got %d)", ms);
            }
            tip->timer_interval_ms = ms;
        }
    }

    /* 1. Tell Tcl where to find itself (once per process) */
    if (!tcl_stubs_initialized) {
        find_executable_bootstrap("ruby");
    }

    /* 2. Create Tcl interpreter (using bootstrap to handle Tcl 8.6) */
    tip->interp = create_interp_bootstrap();
    if (tip->interp == NULL) {
        rb_raise(eTclError, "failed to create Tcl interpreter");
    }

    /* 3. Initialize Tcl stubs - MUST be before any other Tcl calls */
    tcl_version = Tcl_InitStubs(tip->interp, TCL_VERSION, 0);
    if (tcl_version == NULL) {
        const char *err = Tcl_GetStringResult(tip->interp);
        Tcl_DeleteInterp(tip->interp);
        tip->interp = NULL;
        rb_raise(eTclError, "Tcl_InitStubs failed: %s", err);
    }

    /* 4. Set up argc/argv/argv0 before Tcl_Init (required for proper init) */
    Tcl_Eval(tip->interp, "set argc 0; set argv {}; set argv0 tcltkbridge");

    /* 5. Initialize Tcl runtime */
    if (Tcl_Init(tip->interp) != TCL_OK) {
        const char *err = Tcl_GetStringResult(tip->interp);
        Tcl_DeleteInterp(tip->interp);
        tip->interp = NULL;
        rb_raise(eTclError, "Tcl_Init failed: %s", err);
    }

    /* 6. Initialize Tk runtime - must come BEFORE Tk_InitStubs */
    if (Tk_Init(tip->interp) != TCL_OK) {
        const char *err = Tcl_GetStringResult(tip->interp);
        Tcl_DeleteInterp(tip->interp);
        tip->interp = NULL;
        rb_raise(eTclError, "Tk_Init failed: %s", err);
    }

    /* 7. Initialize Tk stubs - after Tk_Init */
    tk_version = Tk_InitStubs(tip->interp, TK_VERSION, 0);
    if (tk_version == NULL) {
        const char *err = Tcl_GetStringResult(tip->interp);
        Tcl_DeleteInterp(tip->interp);
        tip->interp = NULL;
        rb_raise(eTclError, "Tk_InitStubs failed: %s", err);
    }

    tcl_stubs_initialized = 1;

    /* 8. Register Tcl commands for Ruby integration */
    Tcl_CreateObjCommand(tip->interp, "ruby_callback",
                         ruby_callback_proc, (ClientData)tip, NULL);
    Tcl_CreateObjCommand(tip->interp, "ruby",
                         ruby_eval_proc, (ClientData)tip, NULL);
    Tcl_CreateObjCommand(tip->interp, "ruby_eval",
                         ruby_eval_proc, (ClientData)tip, NULL);

    /* 9. Register callback for when Tcl deletes this interpreter */
    Tcl_CallWhenDeleted(tip->interp, interp_deleted_callback, (ClientData)tip);

    /* 10. Track this instance for multi-interp safety checks */
    rb_ary_push(live_instances, self);

    /* 11. Store the main thread ID for cross-thread event queuing */
    tip->main_thread_id = Tcl_GetCurrentThread();

    return self;
}

/* ---------------------------------------------------------
 * ruby_callback - Tcl command that invokes Ruby procs
 *
 * Called from Tcl as: ruby_callback <id> ?args...?
 * Looks up proc by ID and calls it with args.
 * --------------------------------------------------------- */

/* Helper struct for rb_protect call */
struct callback_args {
    VALUE proc;
    VALUE args;
};

static VALUE
callback_invoke(VALUE varg)
{
    struct callback_args *cargs = (struct callback_args *)varg;
    return rb_proc_call(cargs->proc, cargs->args);
}

static int
ruby_callback_proc(ClientData clientData, Tcl_Interp *interp,
                   int objc, Tcl_Obj *const objv[])
{
    struct tcltk_interp *tip = (struct tcltk_interp *)clientData;
    VALUE id_str, proc, args, result;
    struct callback_args cargs;
    int i, state;

    if (objc < 2) {
        Tcl_SetResult(interp, "wrong # args: should be \"ruby_callback id ?args?\"",
                      TCL_STATIC);
        return TCL_ERROR;
    }

    /* Look up proc by ID */
    id_str = rb_utf8_str_new_cstr(Tcl_GetString(objv[1]));
    proc = rb_hash_aref(tip->callbacks, id_str);

    if (NIL_P(proc)) {
        Tcl_SetObjResult(interp, Tcl_ObjPrintf("unknown callback id: %s",
                         Tcl_GetString(objv[1])));
        return TCL_ERROR;
    }

    /* Build args array */
    args = rb_ary_new2(objc - 2);
    for (i = 2; i < objc; i++) {
        Tcl_Size len;
        const char *str = Tcl_GetStringFromObj(objv[i], &len);
        rb_ary_push(args, rb_utf8_str_new(str, len));
    }

    /* Call the proc with exception protection */
    cargs.proc = proc;
    cargs.args = args;
    rbtk_callback_depth++;
    result = rb_protect(callback_invoke, (VALUE)&cargs, &state);
    rbtk_callback_depth--;

    if (state) {
        VALUE errinfo = rb_errinfo();
        rb_set_errinfo(Qnil);

        /* Let SystemExit and Interrupt propagate - don't swallow them */
        if (rb_obj_is_kind_of(errinfo, rb_eSystemExit) ||
            rb_obj_is_kind_of(errinfo, rb_eInterrupt)) {
            rb_exc_raise(errinfo);
        }

        /* Callback control flow - translate to Tcl return codes */
        if (rb_obj_is_kind_of(errinfo, eCallbackBreak)) {
            return TCL_BREAK;
        }
        if (rb_obj_is_kind_of(errinfo, eCallbackContinue)) {
            return TCL_CONTINUE;
        }
        if (rb_obj_is_kind_of(errinfo, eCallbackReturn)) {
            return TCL_RETURN;
        }

        /* Other exceptions: convert to Tcl error */
        VALUE msg = rb_funcall(errinfo, rb_intern("message"), 0);
        Tcl_SetResult(interp, StringValueCStr(msg), TCL_VOLATILE);
        return TCL_ERROR;
    }

    /* Return result to Tcl */
    if (!NIL_P(result)) {
        VALUE str = rb_String(result);
        Tcl_SetResult(interp, StringValueCStr(str), TCL_VOLATILE);
    }

    return TCL_OK;
}

/* ---------------------------------------------------------
 * ruby_eval_proc - Tcl command that evaluates Ruby code strings
 *
 * Called from Tcl as: ruby <ruby_code_string>
 * Used by tcltk.rb's callback mechanism.
 * --------------------------------------------------------- */

/* Helper for rb_protect */
static VALUE
eval_ruby_string(VALUE arg)
{
    return rb_eval_string(StringValueCStr(arg));
}

static int
ruby_eval_proc(ClientData clientData, Tcl_Interp *interp,
               int objc, Tcl_Obj *const objv[])
{
    VALUE code_str, result;
    int state;
    const char *code;

    if (objc != 2) {
        Tcl_SetResult(interp, (char *)"wrong # args: should be \"ruby code\"",
                      TCL_STATIC);
        return TCL_ERROR;
    }

    code = Tcl_GetString(objv[1]);
    code_str = rb_utf8_str_new_cstr(code);

    result = rb_protect(eval_ruby_string, code_str, &state);

    if (state) {
        VALUE errinfo = rb_errinfo();
        rb_set_errinfo(Qnil);

        /* Let SystemExit and Interrupt propagate */
        if (rb_obj_is_kind_of(errinfo, rb_eSystemExit) ||
            rb_obj_is_kind_of(errinfo, rb_eInterrupt)) {
            rb_exc_raise(errinfo);
        }

        VALUE msg = rb_funcall(errinfo, rb_intern("message"), 0);
        Tcl_SetResult(interp, StringValueCStr(msg), TCL_VOLATILE);
        return TCL_ERROR;
    }

    if (!NIL_P(result)) {
        VALUE str = rb_String(result);
        Tcl_SetResult(interp, StringValueCStr(str), TCL_VOLATILE);
    }

    return TCL_OK;
}

/* ---------------------------------------------------------
 * Interp#register_callback(proc) - Store proc, return ID
 * --------------------------------------------------------- */

static VALUE
interp_register_callback(VALUE self, VALUE proc)
{
    struct tcltk_interp *tip = get_interp(self);
    char id_buf[32];
    VALUE id_str;

    snprintf(id_buf, sizeof(id_buf), "cb%lu", tip->next_id++);
    id_str = rb_utf8_str_new_cstr(id_buf);

    rb_hash_aset(tip->callbacks, id_str, proc);
    return id_str;
}

/* ---------------------------------------------------------
 * Interp#unregister_callback(id) - Remove proc by ID
 * --------------------------------------------------------- */

static VALUE
interp_unregister_callback(VALUE self, VALUE id)
{
    struct tcltk_interp *tip = get_interp(self);
    rb_hash_delete(tip->callbacks, id);
    return Qnil;
}

/* ---------------------------------------------------------
 * Thread-safe event queue: run Ruby proc on main Tcl thread
 *
 * Background threads cannot safely call Tcl/Tk directly.
 * This mechanism queues a proc to execute on the main thread.
 * --------------------------------------------------------- */

/* Symbol IDs for queued command hash keys */
static ID sym_type, sym_proc, sym_script, sym_args, sym_queue;
static VALUE sym_eval, sym_invoke, sym_proc_val;

/* Execute a Tcl eval on behalf of a queued request */
static VALUE
execute_queued_eval(VALUE arg)
{
    VALUE *args = (VALUE *)arg;
    struct tcltk_interp *tip = (struct tcltk_interp *)args[0];
    VALUE script = args[1];
    const char *script_cstr = StringValueCStr(script);
    int result = Tcl_Eval(tip->interp, script_cstr);

    if (result != TCL_OK) {
        rb_raise(eTclError, "%s", Tcl_GetStringResult(tip->interp));
    }
    return rb_utf8_str_new_cstr(Tcl_GetStringResult(tip->interp));
}

/* Execute a Tcl invoke on behalf of a queued request */
static VALUE
execute_queued_invoke(VALUE arg)
{
    VALUE *args = (VALUE *)arg;
    struct tcltk_interp *tip = (struct tcltk_interp *)args[0];
    VALUE argv_ary = args[1];
    int argc = (int)RARRAY_LEN(argv_ary);
    Tcl_Obj **objv;
    int i, result;

    objv = ALLOCA_N(Tcl_Obj *, argc);
    for (i = 0; i < argc; i++) {
        VALUE arg = rb_ary_entry(argv_ary, i);
        const char *str;
        Tcl_Size len;

        if (NIL_P(arg)) {
            str = "";
            len = 0;
        } else {
            StringValue(arg);
            str = RSTRING_PTR(arg);
            len = RSTRING_LEN(arg);
        }
        objv[i] = Tcl_NewStringObj(str, len);
        Tcl_IncrRefCount(objv[i]);
    }

    result = Tcl_EvalObjv(tip->interp, argc, objv, 0);

    for (i = 0; i < argc; i++) {
        Tcl_DecrRefCount(objv[i]);
    }

    if (result != TCL_OK) {
        rb_raise(eTclError, "%s", Tcl_GetStringResult(tip->interp));
    }
    return rb_utf8_str_new_cstr(Tcl_GetStringResult(tip->interp));
}

/* Execute a Ruby proc */
static VALUE
execute_queued_proc(VALUE proc)
{
    return rb_proc_call(proc, rb_ary_new());
}

/* Tcl event callback - runs on main thread when event is processed */
static int
ruby_thread_event_handler(Tcl_Event *evPtr, int flags)
{
    struct ruby_thread_event *rte = (struct ruby_thread_event *)evPtr;
    VALUE cmd, type, queue, result, exception;
    int state;
    VALUE exec_args[2];

    /* Pop the command from the GC-protected queue */
    cmd = rb_ary_shift(rte->tip->thread_queue);
    if (NIL_P(cmd)) return 1;

    type = rb_hash_aref(cmd, ID2SYM(sym_type));
    queue = rb_hash_aref(cmd, ID2SYM(sym_queue));
    result = Qnil;
    exception = Qnil;

    exec_args[0] = (VALUE)rte->tip;

    if (type == sym_eval) {
        exec_args[1] = rb_hash_aref(cmd, ID2SYM(sym_script));
        result = rb_protect(execute_queued_eval, (VALUE)exec_args, &state);
    } else if (type == sym_invoke) {
        exec_args[1] = rb_hash_aref(cmd, ID2SYM(sym_args));
        result = rb_protect(execute_queued_invoke, (VALUE)exec_args, &state);
    } else if (type == sym_proc_val) {
        VALUE proc = rb_hash_aref(cmd, ID2SYM(sym_proc));
        result = rb_protect(execute_queued_proc, proc, &state);
    } else {
        state = 0;
    }

    if (state) {
        exception = rb_errinfo();
        rb_set_errinfo(Qnil);

        /* Let SystemExit and Interrupt propagate immediately */
        if (rb_obj_is_kind_of(exception, rb_eSystemExit) ||
            rb_obj_is_kind_of(exception, rb_eInterrupt)) {
            rb_exc_raise(exception);
        }
    }

    /* Send result back through the queue if one was provided */
    if (!NIL_P(queue)) {
        VALUE response = rb_ary_new3(2, result, exception);
        rb_funcall(queue, rb_intern("push"), 1, response);
    }

    return 1; /* Event handled, Tcl will free the event struct */
}

/* Internal: Queue a command and optionally wait for result */
static VALUE
queue_command_internal(struct tcltk_interp *tip, VALUE cmd_hash, int wait_for_result)
{
    struct ruby_thread_event *rte;
    Tcl_ThreadId current_thread;
    VALUE result_queue = Qnil;
    VALUE response, result, exception;

    if (wait_for_result) {
        /* Create a Queue for receiving the result */
        result_queue = rb_funcall(cQueue, rb_intern("new"), 0);
        rb_hash_aset(cmd_hash, ID2SYM(sym_queue), result_queue);
    }

    /* Store command in GC-protected queue */
    rb_ary_push(tip->thread_queue, cmd_hash);

    /* Allocate event - Tcl takes ownership and will free it */
    rte = (struct ruby_thread_event *)ckalloc(sizeof(struct ruby_thread_event));
    rte->event.proc = ruby_thread_event_handler;
    rte->tip = tip;

    /* Queue to main thread and wake it up */
    current_thread = Tcl_GetCurrentThread();
    Tcl_ThreadQueueEvent(tip->main_thread_id, (Tcl_Event *)rte, TCL_QUEUE_TAIL);

    if (current_thread != tip->main_thread_id) {
        Tcl_ThreadAlert(tip->main_thread_id);
    }

    if (!wait_for_result) {
        return Qnil;
    }

    /* Wait for result - this blocks until main thread processes the command */
    response = rb_funcall(result_queue, rb_intern("pop"), 0);
    result = rb_ary_entry(response, 0);
    exception = rb_ary_entry(response, 1);

    if (!NIL_P(exception)) {
        rb_exc_raise(exception);
    }

    return result;
}

/* Queue a proc to run on the main Tcl thread (fire-and-forget) */
static VALUE
interp_queue_for_main(VALUE self, VALUE proc)
{
    struct tcltk_interp *tip;
    VALUE cmd_hash;

    TypedData_Get_Struct(self, struct tcltk_interp, &interp_type, tip);

    if (tip->deleted || tip->interp == NULL) {
        rb_raise(eTclError, "interpreter has been deleted");
    }

    cmd_hash = rb_hash_new();
    rb_hash_aset(cmd_hash, ID2SYM(sym_type), sym_proc_val);
    rb_hash_aset(cmd_hash, ID2SYM(sym_proc), proc);

    return queue_command_internal(tip, cmd_hash, 0);
}

/* Check if current thread is the main Tcl thread */
static VALUE
interp_on_main_thread_p(VALUE self)
{
    struct tcltk_interp *tip = get_interp(self);
    Tcl_ThreadId current = Tcl_GetCurrentThread();
    return (current == tip->main_thread_id) ? Qtrue : Qfalse;
}

/* ---------------------------------------------------------
 * Interp#tcl_eval(script) - Evaluate Tcl script string
 *
 * Thread-safe: automatically routes through event queue if
 * called from a background thread.
 * --------------------------------------------------------- */

static VALUE
interp_tcl_eval(VALUE self, VALUE script)
{
    struct tcltk_interp *tip = get_interp(self);
    Tcl_ThreadId current = Tcl_GetCurrentThread();
    const char *script_cstr;
    int result;

    StringValue(script);

    /* If on background thread, queue to main thread and wait */
    if (current != tip->main_thread_id) {
        VALUE cmd_hash = rb_hash_new();
        rb_hash_aset(cmd_hash, ID2SYM(sym_type), sym_eval);
        rb_hash_aset(cmd_hash, ID2SYM(sym_script), script);
        return queue_command_internal(tip, cmd_hash, 1);
    }

    /* On main thread - execute directly */
    script_cstr = StringValueCStr(script);
    result = Tcl_Eval(tip->interp, script_cstr);

    if (result != TCL_OK) {
        rb_raise(eTclError, "%s", Tcl_GetStringResult(tip->interp));
    }

    return rb_utf8_str_new_cstr(Tcl_GetStringResult(tip->interp));
}

/* ---------------------------------------------------------
 * Interp#tcl_invoke(*args) - Invoke Tcl command with args
 *
 * This is the workhorse - creates widgets, configures them, etc.
 * Thread-safe: automatically routes through event queue if
 * called from a background thread.
 * --------------------------------------------------------- */

static VALUE
interp_tcl_invoke(int argc, VALUE *argv, VALUE self)
{
    struct tcltk_interp *tip = get_interp(self);
    Tcl_ThreadId current = Tcl_GetCurrentThread();
    Tcl_Obj **objv;
    int i, result;
    VALUE ret;

    if (argc == 0) {
        rb_raise(rb_eArgError, "wrong number of arguments (given 0, expected 1+)");
    }

    /* If on background thread, queue to main thread and wait */
    if (current != tip->main_thread_id) {
        VALUE cmd_hash = rb_hash_new();
        VALUE args_ary = rb_ary_new4(argc, argv);
        rb_hash_aset(cmd_hash, ID2SYM(sym_type), sym_invoke);
        rb_hash_aset(cmd_hash, ID2SYM(sym_args), args_ary);
        return queue_command_internal(tip, cmd_hash, 1);
    }

    /* On main thread - execute directly */
    objv = ALLOCA_N(Tcl_Obj *, argc);
    for (i = 0; i < argc; i++) {
        VALUE arg = argv[i];
        const char *str;
        Tcl_Size len;

        if (NIL_P(arg)) {
            str = "";
            len = 0;
        } else {
            StringValue(arg);
            str = RSTRING_PTR(arg);
            len = RSTRING_LEN(arg);
        }

        objv[i] = Tcl_NewStringObj(str, len);
        Tcl_IncrRefCount(objv[i]);
    }

    /* Invoke the command */
    result = Tcl_EvalObjv(tip->interp, argc, objv, 0);

    /* Clean up Tcl objects */
    for (i = 0; i < argc; i++) {
        Tcl_DecrRefCount(objv[i]);
    }

    if (result != TCL_OK) {
        rb_raise(eTclError, "%s", Tcl_GetStringResult(tip->interp));
    }

    ret = rb_utf8_str_new_cstr(Tcl_GetStringResult(tip->interp));
    return ret;
}

/* ---------------------------------------------------------
 * Interp#tcl_get_var(name) - Get Tcl variable value
 * --------------------------------------------------------- */

static VALUE
interp_tcl_get_var(VALUE self, VALUE name)
{
    struct tcltk_interp *tip = get_interp(self);
    const char *name_cstr;
    const char *value;

    StringValue(name);
    name_cstr = StringValueCStr(name);

    value = Tcl_GetVar(tip->interp, name_cstr, TCL_GLOBAL_ONLY);
    if (value == NULL) {
        return Qnil;
    }

    return rb_utf8_str_new_cstr(value);
}

/* ---------------------------------------------------------
 * Interp#tcl_set_var(name, value) - Set Tcl variable
 * --------------------------------------------------------- */

static VALUE
interp_tcl_set_var(VALUE self, VALUE name, VALUE value)
{
    struct tcltk_interp *tip = get_interp(self);
    const char *name_cstr;
    const char *value_cstr;
    const char *result;

    StringValue(name);
    name_cstr = StringValueCStr(name);

    if (NIL_P(value)) {
        value_cstr = "";
    } else {
        StringValue(value);
        value_cstr = StringValueCStr(value);
    }

    result = Tcl_SetVar(tip->interp, name_cstr, value_cstr, TCL_GLOBAL_ONLY);
    if (result == NULL) {
        rb_raise(eTclError, "failed to set variable '%s'", name_cstr);
    }

    return value;
}

/* ---------------------------------------------------------
 * Interp#do_one_event(flags = ALL_EVENTS) - Process single event
 *
 * Returns true if event was processed, false if nothing to do.
 * --------------------------------------------------------- */

static VALUE
interp_do_one_event(int argc, VALUE *argv, VALUE self)
{
    int flags = TCL_ALL_EVENTS;
    int result;

    /* Optional flags argument */
    if (argc > 0) {
        flags = NUM2INT(argv[0]);
    }

    result = Tcl_DoOneEvent(flags);

    return result ? Qtrue : Qfalse;
}

/* ---------------------------------------------------------
 * Interp#deleted? - Check if interpreter was deleted
 * --------------------------------------------------------- */

static VALUE
interp_deleted_p(VALUE self)
{
    struct tcltk_interp *tip;
    TypedData_Get_Struct(self, struct tcltk_interp, &interp_type, tip);
    return (tip->deleted || tip->interp == NULL) ? Qtrue : Qfalse;
}

/* ---------------------------------------------------------
 * Interp#safe? - Check if interpreter is running in safe mode
 *
 * Safe interpreters have restricted access to dangerous commands
 * like file I/O, exec, socket, etc. Created via create_slave(name, true).
 *
 * See: https://www.tcl-lang.org/man/tcl/TclCmd/interp.html#M30
 * --------------------------------------------------------- */

static VALUE
interp_safe_p(VALUE self)
{
    struct tcltk_interp *tip = get_interp(self);
    return Tcl_IsSafe(tip->interp) ? Qtrue : Qfalse;
}

/* ---------------------------------------------------------
 * Interp#delete - Explicitly delete interpreter
 * --------------------------------------------------------- */

static VALUE
interp_delete(VALUE self)
{
    struct tcltk_interp *tip;
    TypedData_Get_Struct(self, struct tcltk_interp, &interp_type, tip);

    if (tip->interp && !tip->deleted) {
        Tcl_DeleteInterp(tip->interp);
        tip->deleted = 1;
        /* Remove from live instances tracking */
        rb_ary_delete(live_instances, self);
    }

    return Qnil;
}

/* ---------------------------------------------------------
 * Interp#tcl_version / #tk_version - Get version strings
 * --------------------------------------------------------- */

static VALUE
interp_tcl_version(VALUE self)
{
    struct tcltk_interp *tip = get_interp(self);
    const char *version = Tcl_GetVar(tip->interp, "tcl_patchLevel", TCL_GLOBAL_ONLY);
    if (version == NULL) {
        return Qnil;
    }
    return rb_utf8_str_new_cstr(version);
}

static VALUE
interp_tk_version(VALUE self)
{
    struct tcltk_interp *tip = get_interp(self);
    const char *version = Tcl_GetVar(tip->interp, "tk_patchLevel", TCL_GLOBAL_ONLY);
    if (version == NULL) {
        return Qnil;
    }
    return rb_utf8_str_new_cstr(version);
}

/* ---------------------------------------------------------
 * Interp#mainloop - Run Tk event loop until no windows remain
 *
 * This is a thread-aware event loop that yields to other Ruby threads.
 * A recurring Tcl timer ensures DoOneEvent returns periodically.
 * The timer interval is controlled by the :thread_timer_ms option
 * passed to initialize (default: 5ms).
 * --------------------------------------------------------- */

/* Quick no-op function for GVL release/reacquire */
static void *
thread_yield_func(void *arg)
{
    return NULL;
}

/* Timer handler - re-registers itself to keep event loop responsive */
static void
keepalive_timer_proc(ClientData clientData)
{
    struct tcltk_interp *tip = (struct tcltk_interp *)clientData;
    if (tip && !tip->deleted && tip->timer_interval_ms > 0) {
        Tcl_CreateTimerHandler(tip->timer_interval_ms, keepalive_timer_proc, clientData);
    }
}

static VALUE
interp_mainloop(VALUE self)
{
    struct tcltk_interp *tip = get_interp(self);

    /* Start recurring timer if interval > 0 */
    if (tip->timer_interval_ms > 0) {
        Tcl_CreateTimerHandler(tip->timer_interval_ms, keepalive_timer_proc, (ClientData)tip);
    }

    while (Tk_GetNumMainWindows() > 0) {
        /* Process one event (timer ensures this returns periodically) */
        Tcl_DoOneEvent(TCL_ALL_EVENTS);

        /* Yield to other Ruby threads by releasing and reacquiring GVL */
        if (tip->timer_interval_ms > 0) {
            rb_thread_call_without_gvl(thread_yield_func, NULL, RUBY_UBF_IO, NULL);
        }

        /* Check for Ruby interrupts (Ctrl-C, etc) */
        rb_thread_check_ints();
    }

    return Qnil;
}

/* ---------------------------------------------------------
 * TclTkLib.mainloop - Global event loop (no interpreter required)
 *
 * Runs the Tk event loop until all windows are closed.
 * Uses the global g_thread_timer_ms setting for thread yielding.
 *
 * IMPORTANT: GVL is released during Tcl_DoOneEvent so background
 * Ruby threads can run while waiting for Tk events. Without this,
 * background threads would be starved (only running during brief
 * yields between events).
 * --------------------------------------------------------- */

/* Global timer handler - re-registers itself using global interval */
static void
global_keepalive_timer_proc(ClientData clientData)
{
    if (g_thread_timer_ms > 0) {
        Tcl_CreateTimerHandler(g_thread_timer_ms, global_keepalive_timer_proc, NULL);
    }
}

static VALUE
lib_mainloop(int argc, VALUE *argv, VALUE self)
{
    int check_root = 1;  /* default: exit when no windows remain */
    int event_flags = TCL_ALL_EVENTS;

    /* Optional check_root argument:
     *   true (default): exit when Tk_GetNumMainWindows() == 0
     *   false: keep running even with no windows (for timers, traces, etc.)
     */
    if (argc > 0 && argv[0] != Qnil) {
        check_root = RTEST(argv[0]);
    }

    for (;;) {
        /* Exit if check_root enabled and no windows remain */
        if (check_root && Tk_GetNumMainWindows() <= 0) {
            break;
        }

        if (rb_thread_alone()) {
            /* No other threads - simple blocking wait */
            Tcl_DoOneEvent(event_flags);
        } else {
            /* Other threads exist - use polling with brief sleep.
             *
             * We tried rb_thread_call_without_gvl() with Tcl_ThreadAlert to
             * efficiently release GVL during blocking waits, but it proved
             * unstable - crashes in Digest and other C extensions, UI freezes,
             * and unreliable notifier wakeup across platforms.
             *
             * This polling approach is simple and stable:
             * - Process any pending events without blocking
             * - If no events, brief sleep to avoid spinning (uses ~1-3% CPU idle)
             * - rb_thread_schedule() lets background threads run during sleep
             */
            int had_event = Tcl_DoOneEvent(event_flags | TCL_DONT_WAIT);
            if (!had_event) {
                rb_thread_schedule();
#ifdef _WIN32
                Sleep(5);  /* 5ms */
#else
                struct timespec ts = {0, 5000000};  /* 5ms */
                nanosleep(&ts, NULL);
#endif
            }
        }

        /* Check for Ruby interrupts (Ctrl-C, etc) */
        rb_thread_check_ints();
    }

    return Qnil;
}

static VALUE
lib_get_thread_timer_ms(VALUE self)
{
    return INT2NUM(g_thread_timer_ms);
}

static VALUE
lib_set_thread_timer_ms(VALUE self, VALUE val)
{
    int ms = NUM2INT(val);
    if (ms < 0) {
        rb_raise(rb_eArgError, "thread_timer_ms must be >= 0 (got %d)", ms);
    }
    g_thread_timer_ms = ms;
    return val;
}

/* ---------------------------------------------------------
 * TclTkLib.do_one_event(flags = ALL_EVENTS) - Process single event
 *
 * Global function - Tcl_DoOneEvent doesn't require an interpreter.
 * Returns true if event was processed, false if nothing to do.
 * --------------------------------------------------------- */

static VALUE
lib_do_one_event(int argc, VALUE *argv, VALUE self)
{
    int flags = TCL_ALL_EVENTS;
    int result;

    if (argc > 0) {
        flags = NUM2INT(argv[0]);
    }

    result = Tcl_DoOneEvent(flags);

    return result ? Qtrue : Qfalse;
}

/* ---------------------------------------------------------
 * Interp#thread_timer_ms / #thread_timer_ms= - Get/set timer interval
 * --------------------------------------------------------- */

static VALUE
interp_get_thread_timer_ms(VALUE self)
{
    struct tcltk_interp *tip = get_interp(self);
    return INT2NUM(tip->timer_interval_ms);
}

static VALUE
interp_set_thread_timer_ms(VALUE self, VALUE val)
{
    struct tcltk_interp *tip = get_interp(self);
    int ms = NUM2INT(val);
    if (ms < 0) {
        rb_raise(rb_eArgError, "thread_timer_ms must be >= 0 (got %d)", ms);
    }
    tip->timer_interval_ms = ms;
    return val;
}

/* ---------------------------------------------------------
 * TclTkLib._merge_tklist(*args) - Merge strings into Tcl list
 *
 * Uses Tcl's quoting rules for proper escaping.
 * Module function (no interpreter needed).
 * --------------------------------------------------------- */

static VALUE
lib_merge_tklist(int argc, VALUE *argv, VALUE self)
{
    Tcl_Obj *listobj;
    Tcl_Size len;
    const char *result;
    VALUE str;
    int i;

    if (argc == 0) return rb_utf8_str_new_cstr("");

    listobj = Tcl_NewListObj(0, NULL);
    Tcl_IncrRefCount(listobj);

    for (i = 0; i < argc; i++) {
        VALUE s = StringValue(argv[i]);
        Tcl_Obj *elem = Tcl_NewStringObj(RSTRING_PTR(s), RSTRING_LEN(s));
        Tcl_ListObjAppendElement(NULL, listobj, elem);
    }

    result = Tcl_GetStringFromObj(listobj, &len);
    str = rb_utf8_str_new(result, len);

    Tcl_DecrRefCount(listobj);
    return str;
}

/* ---------------------------------------------------------
 * Interp#create_slave(name, safe=false) - Create child interpreter
 *
 * Creates a Tcl slave interpreter with the given name.
 * If safe is true, the slave runs in safe mode (restricted commands).
 * --------------------------------------------------------- */

static VALUE
interp_create_slave(int argc, VALUE *argv, VALUE self)
{
    struct tcltk_interp *master = get_interp(self);
    struct tcltk_interp *slave;
    VALUE name, safemode, new_ip;
    int safe;
    Tcl_Interp *slave_interp;

    rb_scan_args(argc, argv, "11", &name, &safemode);
    StringValue(name);
    safe = RTEST(safemode) ? 1 : 0;

    /* Create the slave interpreter */
    slave_interp = Tcl_CreateSlave(master->interp, StringValueCStr(name), safe);
    if (slave_interp == NULL) {
        rb_raise(eTclError, "failed to create slave interpreter");
    }

    /* Wrap in a new TclTkIp Ruby object */
    new_ip = TypedData_Make_Struct(cInterp, struct tcltk_interp,
                                   &interp_type, slave);
    slave->interp = slave_interp;
    slave->deleted = 0;
    slave->callbacks = rb_hash_new();
    slave->thread_queue = rb_ary_new();
    slave->next_id = 1;
    slave->timer_interval_ms = DEFAULT_TIMER_INTERVAL_MS;
    slave->main_thread_id = Tcl_GetCurrentThread();

    /* Register Ruby integration commands in the slave */
    Tcl_CreateObjCommand(slave->interp, "ruby_callback",
                         ruby_callback_proc, (ClientData)slave, NULL);
    Tcl_CreateObjCommand(slave->interp, "ruby",
                         ruby_eval_proc, (ClientData)slave, NULL);
    Tcl_CreateObjCommand(slave->interp, "ruby_eval",
                         ruby_eval_proc, (ClientData)slave, NULL);

    /* Register callback for when Tcl deletes this interpreter */
    Tcl_CallWhenDeleted(slave->interp, interp_deleted_callback, (ClientData)slave);

    /* Track this instance */
    rb_ary_push(live_instances, new_ip);

    return new_ip;
}

/* ---------------------------------------------------------
 * TclTkIp.instance_count - Number of live interpreter instances
 * --------------------------------------------------------- */

static VALUE
tcltkip_instance_count(VALUE klass)
{
    return LONG2NUM(RARRAY_LEN(live_instances));
}

/* ---------------------------------------------------------
 * TclTkIp.instances - Array of live interpreter instances
 * --------------------------------------------------------- */

static VALUE
tcltkip_instances(VALUE klass)
{
    return rb_ary_dup(live_instances);
}

/* ---------------------------------------------------------
 * TclTkLib.in_callback? - Check if currently inside a Tk callback
 *
 * Used to detect unsafe operations (exit/destroy from callback).
 * --------------------------------------------------------- */

static VALUE
lib_in_callback_p(VALUE self)
{
    return rbtk_callback_depth > 0 ? Qtrue : Qfalse;
}

/* ---------------------------------------------------------
 * TclTkLib.get_version - Get Tcl version as [major, minor, type, patchlevel]
 *
 * WHY COMPILE-TIME MACROS INSTEAD OF Tcl_GetVersion()?
 *
 * With stubs enabled (-DUSE_TCL_STUBS), Tcl_GetVersion() becomes a macro
 * that dereferences tclStubsPtr->tcl_GetVersion. But tclStubsPtr is NULL
 * until Tcl_InitStubs() is called - which requires an interpreter.
 *
 * So the "proper" API to get the version needs an interpreter to exist
 * first. That's backwards - callers often want version info before
 * deciding whether to create an interpreter.
 *
 * The workaround: use the compile-time macros from tcl.h directly.
 * These are just #defines, no stubs table needed. The version reported
 * is what we compiled against, which must match the runtime major version
 * (stubs enforce this). Minor/patch may differ at runtime - use
 * TclTkIp#tcl_version for the exact runtime patchlevel.
 * --------------------------------------------------------- */

static VALUE
lib_get_version(VALUE self)
{
    return rb_ary_new3(4,
        INT2NUM(TCL_MAJOR_VERSION),
        INT2NUM(TCL_MINOR_VERSION),
        INT2NUM(TCL_RELEASE_LEVEL),
        INT2NUM(TCL_RELEASE_SERIAL));
}

/* Photo image functions moved to tkphoto.c */

/* ---------------------------------------------------------
 * Interp#create_console - Create Tk console window
 *
 * Creates a console window for platforms without a real terminal.
 * See: https://www.tcl-lang.org/man/tcl8.6/TkLib/CrtConsoleChan.htm
 * --------------------------------------------------------- */

static VALUE
interp_create_console(VALUE self)
{
    struct tcltk_interp *tip = get_interp(self);

    /*
     * tcl_interactive is normally set by tclsh/wish at startup.
     * When embedding Tcl in Ruby, we must set it ourselves.
     * console.tcl checks this to decide whether to show the console window:
     * if 0, the window starts hidden (wm withdraw); if 1, it's shown.
     * See: https://github.com/tcltk/tk/blob/main/library/console.tcl#L144
     */
    if (Tcl_GetVar(tip->interp, "tcl_interactive", TCL_GLOBAL_ONLY) == NULL) {
        Tcl_SetVar(tip->interp, "tcl_interactive", "0", TCL_GLOBAL_ONLY);
    }

    Tk_InitConsoleChannels(tip->interp);

    if (Tk_CreateConsoleWindow(tip->interp) != TCL_OK) {
        rb_raise(eTclError, "failed to create console window: %s",
                 Tcl_GetStringResult(tip->interp));
    }

    return Qtrue;
}

/* ---------------------------------------------------------
 * Module initialization
 * --------------------------------------------------------- */

void
Init_tcltklib(void)
{
    /* Initialize live instances tracking array (must be before any interp creation) */
    live_instances = rb_ary_new();
    rb_gc_register_address(&live_instances);

    /* Initialize symbols for thread queue command hashes */
    sym_type = rb_intern("type");
    sym_proc = rb_intern("proc");
    sym_script = rb_intern("script");
    sym_args = rb_intern("args");
    sym_queue = rb_intern("queue");
    sym_eval = ID2SYM(rb_intern("eval"));
    sym_invoke = ID2SYM(rb_intern("invoke"));
    sym_proc_val = ID2SYM(rb_intern("proc"));

    /* Get Thread::Queue for cross-thread synchronization */
    cQueue = rb_path2class("Thread::Queue");
    rb_gc_register_address(&cQueue);

    /* Teek module (may already exist from Ruby side) */
    mTeek = rb_define_module("Teek");

    /* Event flags as constants */
    rb_define_const(mTeek, "WINDOW_EVENTS", INT2NUM(TCL_WINDOW_EVENTS));
    rb_define_const(mTeek, "FILE_EVENTS", INT2NUM(TCL_FILE_EVENTS));
    rb_define_const(mTeek, "TIMER_EVENTS", INT2NUM(TCL_TIMER_EVENTS));
    rb_define_const(mTeek, "IDLE_EVENTS", INT2NUM(TCL_IDLE_EVENTS));
    rb_define_const(mTeek, "ALL_EVENTS", INT2NUM(TCL_ALL_EVENTS));
    rb_define_const(mTeek, "DONT_WAIT", INT2NUM(TCL_DONT_WAIT));

    /* Teek::TclError exception */
    eTclError = rb_define_class_under(mTeek, "TclError", rb_eRuntimeError);

    /* Callback control flow exceptions */
    eCallbackBreak = rb_define_class_under(mTeek, "CallbackBreak", rb_eStandardError);
    eCallbackContinue = rb_define_class_under(mTeek, "CallbackContinue", rb_eStandardError);
    eCallbackReturn = rb_define_class_under(mTeek, "CallbackReturn", rb_eStandardError);

    /* Module function for list operations */
    rb_define_module_function(mTeek, "merge_tklist", lib_merge_tklist, -1);

    /* Global event loop functions - don't require an interpreter */
    rb_define_module_function(mTeek, "mainloop", lib_mainloop, -1);
    rb_define_module_function(mTeek, "do_one_event", lib_do_one_event, -1);
    rb_define_module_function(mTeek, "thread_timer_ms", lib_get_thread_timer_ms, 0);
    rb_define_module_function(mTeek, "thread_timer_ms=", lib_set_thread_timer_ms, 1);

    /* Callback depth detection for unsafe operation warnings */
    rb_define_module_function(mTeek, "in_callback?", lib_in_callback_p, 0);

    /* Version info - uses compile-time macros, no stubs needed */
    rb_define_module_function(mTeek, "get_version", lib_get_version, 0);

    /* Teek::RELEASE_TYPE module with constants */
    {
        VALUE mReleaseType = rb_define_module_under(mTeek, "RELEASE_TYPE");
        rb_define_const(mReleaseType, "ALPHA", INT2NUM(TCL_ALPHA_RELEASE));
        rb_define_const(mReleaseType, "BETA", INT2NUM(TCL_BETA_RELEASE));
        rb_define_const(mReleaseType, "FINAL", INT2NUM(TCL_FINAL_RELEASE));
    }

    /* Teek::Interp class */
    cInterp = rb_define_class_under(mTeek, "Interp", rb_cObject);
    rb_define_alloc_func(cInterp, interp_alloc);

    rb_define_method(cInterp, "initialize", interp_initialize, -1);
    rb_define_method(cInterp, "tcl_eval", interp_tcl_eval, 1);
    rb_define_method(cInterp, "tcl_invoke", interp_tcl_invoke, -1);
    rb_define_method(cInterp, "tcl_get_var", interp_tcl_get_var, 1);
    rb_define_method(cInterp, "tcl_set_var", interp_tcl_set_var, 2);
    rb_define_method(cInterp, "do_one_event", interp_do_one_event, -1);
    rb_define_method(cInterp, "deleted?", interp_deleted_p, 0);
    rb_define_method(cInterp, "safe?", interp_safe_p, 0);
    rb_define_method(cInterp, "delete", interp_delete, 0);
    rb_define_method(cInterp, "tcl_version", interp_tcl_version, 0);
    rb_define_method(cInterp, "tk_version", interp_tk_version, 0);
    rb_define_method(cInterp, "mainloop", interp_mainloop, 0);
    rb_define_method(cInterp, "register_callback", interp_register_callback, 1);
    rb_define_method(cInterp, "unregister_callback", interp_unregister_callback, 1);
    rb_define_method(cInterp, "create_slave", interp_create_slave, -1);
    rb_define_method(cInterp, "thread_timer_ms", interp_get_thread_timer_ms, 0);
    rb_define_method(cInterp, "thread_timer_ms=", interp_set_thread_timer_ms, 1);
    rb_define_method(cInterp, "queue_for_main", interp_queue_for_main, 1);
    rb_define_method(cInterp, "on_main_thread?", interp_on_main_thread_p, 0);
    rb_define_method(cInterp, "create_console", interp_create_console, 0);

    /* Photo image functions (tkphoto.c) */
    Init_tkphoto(cInterp);

    /* Font functions (tkfont.c) */
    Init_tkfont(cInterp);

    /* Utility functions (tkutil.c) */
    Init_tkutil(cInterp);

    /* Aliases for legacy API compatibility */
    rb_define_alias(cInterp, "_eval", "tcl_eval");
    rb_define_alias(cInterp, "_invoke", "tcl_invoke");

    /* Class methods for instance tracking */
    rb_define_singleton_method(cInterp, "instance_count", tcltkip_instance_count, 0);
    rb_define_singleton_method(cInterp, "instances", tcltkip_instances, 0);
}
