#ifndef RBIMPL_ATTR_FORCEINLINE_H                    /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_ATTR_FORCEINLINE_H
/**
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @warning    Symbols   prefixed  with   either  `RBIMPL`   or  `rbimpl`   are
 *             implementation details.   Don't take  them as canon.  They could
 *             rapidly appear then vanish.  The name (path) of this header file
 *             is also an  implementation detail.  Do not expect  it to persist
 *             at the place it is now.  Developers are free to move it anywhere
 *             anytime at will.
 * @note       To  ruby-core:  remember  that   this  header  can  be  possibly
 *             recursively included  from extension  libraries written  in C++.
 *             Do not  expect for  instance `__VA_ARGS__` is  always available.
 *             We assume C99  for ruby itself but we don't  assume languages of
 *             extension libraries. They could be written in C++98.
 * @brief      Defines #RBIMPL_ATTR_FORCEINLINE.
 */
#include "ruby/impl/compiler_since.h"
#include "ruby/impl/has/attribute.h"

/**
 * Wraps (or  simulates) `__forceinline`.  MSVC complains  on declarations like
 * `static inline __forceinline void foo()`.   It  seems  MSVC's  `inline`  and
 * `__forceinline` are mutually exclusive.  We have to mimic that behaviour for
 * non-MSVC compilers.
 */
#if RBIMPL_COMPILER_SINCE(MSVC, 12, 0, 0)
# define RBIMPL_ATTR_FORCEINLINE() __forceinline
#elif RBIMPL_HAS_ATTRIBUTE(always_inline)
# define RBIMPL_ATTR_FORCEINLINE() __attribute__((__always_inline__)) inline
#else
# define RBIMPL_ATTR_FORCEINLINE() inline
#endif

#endif /* RBIMPL_ATTR_FORCEINLINE_H */
