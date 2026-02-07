/*
 * tcl9compat.h - Tcl 8.x/9.x compatibility layer for Ruby/Tk
 *
 * This header provides compatibility definitions to allow the Ruby/Tk
 * extension to compile against both Tcl 8.x and Tcl 9.x.
 *
 * Key changes in Tcl 9.0:
 * - Tcl_Size replaces int for length/index parameters (supports 64-bit)
 * - Tcl_UniChar is now 32-bit (was 16-bit on Windows)
 * - CONST macro removed (use const directly)
 * - Threading always enabled
 * - Stubs ABI changes
 */

#ifndef TCL9COMPAT_H
#define TCL9COMPAT_H

#include <tcl.h>

/*
 * Tcl_Size compatibility
 *
 * Tcl 9.0 introduces Tcl_Size as a signed 64-bit type for sizes and indices.
 * For Tcl 8.x, we define it as int for compatibility.
 */
#ifndef TCL_SIZE_MAX
/* Tcl 8.x does not have Tcl_Size, define it as int */
typedef int Tcl_Size;
#define TCL_SIZE_MAX INT_MAX
#define TCL_SIZE_MODIFIER ""
#endif

/*
 * CONST/CONST84/CONST86 compatibility
 *
 * Tcl 9.0 removes the CONST macro. All code should use standard 'const'.
 * For compatibility with older Tcl versions, we ensure these are defined.
 */
#ifndef CONST
#define CONST const
#endif

/* CONST84/CONST86 are always const for Tcl 8.6+ */
#ifndef CONST84
#define CONST84 const
#endif

#ifndef CONST86
#define CONST86 const
#endif

/*
 * Command procedure type compatibility
 *
 * Tcl 9.0 uses Tcl_Size for objc parameter in command procedures.
 * We provide a wrapper macro to handle both versions.
 */
#if TCL_MAJOR_VERSION >= 9
#define RBTK_OBJC_TYPE Tcl_Size
#else
#define RBTK_OBJC_TYPE int
#endif

/*
 * String length type for Tcl API calls
 *
 * Tcl 9.0 uses Tcl_Size* for length parameters in functions like
 * Tcl_GetStringFromObj(). We provide a type alias.
 */
#if TCL_MAJOR_VERSION >= 9
#define RBTK_STRLEN_TYPE Tcl_Size
#else
#define RBTK_STRLEN_TYPE int
#endif

/*
 * NULL pointer for length parameters when caller doesn't need the length.
 *
 * Many Tcl functions like Tcl_GetStringFromObj() take an optional length
 * output parameter. When you don't need the length, pass NULL. This macro
 * provides the correctly-typed NULL for the Tcl version being compiled against.
 *
 * Usage:
 *   str = Tcl_GetStringFromObj(obj, TCL_SIZE_NULL);  // don't need length
 *   str = Tcl_GetStringFromObj(obj, &len);           // need length (len is Tcl_Size)
 */
#define TCL_SIZE_NULL ((Tcl_Size*)NULL)

/*
 * Tcl_UniChar compatibility
 *
 * Tcl 9.0 makes Tcl_UniChar always 32-bit (int).
 * Previously it was 16-bit on Windows.
 * This shouldn't require code changes in most cases, but we provide
 * a check macro for code that needs to handle it specially.
 */
#if TCL_MAJOR_VERSION >= 9
#define RBTK_UNICHAR_IS_32BIT 1
#else
#ifdef _WIN32
#define RBTK_UNICHAR_IS_32BIT 0
#else
#define RBTK_UNICHAR_IS_32BIT 1
#endif
#endif

/*
 * Threading compatibility
 *
 * Tcl 9.0 always has threading enabled (TCL_THREADS is always defined).
 * For Tcl 8.x, it's optional.
 */
#if TCL_MAJOR_VERSION >= 9
#ifndef TCL_THREADS
#define TCL_THREADS 1
#endif
#endif

/*
 * Stubs version compatibility
 *
 * The minimum stubs version should be set appropriately.
 * For Tcl 9.0+, we need at least 8.6 stubs (the last 8.x version).
 */
/* Require at least 8.6 stubs (minimum supported version) */
#define RBTK_TCL_STUBS_VERSION "8.6"
#define RBTK_TK_STUBS_VERSION "8.6"

