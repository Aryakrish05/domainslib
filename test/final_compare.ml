let num_domains = try int_of_string Sys.argv.(1) with _ -> 4
let n = try int_of_string Sys.argv.(2) with _ -> 40

module T = Domainslib.Task
module H = Domainslib.Heartbeat

(* Sequential fibonacci *)
let rec fib n =
  if n < 2 then 1
  else fib (n-1) + fib (n-2)

(* Heartbeat version *)
let rec fib_heartbeat pool n =
  if n <= 2 then fib n
  else
    let (a, b) = H.fork2join pool 
      (fun () -> fib_heartbeat pool (n-1))
      (fun () -> fib_heartbeat pool (n-2)) in
    a + b

(* Plain Task.async version *)
let rec fib_async pool n =
  if n <= 2 then fib n
  else
    let a_promise = T.async pool (fun () -> fib_async pool (n-1)) in
    let b = fib_async pool (n-2) in
    let a = T.await pool a_promise in
    a + b

let main =
  Printf.printf "=== Fibonacci(%d) Performance Comparison (%d domains) ===\n\n" n num_domains;
  
  (* Sequential *)
  Printf.printf "--- Sequential ---\n%!";
  let start = Unix.gettimeofday () in
  let seq_result = fib n in
  let seq_time = Unix.gettimeofday () -. start in
  Printf.printf "Result: %d\n" seq_result;
  Printf.printf "Time:   %.4fs\n\n%!" seq_time;

  (* Heartbeat *)
  let pool = T.setup_pool ~num_domains:(num_domains - 1) () in
  Printf.printf "--- Heartbeat (work-stealing) ---\n%!";
  H.setup pool;
  let start = Unix.gettimeofday () in
  let hb_result = T.run pool (fun _ -> 
    H.init_tokens 100;
    fib_heartbeat pool n
  ) in
  let hb_time = Unix.gettimeofday () -. start in
  Printf.printf "Result: %d\n" hb_result;
  Printf.printf "Time:   %.4fs\n\n%!" hb_time;
  H.teardown ();

  (* Task.async *)
  Printf.printf "--- Task.async (naive parallel) ---\n%!";
  let start = Unix.gettimeofday () in
  let async_result = T.run pool (fun _ -> fib_async pool n) in
  let async_time = Unix.gettimeofday () -. start in
  Printf.printf "Result: %d\n" async_result;
  Printf.printf "Time:   %.4fs\n\n%!" async_time;
  
  (* Summary *)
  Printf.printf "=== Summary ===\n";
  Printf.printf "Sequential: %.4fs  (baseline)\n" seq_time;
  Printf.printf "Task.async: %.4fs  (%.2fx speedup)\n" async_time (seq_time /. async_time);
  Printf.printf "Heartbeat:  %.4fs  (%.2fx speedup)\n" hb_time (seq_time /. hb_time);
  Printf.printf "\nHeartbeat vs Task.async: %.2fx\n" (async_time /. hb_time);
  
  T.teardown_pool pool

let () = main
