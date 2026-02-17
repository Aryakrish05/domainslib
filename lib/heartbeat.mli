(** Heartbeat-based work-stealing scheduler for balanced fork-join parallelism.
    
    This module implements token-based work scheduling with periodic heartbeat
    interrupts to promote queued tasks, providing automatic load balancing without
    explicit work stealing. *)

(** {1 Setup and Teardown} *)

val setup : Task.pool -> unit
(** [setup pool] initializes the heartbeat scheduler for the given pool.
    
    @param pool The task pool to use for promoted work    
    Must be called once before using {!fork2join}. Spawns a background heartbeat
    thread that sends periodic interrupts to all domains. *)

val init_tokens : int -> unit
(** [init_tokens n] initializes the token count for the current fiber.
    Should be called at the start of parallel computation before using fork2join. *)

val teardown : unit -> unit
(** [teardown ()] pauses the heartbeat scheduler.
    
    The heartbeat thread goes to sleep when all domains have called teardown.
    Can be reactivated by calling {!setup} again. *)

(** {1 Fork-Join Parallelism} *)

(** [fork2join pool f g] executes [f] and [g] in a fork-join pattern with
    token-based work stealing.
    
    Behavior depends on available tokens:
    - If tokens > 1: Spawns [g] as async task, splits tokens
    - If tokens ≤ 1: Queues [g] to fiber-local deque for later promotion
    
    Always executes [f] immediately. When [f] completes:
    - If [g] was promoted (by heartbeat interrupt), awaits its result
    - Otherwise, executes [g] sequentially
    
    @return Tuple [(result_f, result_g)]
    @raise Failure if fiber-local storage is not properly initialized *)
val fork2join : Task.pool -> (unit -> 'a) -> (unit -> 'b) -> 'a * 'b

(** {1 Debug/Statistics} *)

val stats : unit -> int * int
(** [stats ()] returns [(heartbeat_count, callbacks_invoked)] for debugging. *)

val reset_stats : unit -> unit
(** Reset heartbeat statistics. *)