/*
 * Deprecated API compatibility wrappers
 *
 * Some Tcl 8.x APIs are deprecated or changed in 9.0.
 * We provide compatibility where needed.
 */

/*
 * Tcl_GetStringResult is deprecated in 9.0 but still works.
 * New code should use Tcl_GetObjResult() instead.
 */
#if TCL_MAJOR_VERSION >= 9
/* Use the existing function, it's still available */
#endif

/*
 * Tcl_AppendResult is deprecated in 9.0.
 * New code should use Tcl_AppendObjToObj() or Tcl_SetObjResult().
 * For now, the function still works, so no wrapper needed.
 */

/*
 * TCL_INTERP_DESTROYED compatibility (TIP 543)
 *
 * Tcl 9.0 removes the TCL_INTERP_DESTROYED flag entirely.
 * Code should use Tcl_InterpDeleted() instead (available since Tcl 7.5).
 *
 * For variable trace callbacks that check this flag, we provide a macro
 * that checks using Tcl_InterpDeleted() on Tcl 9.x.
 *
 * Note: The callback receives flags and interp, so we pass interp as param.
 */
#if TCL_MAJOR_VERSION >= 9
#define RBTK_INTERP_DESTROYED(interp, flags) Tcl_InterpDeleted(interp)
#else
#define RBTK_INTERP_DESTROYED(interp, flags) ((flags) & TCL_INTERP_DESTROYED)
#endif

/*
 * Tk_Preserve/Tk_Release compatibility
 *
 * These Tk functions were deprecated and removed in favor of the
 * equivalent Tcl functions: Tcl_Preserve/Tcl_Release.
 * The Tcl versions have been available since Tcl 7.5.
 */
#if TCL_MAJOR_VERSION >= 9
#define RbTk_Preserve(clientData) Tcl_Preserve(clientData)
#define RbTk_Release(clientData) Tcl_Release(clientData)
#else
/* On Tcl 8.x, use Tk versions if available, otherwise Tcl versions */
#ifdef Tk_Preserve
#define RbTk_Preserve(clientData) Tk_Preserve(clientData)
#define RbTk_Release(clientData) Tk_Release(clientData)
#else
#define RbTk_Preserve(clientData) Tcl_Preserve(clientData)
#define RbTk_Release(clientData) Tcl_Release(clientData)
#endif
#endif

/*
 * Tcl_MakeSafe compatibility (TIP 624)
 * https://core.tcl-lang.org/tips/doc/trunk/tip/624.md
 *
 * Tcl_MakeSafe() was removed in Tcl 9.0.
 * In Tcl 9, safe interpreters must be created safe from the start
 * using Tcl_CreateSlave with the safe flag, or Tcl_CreateInterp
 * followed by safe initialization. An existing interpreter cannot
 * be converted to safe mode.
 *
 * We provide a compatibility macro that returns TCL_ERROR on Tcl 9.
 */
#if TCL_MAJOR_VERSION >= 9
#define RBTK_HAS_MAKE_SAFE 0
#define RbTk_MakeSafe(interp) \
    (Tcl_SetObjResult((interp), Tcl_NewStringObj("Tcl_MakeSafe not available in Tcl 9.x", -1)), TCL_ERROR)
#else
#define RBTK_HAS_MAKE_SAFE 1
#define RbTk_MakeSafe(interp) Tcl_MakeSafe(interp)
#endif

/*
 * Safe memory allocation
 *
 * Update the allocation macro to use proper size type.
 */
#undef RbTk_ALLOC_N
#define RbTk_ALLOC_N(type, n) ((type *)ckalloc(sizeof(type) * (size_t)(n)))

/*
 * Version detection macros
 */
#define RBTK_TCL_VERSION_GE(major, minor) \
    (TCL_MAJOR_VERSION > (major) || \
     (TCL_MAJOR_VERSION == (major) && TCL_MINOR_VERSION >= (minor)))

#define RBTK_TCL_VERSION_LT(major, minor) \
    (TCL_MAJOR_VERSION < (major) || \
     (TCL_MAJOR_VERSION == (major) && TCL_MINOR_VERSION < (minor)))

#define RBTK_IS_TCL9 (TCL_MAJOR_VERSION >= 9)
#define RBTK_IS_TCL8 (TCL_MAJOR_VERSION == 8)

#endif /* TCL9COMPAT_H */
