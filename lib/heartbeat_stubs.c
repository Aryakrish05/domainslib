#define _POSIX_C_SOURCE 199309L
#define CAML_INTERNALS  

//We are assuming that CAML_RUNTIME_5 is defined

#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/fiber.h>
#include <caml/platform.h>
#include <caml/domain.h>
#include <caml/callback.h>

/*Fiber Local Storage Functions*/
CAMLprim value caml_fiber_get_tokens(value unit)
{
  return Val_long(Caml_state->current_stack->token_cnt);
}


CAMLprim value caml_fiber_set_tokens(value n)
{
  Caml_state->current_stack->token_cnt = Long_val(n);
  return Val_unit;
}


CAMLprim value caml_fiber_get_local_deque(value unit)
{
  CAMLparam0();
  value dq = Caml_state->current_stack->fls_local_deque;
  
  if (dq == Val_unit) {
    caml_failwith("Fiber-local deque not initialized");
  }
  
  CAMLreturn(dq);
}


CAMLprim value caml_fiber_set_local_deque(value deque)
{
  CAMLparam1(deque);
  struct stack_info* stack = Caml_state->current_stack;
  
  if (stack->fls_local_deque == Val_unit) {
    caml_register_generational_global_root(&stack->fls_local_deque);
  }
  
  stack->fls_local_deque = deque;
  
  CAMLreturn(Val_unit);
}

/*Heartbeat Functions*/
#include <stdbool.h>
#include <pthread.h>
#include <errno.h>
#include <time.h>

#define HB_INTERRUPT_FLAG ((uintnat)(1 << 1))

typedef struct {
  pthread_mutex_t mut;
  pthread_cond_t cond;
  uint64_t count;
} heartbeat_refcount_t;
static heartbeat_refcount_t heartbeat_refcount = {PTHREAD_MUTEX_INITIALIZER,
                                                  PTHREAD_COND_INITIALIZER, 0};

static value heartbeat_callback;

static uintnat heartbeat_interval_us;

static value heartbeat_pool;

static void (*existing_domain_external_interrupt_hook)(void);

static void parallel_domain_external_interrupt_hook() {
  uintnat mask = ~HB_INTERRUPT_FLAG;
  atomic_uintnat *request = &Caml_state->requested_external_interrupt;

  if (atomic_fetch_and_explicit(request, mask, memory_order_seq_cst) &
      HB_INTERRUPT_FLAG) {
    caml_callback(heartbeat_callback, heartbeat_pool);
  }

  if (existing_domain_external_interrupt_hook) {
    existing_domain_external_interrupt_hook();
  }
}

static void *parallel_heartbeat_thread(__attribute__((unused)) void *param) {

  struct timespec interval = {0};
  interval.tv_nsec = heartbeat_interval_us * 1000;

  while (true) {

    pthread_mutex_lock(&heartbeat_refcount.mut);
    //while loop to avoid spurious wakeups
    while (heartbeat_refcount.count == 0) {
      pthread_cond_wait(&heartbeat_refcount.cond, &heartbeat_refcount.mut);
    }
    pthread_mutex_unlock(&heartbeat_refcount.mut);

    struct timespec remain = {0};

#ifdef __APPLE__
    int err = nanosleep(&interval, &remain);
    while (err == EINTR) {
      err = nanosleep(&remain, &remain);
    }
#else
    int err = clock_nanosleep(CLOCK_MONOTONIC, 0, &interval, &remain);
    while (err == EINTR) {
      err = clock_nanosleep(CLOCK_MONOTONIC, 0, &remain, &remain);
    }
#endif

    if (err) {
      caml_fatal_error("Heartbeat thread failed to sleep: %d\n", err);
    }

    caml_external_interrupt_all_signal_safe(HB_INTERRUPT_FLAG);
  }

  return NULL;
}

static void parallel_heartbeat_incref() {
  pthread_mutex_lock(&heartbeat_refcount.mut);
  if (heartbeat_refcount.count++ == 0) {
    pthread_cond_signal(&heartbeat_refcount.cond);
  }
  pthread_mutex_unlock(&heartbeat_refcount.mut);
}

static void parallel_heartbeat_decref() {
  pthread_mutex_lock(&heartbeat_refcount.mut);
  heartbeat_refcount.count--;
  pthread_mutex_unlock(&heartbeat_refcount.mut);
}

CAMLprim value parallel_setup_heartbeat(value interval_us,value callback,value pool) {
  CAMLparam3(interval_us, callback, pool);

  heartbeat_interval_us = Long_val(interval_us);
  heartbeat_callback = callback;
  heartbeat_pool = pool;
  
  caml_register_generational_global_root(&heartbeat_callback);
  caml_register_generational_global_root(&heartbeat_pool);

  CAMLreturn(Val_unit);
}

//potential changes
CAMLprim value parallel_acquire_heartbeat(__attribute__((unused)) value unit) {

  static atomic_uintnat heartbeat_running = 0;
  uintnat running = 0;
  /* relaxed here is ok since our only concern is that [running] is set once */
  if (atomic_load_explicit(&heartbeat_running, memory_order_relaxed) == 0 &&
      atomic_compare_exchange_strong_explicit(
          &heartbeat_running, &running, 1, memory_order_relaxed, memory_order_relaxed)) {
  
    existing_domain_external_interrupt_hook = caml_domain_external_interrupt_hook;
    caml_domain_external_interrupt_hook = &parallel_domain_external_interrupt_hook;

    sigset_t mask, old_mask;
    sigfillset(&mask);
    pthread_sigmask(SIG_BLOCK, &mask, &old_mask);

    pthread_t thread;
    int err = pthread_create(&thread, NULL, parallel_heartbeat_thread, NULL);
    if (err) {
      caml_fatal_error("Failed to create heartbeat thread: %d\n", err);
    }
    
    pthread_sigmask(SIG_SETMASK, &old_mask, NULL);
  }

  parallel_heartbeat_incref();
  return Val_unit;
}

//potential changes
CAMLprim value parallel_release_heartbeat(__attribute__((unused)) value unit) {
  parallel_heartbeat_decref();
  return Val_unit;
}
