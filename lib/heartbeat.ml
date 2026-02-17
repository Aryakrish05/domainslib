(* Heartbeat scheduling with queue-based work-stealing *)

(* Create a dynamic variable *)
external create_dynamic : 'a -> 'a = "domainslib_create_dynamic"

(* Set fiber-local state directly on current fiber *)
external set_fiber_state : 'a -> 'b -> unit = "domainslib_set_fiber_state"

(* Get fiber-local state *)
external get_fiber_state : 'a -> 'b = "domainslib_get_fiber_state"

external heartbeat_setup : int -> 'a -> ('b -> 'a -> unit) -> 'b -> unit = "domainslib_heartbeat_setup"
external heartbeat_acquire : unit -> unit = "domainslib_heartbeat_acquire"
external heartbeat_release : unit -> unit = "domainslib_heartbeat_release"
external heartbeat_stats : unit -> int * int = "domainslib_heartbeat_stats"
external heartbeat_reset_stats : unit -> unit = "domainslib_heartbeat_reset_stats"

let heartbeat_interval_us = 250
let tokens_per_heartbeat = 15

(* Task status in the queue *)
type 'a task_status =
  | Promoted of ('a * int) Task.promise
  | Claimed
  | Pending of (unit -> 'a)

type task_ref = TaskRef : 'a task_status ref -> task_ref

(* Fiber-local state *)
type state = {
  mutable tokens : int;
  mutable queue : task_ref Queue.t;
  mutable heartbeat_mask : bool;
}

let null_state = { tokens = 0; queue = Queue.create (); heartbeat_mask = false }
let dynamic_key = create_dynamic null_state

(* Get current fiber's state *)
let current_state () : state =
  get_fiber_state dynamic_key

let promote pool (state : state) g =
  let cur_tokens = state.tokens in
  state.tokens <- (cur_tokens - 1) / 2;
  let closure = fun _ ->
    let child_state = { tokens = cur_tokens / 2;
                        queue = Queue.create ();
                        heartbeat_mask = true } in
    set_fiber_state dynamic_key child_state;
    let result = g () in
    let child_tokens = child_state.tokens in
    (result, child_tokens)
  in
  Task.async pool closure

let join : type a. Task.pool -> state -> (a * int) Task.promise -> a =
  fun pool state promise ->
    let (result, child_tokens) = Task.await pool promise in
    state.tokens <- state.tokens + child_tokens;
    result

let promote_at_interrupt pool state =
  state.heartbeat_mask <- false;
  let rec loop () =
    if state.tokens > 0 then
      match Queue.take_opt state.queue with
      | None -> ()
      | Some (TaskRef task) ->
          (match !task with
           | Claimed -> loop ()
           | Pending g ->
               task := Promoted (promote pool state g);
               loop ()
           | Promoted _ -> loop ())
    else ()
  in
  loop ();
  state.heartbeat_mask <- true

(* Heartbeat callback *)
let heartbeat_callback pool (state : state) =
  if state != null_state then begin
    state.tokens <- state.tokens + tokens_per_heartbeat;
    if state.heartbeat_mask then
      promote_at_interrupt pool state
  end

let fork2join : type a b. Task.pool -> (unit -> a) -> (unit -> b) -> a * b =
  fun pool f g ->
    let state = current_state () in
    if state.tokens > 0 then begin
      state.heartbeat_mask <- false;
      let g_promise = promote pool state g in
      state.heartbeat_mask <- true;
      let result_f = f () in
      let result_g = join pool state g_promise in
      (result_f, result_g)
    end else begin
      let task = ref (Pending g) in
      state.heartbeat_mask <- false;
      Queue.add (TaskRef task) state.queue;
      state.heartbeat_mask <- true;
      
      let result_f = f () in
      
      state.heartbeat_mask <- false;
      let result_g =
        match !task with
        | Promoted p ->
            let res = join pool state p in
            state.heartbeat_mask <- true;
            res
        | Pending g ->
            task := Claimed;
            state.heartbeat_mask <- true;
            g ()
        | Claimed ->
            state.heartbeat_mask <- true;
            failwith "Internal Error: Task already claimed"
      in
      (result_f, result_g)
    end

let setup pool =
  heartbeat_setup heartbeat_interval_us dynamic_key heartbeat_callback pool;
  heartbeat_acquire ()

let init_tokens n =
  let state = { tokens = n;
                queue = Queue.create ();
                heartbeat_mask = true } in
  set_fiber_state dynamic_key state

let teardown () =
  heartbeat_release ()

let stats = heartbeat_stats
let reset_stats = heartbeat_reset_stats
