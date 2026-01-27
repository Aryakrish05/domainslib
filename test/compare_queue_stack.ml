let num_domains = try int_of_string Sys.argv.(1) with _ -> 4
let n = try int_of_string Sys.argv.(2) with _ -> 35

module T = Domainslib.Task
module HQ = Domainslib.Heartbeat       (* Queue-based *)
module HS = Domainslib.Heartbeat_stack  (* Stack-based *)

(* Sequential fibonacci *)
let rec fib n =
  if n < 2 then 1
  else fib (n-1) + fib (n-2)

(* Heartbeat Queue version *)
let rec fib_queue pool n =
  if n <= 20 then fib n
  else
    let (a, b) = HQ.fork2join pool 
      (fun () -> fib_queue pool (n-1))
      (fun () -> fib_queue pool (n-2)) in
    a + b

(* Heartbeat Stack version *)
let rec fib_stack pool n =
  if n <= 20 then fib n
  else
    let (a, b) = HS.fork2join pool 
      (fun () -> fib_stack pool (n-1))
      (fun () -> fib_stack pool (n-2)) in
    a + b

let main =
  Printf.printf "=== Queue vs Stack Comparison: fib(%d) with %d domains ===\n\n" n num_domains;
  
  let pool = T.setup_pool ~num_domains:(num_domains - 1) () in
  
  (* Test Queue-based *)
  Printf.printf "--- Queue-based (FIFO) ---\n%!";
  HQ.setup pool;
  let start = Unix.gettimeofday () in
  let queue_result = T.run pool (fun _ -> 
    HQ.init_tokens 100;
    fib_queue pool n
  ) in
  let queue_time = Unix.gettimeofday () -. start in
  Printf.printf "Result: %d\n" queue_result;
  Printf.printf "Time:   %.4fs\n\n%!" queue_time;
  HQ.teardown ();
  
  (* Small delay *)
  Unix.sleepf 0.1;
  
  (* Test Stack-based *)
  Printf.printf "--- Stack-based (LIFO) ---\n%!";
  HS.setup pool;
  let start = Unix.gettimeofday () in
  let stack_result = T.run pool (fun _ -> 
    HS.init_tokens 100;
    fib_stack pool n
  ) in
  let stack_time = Unix.gettimeofday () -. start in
  Printf.printf "Result: %d\n" stack_result;
  Printf.printf "Time:   %.4fs\n\n%!" stack_time;
  HS.teardown ();
  
  T.teardown_pool pool;
  
  (* Summary *)
  Printf.printf "=== Summary ===\n";
  Printf.printf "Queue (FIFO): %.4fs\n" queue_time;
  Printf.printf "Stack (LIFO): %.4fs\n" stack_time;
  Printf.printf "Difference:   %.4fs (%.1f%%)\n" 
    (abs_float (queue_time -. stack_time))
    (100. *. abs_float (queue_time -. stack_time) /. (min queue_time stack_time));
  if queue_time < stack_time then
    Printf.printf "Queue is %.2fx faster\n" (stack_time /. queue_time)
  else if stack_time < queue_time then
    Printf.printf "Stack is %.2fx faster\n" (queue_time /. stack_time)
  else
    Printf.printf "Both have identical performance\n"

let () = main
