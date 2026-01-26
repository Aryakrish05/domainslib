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

type 'a task_ref = {
  mutable status : 'a task_status;
  compute : unit -> 'a;
}

and _ task_status =
  | Pending : 'a task_status
  | Promoted : ('a * int) Task.promise -> 'a task_status  
  | Claimed : 'a task_status

type task = Task : 'a task_ref -> task

let promote : type b. Task.pool -> b task_status -> (unit -> b) -> b task_status = 
  fun pool status compute ->
    match status with
    | Promoted _ | Claimed -> status
    | Pending ->
        let raw_tokens = fiber_get_tokens () in
        let tokens = if raw_tokens < 0 || raw_tokens > 100000 then 0 else raw_tokens in
        if tokens < 1 then Pending
        else begin
          let new_tokens = max 0 (tokens / 2) in
          fiber_set_tokens new_tokens;
          let promise = Task.async pool (fun () ->
            let child_tokens = max 0 new_tokens in
            fiber_set_tokens child_tokens;
            let res = compute () in
            let final_tokens = fiber_get_tokens () in
            let final_tokens = if final_tokens < 0 || final_tokens > 100000 then 0 else final_tokens in
            (res, final_tokens)
          ) in
          Promoted promise
        end

let join : type b. Task.pool -> (b * int) Task.promise -> b =
  fun pool promise ->
    let (result, child_tokens) = Task.await pool promise in
    let child_tokens = if child_tokens < 0 || child_tokens > 100000 then 0 else child_tokens in
    let cur_tokens = fiber_get_tokens () in
    let cur_tokens = if cur_tokens < 0 || cur_tokens > 100000 then 0 else cur_tokens in
    fiber_set_tokens (cur_tokens + child_tokens);
    result

let fork2join : type a b. Task.pool -> (unit -> a) -> (unit -> b) -> a * b =
  fun pool f g ->
    let raw_tokens = fiber_get_tokens () in
    let tokens = 
      if raw_tokens < 0 then begin
        fiber_set_tokens 0;
        0
      end else if raw_tokens > 100000 then begin
        fiber_set_tokens 0;
        0
      end else
        raw_tokens
    in
    
    let task_ref = { compute = g; status = Pending } in
    let task = Task task_ref in
    
    if tokens > 1 then begin
      let new_status = promote pool task_ref.status task_ref.compute in
      task_ref.status <- new_status
    end else begin
      let fls_queue =
        try fiber_get_local_deque () with Failure _ -> (
          let q = Queue.create () in
          fiber_set_local_deque q;
          q
        )
      in
      Queue.add task fls_queue
    end;
    
    let result_f = f () in
    let result_g : b =
      match task_ref.status with
      | Promoted p -> join pool p
      | Pending ->
          task_ref.status <- Claimed;
          task_ref.compute ()
      | Claimed ->
          (* Race: someone else claimed it, but we still execute *)
          task_ref.compute ()
    in
    (result_f, result_g)

let rec promote_at_interrupt pool =
  let fls_queue =
    try fiber_get_local_deque () with Failure _ -> (
      let q = Queue.create () in
      fiber_set_local_deque q;
      q
    ) in
  if Queue.is_empty fls_queue then ()
  else
    match Queue.take_opt fls_queue with
    | None -> ()
    | Some (Task task_ref) ->
        let new_status = promote pool task_ref.status task_ref.compute in
        task_ref.status <- new_status;
        if fiber_get_tokens () > 1 then
          promote_at_interrupt pool

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
