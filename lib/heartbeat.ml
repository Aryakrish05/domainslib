external fiber_get_tokens : unit -> int = "caml_fiber_get_tokens"
external fiber_set_tokens : int -> unit = "caml_fiber_set_tokens"
external fiber_get_local_queue : unit -> 'a = "caml_fiber_get_local_queue"
external fiber_set_local_queue : 'a -> unit = "caml_fiber_set_local_queue"

(*external print_closure_unsafe  : (unit -> 'a) -> unit = "print_promoting_closure_unsafe"
external print_promise : 'a -> unit = "print_await_promise_unsafe"*)

external setup_heartbeat : int -> ('a -> unit) -> 'b -> unit = "parallel_setup_heartbeat"
external acquire_heartbeat : unit -> unit = "parallel_acquire_heartbeat"
external release_heartbeat : unit -> unit = "parallel_release_heartbeat"

module Heartbeat_Queue=struct
  type 'a t= {mutable queue: 'a Queue.t; mutable heartbeat_mask: bool}

  let create () = {queue=Queue.create(); heartbeat_mask=true}
  (*have heartbeats enabled by default*)

  let get() =
    try fiber_get_local_queue () with Failure _ ->
      let q = create () in
      fiber_set_local_queue q;
      q

  let disable_interrupts q = q.heartbeat_mask <- false

  let enable_interrupts q = q.heartbeat_mask <- true

  let add x q = Queue.add x q.queue

  let take_opt q = Queue.take_opt q.queue

  let interrupts_enabled ()= (get ()).heartbeat_mask
end
let heartbeat_promotions = 15
let heartbeat_interval_us = 250

type _ task_status =
  | Promoted : ('a * int) Task.promise -> 'a task_status
  | Claimed : 'a task_status
  | Pending : (unit -> 'a) -> 'a task_status

type task_ref = TaskRef : 'a task_status ref -> task_ref

let promote pool g =
  let cur_tokens = fiber_get_tokens () in
    fiber_set_tokens ((cur_tokens - 1) / 2);
    let closure = fun _ ->
      (fiber_set_tokens (cur_tokens / 2);
      let result = g () in
      let child_tokens = fiber_get_tokens () in
      (result, child_tokens))
    in
    let result = Task.async pool closure in
    result

let join : type a. Task.pool -> (a * int) Task.promise -> a =
  fun pool promise ->
    let (result, child_tokens) = Task.await pool promise in
    let cur_tokens = fiber_get_tokens () in
    fiber_set_tokens (cur_tokens + child_tokens);
    result

let fork2join : type a b. Task.pool -> (unit -> a) -> (unit -> b) -> a * b =
  fun pool f g ->
    let task = ref (Pending g) in
    
    let fls_queue=Heartbeat_Queue.get () in

    Heartbeat_Queue.disable_interrupts fls_queue;
    
    if (fiber_get_tokens () > 0) then (
      let g_promise = promote pool g in
      task := Promoted g_promise
    )
    else (
      Heartbeat_Queue.add (TaskRef task) fls_queue
    );
    
    Heartbeat_Queue.enable_interrupts fls_queue;

    let result_f = f () in

    Heartbeat_Queue.disable_interrupts fls_queue;
    let result_g =
      match !task with
        | Promoted p -> 
          let res=join pool p in
          Heartbeat_Queue.enable_interrupts fls_queue;
          res
        | Pending g -> 
          task := Claimed;
          Heartbeat_Queue.enable_interrupts fls_queue; 
          g ()
        | Claimed -> Heartbeat_Queue.enable_interrupts fls_queue; failwith "Internal Error: Task already claimed"
    in
    (result_f, result_g)

let promote_at_interrupt pool =
  let fls_queue=Heartbeat_Queue.get () in
  Heartbeat_Queue.disable_interrupts fls_queue;
  let rec loop () =
    if(fiber_get_tokens () > 0) then 
      (match Heartbeat_Queue.take_opt fls_queue with
        | None -> ()
        | Some (TaskRef task) ->
          (match !task with
            | Claimed -> loop ()
            | Pending g ->
                  task := Promoted (promote pool g);
                  loop ()
            | Promoted _ -> loop ()))
    else () in 
  loop ();
  Heartbeat_Queue.enable_interrupts fls_queue

(*If heartbeats are disabled - I just increment the fiber count and pass*)
let callback pool =
  fiber_set_tokens (fiber_get_tokens () + heartbeat_promotions);
  if Heartbeat_Queue.interrupts_enabled () then
  promote_at_interrupt pool

let setup pool =
  setup_heartbeat heartbeat_interval_us callback pool;
  acquire_heartbeat ()

let init_tokens n =
  fiber_set_tokens n

let teardown () =
  release_heartbeat ()
