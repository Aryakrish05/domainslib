let num_domains = try int_of_string Sys.argv.(1) with _ -> 4
let n = try int_of_string Sys.argv.(2) with _ -> 40

module T = Domainslib.Task

(* Sequential fibonacci *)
let rec fib n =
  if n < 2 then 1
  else fib (n-1) + fib (n-2)

(* Plain Task.async version *)
let rec fib_async pool n =
  if n <= 20 then fib n
  else
    let a_promise = T.async pool (fun () -> fib_async pool (n-1)) in
    let b = fib_async pool (n-2) in
    let a = T.await pool a_promise in
    a + b

let main =
  Printf.printf "=== Comparison: fib(%d) with %d domains ===\n\n" n num_domains;
  
  (* Benchmark Sequential *)
  Printf.printf "--- Sequential ---\n%!";
  let start = Unix.gettimeofday () in
  let seq_result = fib n in
  let seq_time = Unix.gettimeofday () -. start in
  Printf.printf "Sequential: %.4fs (result=%d)\n\n%!" seq_time seq_result;

  (* Benchmark Task.async *)
  Printf.printf "--- Task.async ---\n%!";
  let pool = T.setup_pool ~num_domains:(num_domains - 1) () in
  let start = Unix.gettimeofday () in
  let async_result = T.run pool (fun _ -> fib_async pool n) in
  let async_time = Unix.gettimeofday () -. start in
  Printf.printf "Task.async: %.4fs (result=%d)\n\n%!" async_time async_result;
  T.teardown_pool pool;
  
  (* Summary *)
  Printf.printf "=== Summary ===\n";
  Printf.printf "Sequential: %.4fs  (baseline)\n" seq_time;
  Printf.printf "Task.async: %.4fs  (%.2fx speedup)\n" async_time (seq_time /. async_time)

let () = main
