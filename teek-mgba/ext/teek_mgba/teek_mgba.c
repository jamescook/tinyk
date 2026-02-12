#include "teek_mgba.h"
#include <ruby/thread.h>
#include <string.h>
#include <stdlib.h>

/*
 * Forward declarations for blip_buf (audio buffer API).
 * These functions are part of libmgba but the header may
 * not be in the installed include path.
 */
struct blip_t;
int blip_samples_avail(const struct blip_t *);
int blip_read_samples(struct blip_t *, short out[], int count, int stereo);

VALUE mTeek;
VALUE mTeekMGBA;
static VALUE cCore;

/* No-op logger — prevents segfault when mGBA tries to log
 * without a logger configured (the default is NULL). */
static void
null_log(struct mLogger *logger, int category, enum mLogLevel level,
         const char *format, va_list args)
{
    (void)logger; (void)category; (void)level;
    (void)format; (void)args;
}

static struct mLogger s_null_logger = {
    .log = null_log,
    .filter = NULL,
};

/* GBA key indices (bit positions for set_keys bitmask).
 * Matches mGBA's GBA_KEY_* enum. */
#define TEEK_GBA_KEY_A      0
#define TEEK_GBA_KEY_B      1
#define TEEK_GBA_KEY_SELECT 2
#define TEEK_GBA_KEY_START  3
#define TEEK_GBA_KEY_RIGHT  4
#define TEEK_GBA_KEY_LEFT   5
#define TEEK_GBA_KEY_UP     6
#define TEEK_GBA_KEY_DOWN   7
#define TEEK_GBA_KEY_R      8
#define TEEK_GBA_KEY_L      9

/* --------------------------------------------------------- */
/* Core wrapper struct                                       */
/* --------------------------------------------------------- */

struct mgba_core {
    struct mCore *core;
    color_t *video_buffer;
    int width;
    int height;
    int destroyed;
};

static void
mgba_core_dfree(void *ptr)
{
    struct mgba_core *mc = ptr;
    if (!mc->destroyed && mc->core) {
        mc->core->deinit(mc->core);
        mc->core = NULL;
    }
    if (mc->video_buffer) {
        free(mc->video_buffer);
        mc->video_buffer = NULL;
    }
    mc->destroyed = 1;
    xfree(mc);
}

static size_t
mgba_core_memsize(const void *ptr)
{
    const struct mgba_core *mc = ptr;
    size_t size = sizeof(struct mgba_core);
    if (mc->video_buffer) {
        size += (size_t)mc->width * mc->height * sizeof(color_t);
    }
    return size;
}

