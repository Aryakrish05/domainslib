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
  let pool = T.setup_pool ~num_domains:(num_domains - 1) () in
  
  Printf.printf "=== Benchmark: fib(%d) with %d domains (single run each) ===\n\n" n num_domains;
  
  (* Benchmark Heartbeat *)
  Printf.printf "--- Heartbeat scheduler ---\n";
  H.setup pool;
  let start = Unix.gettimeofday () in
  let hb_result = T.run pool (fun _ -> 
    H.init_tokens 100;
    fib_heartbeat pool n
  ) in
  let hb_time = Unix.gettimeofday () -. start in
  Printf.printf "Heartbeat: %.4fs (result=%d)\n\n%!" hb_time hb_result;
  H.teardown ();
  
  (* Benchmark normal fib *)
  Printf.printf "--- Sequential fib ---\n";
  let start = Unix.gettimeofday () in
  let normal_result = fib n in
  let normal_time = Unix.gettimeofday () -. start in
  Printf.printf "Sequential: %.4fs (result=%d)\n\n%!" normal_time normal_result;

  (* Benchmark Task.async *)
  Printf.printf "--- Task.async (baseline) ---\n";
  let start = Unix.gettimeofday () in
  let async_result = T.run pool (fun _ -> fib_async pool n) in
  let async_time = Unix.gettimeofday () -. start in
  Printf.printf "Task.async: %.4fs (result=%d)\n\n%!" async_time async_result;
  
  T.teardown_pool pool;
  
  (* Summary *)
  Printf.printf "=== Summary ===\n";
  Printf.printf "Sequential:  %.4fs\n" normal_time;
  Printf.printf "Task.async:  %.4fs  (%.2fx vs sequential)\n" async_time (normal_time /. async_time);
  Printf.printf "Heartbeat:   %.4fs  (%.2fx vs sequential)\n" hb_time (normal_time /. hb_time);
  Printf.printf "Heartbeat vs Task.async speedup: %.2fx\n" (async_time /. hb_time)

let () = main
