(* Fiber Local Storage *)
external fiber_get_tokens : unit -> int = "caml_fiber_get_tokens"
external fiber_set_tokens : int -> unit = "caml_fiber_set_tokens"
external fiber_get_local_queue : unit -> 'a = "caml_fiber_get_local_queue"
external fiber_set_local_queue : 'a -> unit = "caml_fiber_set_local_queue"

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

(*currently - if cur_tokens <=0 , then we are not gonna parallelise
  might be slightly bad*)
let promote pool g =
  let cur_tokens = fiber_get_tokens () in
  if(cur_tokens <= 0) then (Pending g)
  else
    (fiber_set_tokens ((cur_tokens - 1) / 2);
    let closure = fun _ ->
      (fiber_set_tokens (cur_tokens / 2);
      let result = g () in
      let child_tokens = fiber_get_tokens () in
      (result, child_tokens))
    in
    Promoted (Task.async pool closure))

let join : type a. Task.pool -> (a * int) Task.promise -> a =
  fun pool promise ->
    (*print_endline("Awaiting for my promise");*)
    let (result, child_tokens) = Task.await pool promise in
    let cur_tokens = fiber_get_tokens () in
    fiber_set_tokens (cur_tokens + child_tokens);
    (*print_endline("Received my promise");*)
    result

let fork2join : type a b. Task.pool -> (unit -> a) -> (unit -> b) -> a * b =
  fun pool f g ->
    let task = ref (Pending g) in
    
    if fiber_get_tokens () > 0 then (
      task := promote pool g
    )
    else (
      let fls_queue =
        try fiber_get_local_queue () with Failure _ ->
          let q = Queue.create () in
          fiber_set_local_queue q;
          q
      in
      Queue.add (TaskRef task) fls_queue
    );
    
    let result_f = f () in
    
    let result_g =
      match !task with
      | Promoted p -> 
        print_endline("Joining my promoted task");
        let res=join pool p in
        print_endline("Joined my promoted task");res
      | Pending g -> task := Claimed; g ()
      | Claimed -> failwith "Internal Error: Task already claimed"
    in
    (result_f, result_g)

let rec promote_at_interrupt pool =
  let fls_queue =
    try fiber_get_local_queue () with Failure _ ->
      let q = Queue.create () in
      fiber_set_local_queue q;
      q
  in
  if(fiber_get_tokens () > 0) then 
    (match Queue.take_opt fls_queue with
      | None -> ()
      | Some (TaskRef task) ->
        (match !task with
          | Claimed -> promote_at_interrupt pool
          | Pending g ->
            (match promote pool g with
              | Promoted _ as p -> 
                task := p; 
                promote_at_interrupt pool
              | Pending _ ->
                (* Not enough tokens, put it back in the queue *)
                Queue.add (TaskRef task) fls_queue
              | Claimed -> failwith "Internal Error: Task couldn't have been claimed here")
          | Promoted _ -> promote_at_interrupt pool))
  else () 

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
