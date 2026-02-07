/* tkutil.c - General Tcl/Tk utility C functions for tk-ng
 *
 * Miscellaneous utility functions: list parsing, idle detection, etc.
 */

#include "tcltkbridge.h"

/* ---------------------------------------------------------
 * Interp#tcl_split_list(str) - Parse Tcl list into Ruby array
 *
 * Single C call instead of N+1 eval round-trips.
 * Returns array of strings (does not recursively parse nested lists).
 * --------------------------------------------------------- */

static VALUE
interp_tcl_split_list(VALUE self, VALUE list_str)
{
    struct tcltk_interp *tip = get_interp(self);
    Tcl_Obj *listobj;
    Tcl_Size objc;
    Tcl_Obj **objv;
    VALUE ary;
    Tcl_Size i;
    int result;

    if (NIL_P(list_str)) {
        return rb_ary_new();
    }

    StringValue(list_str);
    if (RSTRING_LEN(list_str) == 0) {
        return rb_ary_new();
    }

    /* Create Tcl object from Ruby string */
    listobj = Tcl_NewStringObj(RSTRING_PTR(list_str), RSTRING_LEN(list_str));
    Tcl_IncrRefCount(listobj);

    /* Split into array of Tcl objects */
    result = Tcl_ListObjGetElements(tip->interp, listobj, &objc, &objv);
    if (result != TCL_OK) {
        Tcl_DecrRefCount(listobj);
        rb_raise(eTclError, "invalid Tcl list: %s", Tcl_GetStringResult(tip->interp));
    }

    /* Convert to Ruby array of strings */
    ary = rb_ary_new2(objc);
    for (i = 0; i < objc; i++) {
        Tcl_Size len;
        const char *str = Tcl_GetStringFromObj(objv[i], &len);
        rb_ary_push(ary, rb_utf8_str_new(str, len));
    }

    Tcl_DecrRefCount(listobj);
    return ary;
}

/* ---------------------------------------------------------
 * Interp#user_inactive_time
 *
 * Get milliseconds since last user activity using Tk_GetUserInactiveTime.
 * Useful for implementing screensavers, idle timeouts, etc.
 *
 * Returns:
 *   Integer milliseconds of inactivity, or
 *   -1 if the display doesn't support inactivity queries
 *
 * See: https://www.tcl-lang.org/man/tcl9.0/TkLib/Inactive.html
 * --------------------------------------------------------- */

static VALUE
interp_user_inactive_time(VALUE self)
{
    struct tcltk_interp *tip = get_interp(self);
    Tk_Window mainWin;
    Display *display;
    long inactive_ms;

    /* Get the main window for display access */
    mainWin = Tk_MainWindow(tip->interp);
    if (!mainWin) {
        rb_raise(eTclError, "Tk not initialized (no main window)");
    }

    /* Get the display */
    display = Tk_Display(mainWin);
    if (!display) {
        rb_raise(eTclError, "Could not get display");
    }

    /* Query user inactive time */
    inactive_ms = Tk_GetUserInactiveTime(display);

    return LONG2NUM(inactive_ms);
}

/* ---------------------------------------------------------
 * Interp#get_root_coords(window_path)
 *
 * Get absolute screen coordinates of a window's upper-left corner.
 *
 * Arguments:
 *   window_path - Tk window path (e.g., ".", ".frame.button")
 *
 * Returns [x, y] array of root window coordinates.
 *
 * See: https://www.tcl-lang.org/man/tcl9.0/TkLib/GetRootCrd.html
 * --------------------------------------------------------- */

static VALUE
interp_get_root_coords(VALUE self, VALUE window_path)
{
    struct tcltk_interp *tip = get_interp(self);
    Tk_Window mainWin;
    Tk_Window tkwin;
    int x, y;

    StringValue(window_path);

    /* Get the main window for hierarchy reference */
    mainWin = Tk_MainWindow(tip->interp);
    if (!mainWin) {
        rb_raise(eTclError, "Tk not initialized (no main window)");
    }

    /* Find the target window by path */
    tkwin = Tk_NameToWindow(tip->interp, StringValueCStr(window_path), mainWin);
    if (!tkwin) {
        rb_raise(eTclError, "window not found: %s", StringValueCStr(window_path));
    }

    /* Get root coordinates */
    Tk_GetRootCoords(tkwin, &x, &y);

    return rb_ary_new_from_args(2, INT2NUM(x), INT2NUM(y));
}

/* ---------------------------------------------------------
 * Interp#coords_to_window(root_x, root_y)
 *
 * Find which window contains the given screen coordinates (hit testing).
 *
 * Arguments:
 *   root_x - X coordinate in root window (screen) coordinates
 *   root_y - Y coordinate in root window (screen) coordinates
 *
 * Returns window path string, or nil if no Tk window at that location.
 *
 * See: https://manpages.ubuntu.com/manpages/kinetic/man3/Tk_CoordsToWindow.3tk.html
 * --------------------------------------------------------- */

static VALUE
interp_coords_to_window(VALUE self, VALUE root_x, VALUE root_y)
{
    struct tcltk_interp *tip = get_interp(self);
    Tk_Window mainWin;
    Tk_Window foundWin;
    const char *pathName;

    /* Get the main window for application reference */
    mainWin = Tk_MainWindow(tip->interp);
    if (!mainWin) {
        rb_raise(eTclError, "Tk not initialized (no main window)");
    }

    /* Find window at coordinates */
    foundWin = Tk_CoordsToWindow(NUM2INT(root_x), NUM2INT(root_y), mainWin);
    if (!foundWin) {
        return Qnil;
    }

    /* Get window path name */
    pathName = Tk_PathName(foundWin);
    if (!pathName) {
        return Qnil;
    }

    return rb_utf8_str_new_cstr(pathName);
}

/* ---------------------------------------------------------
 * Init_tkutil - Register utility methods on TclTkIp class
 *
 * Called from Init_tcltklib in tcltkbridge.c
 * --------------------------------------------------------- */

void
Init_tkutil(VALUE cTclTkIp)
{
    rb_define_method(cTclTkIp, "tcl_split_list", interp_tcl_split_list, 1);
    rb_define_method(cTclTkIp, "user_inactive_time", interp_user_inactive_time, 0);
    rb_define_method(cTclTkIp, "get_root_coords", interp_get_root_coords, 1);
    rb_define_method(cTclTkIp, "coords_to_window", interp_coords_to_window, 2);
}
