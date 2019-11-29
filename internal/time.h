#ifndef INTERNAL_TIME_H /* -*- C -*- */
#define INTERNAL_TIME_H
/**
 * @file
 * @brief      Internal header for Time.
 * @author     \@shyouhei
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */

#if SIGNEDNESS_OF_TIME_T < 0    /* signed */
# define TIMET_MAX SIGNED_INTEGER_MAX(time_t)
# define TIMET_MIN SIGNED_INTEGER_MIN(time_t)
#elif SIGNEDNESS_OF_TIME_T > 0  /* unsigned */
# define TIMET_MAX UNSIGNED_INTEGER_MAX(time_t)
# define TIMET_MIN ((time_t)0)
#endif
#define TIMET_MAX_PLUS_ONE (2*(double)(TIMET_MAX/2+1))

/* time.c */
struct timeval rb_time_timeval(VALUE);

RUBY_SYMBOL_EXPORT_BEGIN
/* time.c (export) */
void ruby_reset_leap_second_info(void);
RUBY_SYMBOL_EXPORT_END

#endif /* INTERNAL_TIME_H */
