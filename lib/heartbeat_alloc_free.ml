(* Heartbeat with allocation-free task array instead of queue *)

(* Create a dynamic variable *)
external create_dynamic : 'a -> 'a = "domainslib_create_dynamic"

(* Set fiber-local state directly on current fiber - fast! *)
external set_fiber_state : 'a -> 'b -> unit = "domainslib_set_fiber_state"

(* Get fiber-local state *)
external get_fiber_state : 'a -> 'b = "domainslib_get_fiber_state"

external setup_heartbeat : int -> 'a -> ('b -> 'a -> unit) -> 'b -> unit = "domainslib_heartbeat_setup"
external acquire_heartbeat : unit -> unit = "domainslib_heartbeat_acquire"
external release_heartbeat : unit -> unit = "domainslib_heartbeat_release"

module Task_Queue = struct
  type t = {
    task_array: TaskArray.t;
    mutable heartbeat_mask: bool;
  }

  let create () = {
    task_array = TaskArray.create ();
    heartbeat_mask = true;
  }

  let disable_interrupts q = q.heartbeat_mask <- false
  let enable_interrupts q = q.heartbeat_mask <- true
end

(* State stored per fiber *)
type fls_state = {
  mutable tokens: int;
  mutable task_queue: Task_Queue.t;
}

let null_state = { tokens = 0; task_queue = Task_Queue.create () }
let dynamic_key = create_dynamic null_state

(* Get current fiber's state *)
let current_state () : fls_state =
  get_fiber_state dynamic_key

let heartbeat_promotions = 15
let heartbeat_interval_us = 250

let promote pool (state : fls_state) g =
  let cur_tokens = state.tokens in
  state.tokens <- (cur_tokens - 1) / 2;
  let closure = fun _ ->
    let child_state = { tokens = cur_tokens / 2;
                         task_queue = Task_Queue.create () } in
    set_fiber_state dynamic_key child_state;
    let result = g () in
    let child_tokens = child_state.tokens in
    (result, child_tokens)
  in
  Task.async pool closure

let join : type a. Task.pool -> fls_state -> (a * int) Task.promise -> a =
  fun pool state promise ->
    let (result, child_tokens) = Task.await pool promise in
    state.tokens <- state.tokens + child_tokens;
    result

let fork2join : type a b. Task.pool -> (unit -> a) -> (unit -> b) -> a * b =
  fun pool f g ->
    let state = current_state () in
    if state.tokens > 0 then (
      let task_queue = state.task_queue in
      Task_Queue.disable_interrupts task_queue;
      let g_promise = promote pool state g in
      Task_Queue.enable_interrupts task_queue;
      let result_f = f () in
      let result_g = join pool state g_promise in
      (result_f, result_g)
    )
    else (
      let task_queue = state.task_queue in
      let task_array = task_queue.task_array in
      Task_Queue.disable_interrupts task_queue;
      let task_id = TaskArray.add g task_array in
      Task_Queue.enable_interrupts task_queue;

      let result_f = f () in

      Task_Queue.disable_interrupts task_queue;
      let result_g =
        if (TaskArray.is_promoted task_id task_array) then (
          let p = TaskArray.unsafe_get_promise task_id task_array in
          let res = join pool state p in
          Task_Queue.enable_interrupts task_queue;
          res
        )
        else if (TaskArray.is_pending task_id task_array) then (
          let g : unit -> b = TaskArray.unsafe_get_closure task_id task_array in
          TaskArray.pop_back task_array;
          Task_Queue.enable_interrupts task_queue;
          g ()
        )
        else (
          Task_Queue.enable_interrupts task_queue;
          failwith "Internal Error: Task already claimed"
        )
      in
      (result_f, result_g)
    )

let promote_at_interrupt pool state =
  let task_queue = state.task_queue in
  let task_array = task_queue.task_array in
  Task_Queue.disable_interrupts task_queue;
  let rec loop () =
    if state.tokens > 0 then
      (match TaskArray.take_opt task_array with
      | None -> ()
      | Some task_id ->
          if (TaskArray.is_pending task_id task_array) then(
            let g = TaskArray.unsafe_get_closure task_id task_array in
            let g_promise = promote pool state g in
            TaskArray.unsafe_set_promoted task_id g_promise task_array;
            loop ()
          )
          else loop ())
    else () in
  loop ();
  Task_Queue.enable_interrupts task_queue

(* Heartbeat callback *)
let callback pool (state : fls_state) =
  if state != null_state then begin
    state.tokens <- state.tokens + heartbeat_promotions;
    if state.task_queue.heartbeat_mask then
      promote_at_interrupt pool state
  end

let setup pool =
  setup_heartbeat heartbeat_interval_us dynamic_key callback pool;
  acquire_heartbeat ()

let init_tokens n =
  let state = { tokens = n;
                task_queue = Task_Queue.create () } in
  set_fiber_state dynamic_key state

let teardown () =
  release_heartbeat ()
