#ifndef RUBY_THREAD_NONE_H
#define RUBY_THREAD_NONE_H

#define RB_NATIVETHREAD_LOCK_INIT (void)(0)
#define RB_NATIVETHREAD_COND_INIT (void)(0)

// no-thread impl doesn't use TLS but define this to avoid using tls key
// based implementation in vm.c
#define RB_THREAD_LOCAL_SPECIFIER

typedef struct native_thread_data_struct {} native_thread_data_t;

typedef struct rb_global_vm_lock_struct {} rb_global_vm_lock_t;

RUBY_EXTERN struct rb_execution_context_struct *ruby_current_ec;

#endif /* RUBY_THREAD_NONE_H */
