/* tcltkbridge.h - Shared definitions for tk-ng C extension
 *
 * This header provides shared types and functions for the tcltklib extension,
 * allowing code to be split across multiple .c files.
 */

#ifndef TCLTKBRIDGE_H
#define TCLTKBRIDGE_H

#include <ruby.h>
#include <tcl.h>
#include <tk.h>
#include "tcl9compat.h"

/* Interp struct stored in Ruby object */
struct tcltk_interp {
    Tcl_Interp *interp;
    int deleted;
    VALUE callbacks;      /* Hash: id_string => proc (GC-marked) */
    VALUE thread_queue;   /* Array: pending procs from other threads (GC-marked) */
    unsigned long next_id; /* Next callback ID */
    int timer_interval_ms; /* Mainloop timer interval for thread yielding */
    Tcl_ThreadId main_thread_id; /* Thread that created the interp */
};

/* Shared globals - defined in tcltkbridge.c */
extern VALUE eTclError;
extern const rb_data_type_t interp_type;

/* Get interpreter from Ruby object, raising if deleted */
struct tcltk_interp *get_interp(VALUE self);

/* Photo image functions - defined in tkphoto.c */
void Init_tkphoto(VALUE cTclTkIp);

/* Font functions - defined in tkfont.c */
void Init_tkfont(VALUE cTclTkIp);

/* Utility functions - defined in tkutil.c */
void Init_tkutil(VALUE cTclTkIp);

#endif /* TCLTKBRIDGE_H */
