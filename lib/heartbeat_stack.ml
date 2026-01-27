(* Fiber Local Storage *)
external fiber_get_tokens : unit -> int = "caml_fiber_get_tokens"
external fiber_set_tokens : int -> unit = "caml_fiber_set_tokens"
external fiber_get_local_deque : unit -> 'a = "caml_fiber_get_local_deque"
external fiber_set_local_deque : 'a -> unit = "caml_fiber_set_local_deque"

(* Heartbeat *)
external setup_heartbeat : int -> ('a -> unit) -> 'b -> unit = "parallel_setup_heartbeat"
external acquire_heartbeat : unit -> unit = "parallel_acquire_heartbeat"
external release_heartbeat : unit -> unit = "parallel_release_heartbeat"

let heartbeat_promotions = 15
let heartbeat_interval_us = 250

(** Task status with GADTs - stores function in Pending constructor. *)
type _ task_status =
  | Promoted : ('a * int) Task.promise -> 'a task_status
  | Claimed : 'a task_status
  | Pending : (unit -> 'a) -> 'a task_status

(** Existential wrapper to hide the type parameter. *)
type task_ref = TaskRef : 'a task_status ref -> task_ref

let promote pool g =
  let cur_tokens = fiber_get_tokens () in
  assert (cur_tokens > 0);
  fiber_set_tokens ((cur_tokens - 1) / 2);
  let closure = fun _ ->
    fiber_set_tokens (cur_tokens / 2);
    let result = g () in
    let child_tokens = fiber_get_tokens () in
    (result, child_tokens)
  in
  Task.async pool closure

let join : type a. Task.pool -> (a * int) Task.promise -> a =
  fun pool promise ->
    let (result, child_tokens) = Task.await pool promise in
    let cur_tokens = fiber_get_tokens () in
    fiber_set_tokens (cur_tokens + child_tokens);
    result

let fork2join : type a b. Task.pool -> (unit -> a) -> (unit -> b) -> a * b =
  fun pool f g ->
    let task = ref (Pending g) in
    
    if fiber_get_tokens () > 1 then (
      task := Promoted (promote pool g)
    ) else (
      let fls_stack =
        try fiber_get_local_deque () with Failure _ ->
          let s = Stack.create () in
          fiber_set_local_deque s;
          s
      in
      Stack.push (TaskRef task) fls_stack
    );
    
    let result_f = f () in
    
    let result_g =
      match !task with
      | Promoted p -> join pool p
      | Pending g -> task := Claimed; g ()
      | Claimed -> failwith "Internal Error: Task already claimed"
    in
    (result_f, result_g)

let rec promote_at_interrupt pool =
  let fls_stack =
    try fiber_get_local_deque () with Failure _ ->
      let s = Stack.create () in
      fiber_set_local_deque s;
      s
  in
  if Stack.is_empty fls_stack then ()
  else
    match Stack.pop_opt fls_stack with
    | None -> ()
    | Some (TaskRef task) ->
        (match !task with
        | Claimed -> promote_at_interrupt pool
        | Pending g ->
            let p = promote pool g in
            task := Promoted p;
            if fiber_get_tokens () > 1 then
              promote_at_interrupt pool
        | Promoted _ -> promote_at_interrupt pool)

let callback pool =
  fiber_set_tokens (fiber_get_tokens () + heartbeat_promotions);
  promote_at_interrupt pool

let setup pool =
  setup_heartbeat heartbeat_interval_us callback pool;
  acquire_heartbeat ()

let init_tokens n =
  fiber_set_tokens n

let teardown () =
  release_heartbeat ()
