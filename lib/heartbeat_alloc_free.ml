external fiber_get_tokens : unit -> int = "caml_fiber_get_tokens"
external fiber_set_tokens : int -> unit = "caml_fiber_set_tokens"
external fiber_get_local_queue : unit -> 'a = "caml_fiber_get_local_queue"
external fiber_set_local_queue : 'a -> unit = "caml_fiber_set_local_queue"

(*external print_closure_unsafe  : (unit -> 'a) -> unit = "print_promoting_closure_unsafe"
external print_promise : 'a -> unit = "print_await_promise_unsafe"*)

external setup_heartbeat : int -> ('a -> unit) -> 'b -> unit = "parallel_setup_heartbeat"
external acquire_heartbeat : unit -> unit = "parallel_acquire_heartbeat"
external release_heartbeat : unit -> unit = "parallel_release_heartbeat"

module Task_Queue = struct
  type t = {
    task_array: TaskArray.t;
    mutable heartbeat_mask: bool;
  }

  let create () = {
    task_array = TaskArray.create ();
    heartbeat_mask = true;
  }

  let get () =
    try fiber_get_local_queue () with Failure _ ->
      let q = create () in
      fiber_set_local_queue q;
      q

  let disable_interrupts q = q.heartbeat_mask <- false
  let enable_interrupts q = q.heartbeat_mask <- true
  let interrupts_enabled () = (get ()).heartbeat_mask
end

let heartbeat_promotions = 15
let heartbeat_interval_us = 250

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
    let task_queue = Task_Queue.get () in
    let task_array = task_queue.task_array in
    
    Task_Queue.disable_interrupts task_queue;

    let task_id = TaskArray.add g task_array in
  
    if (fiber_get_tokens () > 0) then (
      let g_promise = promote pool g in
      TaskArray.unsafe_set_promoted task_id g_promise task_array
    );
    
    Task_Queue.enable_interrupts task_queue;

    let result_f = f () in

    Task_Queue.disable_interrupts task_queue;
    let result_g =
      if TaskArray.is_promoted task_id task_array then (
        let p = TaskArray.unsafe_get_promise task_id task_array in
        let res = join pool p in
        Task_Queue.enable_interrupts task_queue;
        res
      )
      else if TaskArray.is_pending task_id task_array then (
        let g : unit -> b = TaskArray.unsafe_get_closure task_id task_array in
        TaskArray.unsafe_set_claimed task_id task_array;
        Task_Queue.enable_interrupts task_queue;
        g ()
      )
      else (
        Task_Queue.enable_interrupts task_queue;
        failwith "Internal Error: Task already claimed"
      )
    in
    (result_f, result_g)

let promote_at_interrupt pool =
  let task_queue = Task_Queue.get () in
  let task_array = task_queue.task_array in
  Task_Queue.disable_interrupts task_queue;
  let rec loop () =
    if fiber_get_tokens () > 0 then
      (match TaskArray.take_opt task_array with
      | None -> ()
      | Some task_id ->
          if TaskArray.is_pending task_id task_array then(
            let g = TaskArray.unsafe_get_closure task_id task_array in
            let g_promise = promote pool g in
            TaskArray.unsafe_set_promoted task_id g_promise task_array;
            loop ()
          )
          else loop ()) 
    else () in
  loop ();
  Task_Queue.enable_interrupts task_queue

(*If heartbeats are disabled - I just increment the fiber count and pass*)
let callback pool =
  fiber_set_tokens (fiber_get_tokens () + heartbeat_promotions);
  if Task_Queue.interrupts_enabled () then
  promote_at_interrupt pool

let setup pool =
  setup_heartbeat heartbeat_interval_us callback pool;
  acquire_heartbeat ()

let init_tokens n =
  fiber_set_tokens n

let teardown () =
  release_heartbeat ()