static const rb_data_type_t mgba_core_type = {
    .wrap_struct_name = "TeekMGBA::Core",
    .function = {
        .dmark = NULL,
        .dfree = mgba_core_dfree,
        .dsize = mgba_core_memsize,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE
mgba_core_alloc(VALUE klass)
{
    struct mgba_core *mc;
    VALUE obj = TypedData_Make_Struct(klass, struct mgba_core,
                                     &mgba_core_type, mc);
    mc->core = NULL;
    mc->video_buffer = NULL;
    mc->width = 0;
    mc->height = 0;
    mc->destroyed = 0;
    return obj;
}

static struct mgba_core *
get_mgba_core(VALUE self)
{
    struct mgba_core *mc;
    TypedData_Get_Struct(self, struct mgba_core, &mgba_core_type, mc);
    if (mc->destroyed || !mc->core) {
        rb_raise(rb_eRuntimeError, "mGBA core has been destroyed");
    }
    return mc;
}

/* --------------------------------------------------------- */
/* Core#initialize(rom_path)                                 */
/* --------------------------------------------------------- */

static VALUE
mgba_core_initialize(VALUE self, VALUE rom_path)
{
    struct mgba_core *mc;
    TypedData_Get_Struct(self, struct mgba_core, &mgba_core_type, mc);

    const char *path = StringValueCStr(rom_path);

    /* 1. Detect platform from ROM */
    struct mCore *core = mCoreFind(path);
    if (!core) {
        rb_raise(rb_eArgError, "mCoreFind failed — unsupported ROM: %s", path);
    }

    /* 2. Initialize core + config (required per mGBA Python bindings) */
    if (!core->init(core)) {
        rb_raise(rb_eRuntimeError, "mCore init failed");
    }
    mCoreInitConfig(core, NULL);

    /* 3. Get desired video dimensions */
    unsigned w, h;
    core->desiredVideoDimensions(core, &w, &h);
    mc->width = (int)w;
    mc->height = (int)h;

    /* 4. Allocate and set video buffer */
    mc->video_buffer = calloc((size_t)w * h, sizeof(color_t));
    if (!mc->video_buffer) {
        core->deinit(core);
        rb_raise(rb_eNoMemError, "failed to allocate video buffer");
    }
    core->setVideoBuffer(core, mc->video_buffer, w);

    /* 5. Set audio buffer size */
    core->setAudioBufferSize(core, 2048);

    /* 6. Load ROM (convenience function handles VFile internally) */
    if (!mCoreLoadFile(core, path)) {
        free(mc->video_buffer);
        mc->video_buffer = NULL;
        core->deinit(core);
        rb_raise(rb_eArgError, "failed to load ROM: %s", path);
    }

    /* 8. Reset */
    core->reset(core);

    mc->core = core;
    return self;
}

/* --------------------------------------------------------- */
/* Core#run_frame — releases GVL for ~16ms of CPU work       */
/* --------------------------------------------------------- */

struct run_frame_args {
    struct mCore *core;
};

static void *
run_frame_nogvl(void *arg)
{
    struct run_frame_args *a = arg;
    a->core->runFrame(a->core);
    return NULL;
}

static VALUE
mgba_core_run_frame(VALUE self)
{
    struct mgba_core *mc = get_mgba_core(self);
    struct run_frame_args args = { .core = mc->core };
    rb_thread_call_without_gvl(run_frame_nogvl, &args, RUBY_UBF_IO, NULL);
    return Qnil;
}

/* --------------------------------------------------------- */
/* Core#video_buffer                                         */
/* --------------------------------------------------------- */

static VALUE
mgba_core_video_buffer(VALUE self)
{
    struct mgba_core *mc = get_mgba_core(self);
    long size = (long)mc->width * mc->height * (long)sizeof(color_t);
    return rb_str_new((const char *)mc->video_buffer, size);
}

/* --------------------------------------------------------- */
/* Core#video_buffer_argb                                    */
/* Returns pixel data with R↔B swapped for SDL ARGB8888.     */
/* mGBA color_t is 0xAABBGGRR; SDL wants 0xAARRGGBB.        */
/* --------------------------------------------------------- */

static VALUE
mgba_core_video_buffer_argb(VALUE self)
{
    struct mgba_core *mc = get_mgba_core(self);
    long npixels = (long)mc->width * mc->height;
    long size = npixels * (long)sizeof(uint32_t);
    VALUE str = rb_str_new(NULL, size);
    uint32_t *dst = (uint32_t *)RSTRING_PTR(str);
    const uint32_t *src = (const uint32_t *)mc->video_buffer;

    for (long i = 0; i < npixels; i++) {
        uint32_t px = src[i];
        /* Swap R (bits 0-7) and B (bits 16-23), keep A and G */
        dst[i] = (px & 0xFF00FF00)
               | ((px & 0x000000FF) << 16)
               | ((px & 0x00FF0000) >> 16);
    }
    return str;
}

/* --------------------------------------------------------- */
/* Core#audio_buffer                                         */
/* --------------------------------------------------------- */

static VALUE
mgba_core_audio_buffer(VALUE self)
{
    struct mgba_core *mc = get_mgba_core(self);

    struct blip_t *left  = mc->core->getAudioChannel(mc->core, 0);
    struct blip_t *right = mc->core->getAudioChannel(mc->core, 1);

    int avail = blip_samples_avail(left);
    if (avail <= 0) {
        return rb_str_new(NULL, 0);
    }

    /* Interleaved stereo int16: L R L R ... */
    long byte_size = (long)avail * 2 * (long)sizeof(int16_t);
    VALUE str = rb_str_new(NULL, byte_size);
    int16_t *buf = (int16_t *)RSTRING_PTR(str);

    /* stereo=1: write every other sample for interleaving */
    blip_read_samples(left,  buf,     avail, 1);
    blip_read_samples(right, buf + 1, avail, 1);

    return str;
}

/* --------------------------------------------------------- */
/* Core#set_keys(bitmask)                                    */
/* --------------------------------------------------------- */

static VALUE
mgba_core_set_keys(VALUE self, VALUE keys)
{
    struct mgba_core *mc = get_mgba_core(self);
    uint32_t bitmask = NUM2UINT(keys);
    mc->core->setKeys(mc->core, bitmask);
    return Qnil;
}

/* --------------------------------------------------------- */
/* Core#width, Core#height                                   */
/* --------------------------------------------------------- */

static VALUE
mgba_core_width(VALUE self)
{
    struct mgba_core *mc = get_mgba_core(self);
    return INT2NUM(mc->width);
}

static VALUE
mgba_core_height(VALUE self)
{
    struct mgba_core *mc = get_mgba_core(self);
    return INT2NUM(mc->height);
}

/* --------------------------------------------------------- */
/* Core#title                                                */
/* --------------------------------------------------------- */

static VALUE
mgba_core_title(VALUE self)
{
    struct mgba_core *mc = get_mgba_core(self);
    char title[16];
    memset(title, 0, sizeof(title));
    mc->core->getGameTitle(mc->core, title);

    /* Trim trailing spaces and nulls */
    int len = 15;
    while (len >= 0 && (title[len] == '\0' || title[len] == ' ')) {
        len--;
    }
    return rb_str_new(title, len + 1);
}

/* --------------------------------------------------------- */
/* Core#destroy, Core#destroyed?                             */
/* --------------------------------------------------------- */

static VALUE
mgba_core_destroy(VALUE self)
{
    struct mgba_core *mc;
    TypedData_Get_Struct(self, struct mgba_core, &mgba_core_type, mc);
    if (!mc->destroyed && mc->core) {
        mc->core->deinit(mc->core);
        mc->core = NULL;
    }
    if (mc->video_buffer) {
        free(mc->video_buffer);
        mc->video_buffer = NULL;
    }
    mc->destroyed = 1;
    return Qnil;
}

static VALUE
mgba_core_destroyed_p(VALUE self)
{
    struct mgba_core *mc;
    TypedData_Get_Struct(self, struct mgba_core, &mgba_core_type, mc);
    return mc->destroyed ? Qtrue : Qfalse;
}

/* --------------------------------------------------------- */
/* Init                                                      */
/* --------------------------------------------------------- */

void
Init_teek_mgba(void)
{
    /* Install no-op logger before any mGBA calls */
    mLogSetDefaultLogger(&s_null_logger);

    /* Teek module (may already exist from teek gem) */
    mTeek = rb_define_module("Teek");

    /* Teek::MGBA module */
    mTeekMGBA = rb_define_module_under(mTeek, "MGBA");

    /* Teek::MGBA::Core class */
    cCore = rb_define_class_under(mTeekMGBA, "Core", rb_cObject);
    rb_define_alloc_func(cCore, mgba_core_alloc);

    rb_define_method(cCore, "initialize",  mgba_core_initialize, 1);
    rb_define_method(cCore, "run_frame",   mgba_core_run_frame, 0);
    rb_define_method(cCore, "video_buffer", mgba_core_video_buffer, 0);
    rb_define_method(cCore, "video_buffer_argb", mgba_core_video_buffer_argb, 0);
    rb_define_method(cCore, "audio_buffer", mgba_core_audio_buffer, 0);
    rb_define_method(cCore, "set_keys",    mgba_core_set_keys, 1);
    rb_define_method(cCore, "width",       mgba_core_width, 0);
    rb_define_method(cCore, "height",      mgba_core_height, 0);
    rb_define_method(cCore, "title",       mgba_core_title, 0);
    rb_define_method(cCore, "destroy",     mgba_core_destroy, 0);
    rb_define_method(cCore, "destroyed?",  mgba_core_destroyed_p, 0);

    /* GBA key constants (bitmask values for set_keys) */
    rb_define_const(mTeekMGBA, "KEY_A",      INT2NUM(1 << TEEK_GBA_KEY_A));
    rb_define_const(mTeekMGBA, "KEY_B",      INT2NUM(1 << TEEK_GBA_KEY_B));
    rb_define_const(mTeekMGBA, "KEY_SELECT", INT2NUM(1 << TEEK_GBA_KEY_SELECT));
    rb_define_const(mTeekMGBA, "KEY_START",  INT2NUM(1 << TEEK_GBA_KEY_START));
    rb_define_const(mTeekMGBA, "KEY_RIGHT",  INT2NUM(1 << TEEK_GBA_KEY_RIGHT));
    rb_define_const(mTeekMGBA, "KEY_LEFT",   INT2NUM(1 << TEEK_GBA_KEY_LEFT));
    rb_define_const(mTeekMGBA, "KEY_UP",     INT2NUM(1 << TEEK_GBA_KEY_UP));
    rb_define_const(mTeekMGBA, "KEY_DOWN",   INT2NUM(1 << TEEK_GBA_KEY_DOWN));
    rb_define_const(mTeekMGBA, "KEY_R",      INT2NUM(1 << TEEK_GBA_KEY_R));
    rb_define_const(mTeekMGBA, "KEY_L",      INT2NUM(1 << TEEK_GBA_KEY_L));
}
