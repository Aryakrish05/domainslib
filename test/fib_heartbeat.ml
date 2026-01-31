let num_domains = try int_of_string Sys.argv.(1) with _ -> 1
let n = try int_of_string Sys.argv.(2) with _ -> 43

module T = Domainslib.Task
module H = Domainslib.Heartbeat

let rec fib n =
  if n < 2 then 1
  else fib (n-1) + fib (n-2)

let rec fib_heartbeat pool n =
  if n <= 5 then fib n  (* Sequential cutoff to avoid stack overflow *)
  else
    let (a, b) = H.fork2join pool 
      (fun () -> fib_heartbeat pool (n-1))
      (fun () -> fib_heartbeat pool (n-2)) in
    a + b

let main =
  let pool = T.setup_pool ~num_domains:(num_domains - 1) () in
  H.setup pool;
  let res = T.run pool (fun _ -> 
    H.init_tokens 100;
    fib_heartbeat pool n
  ) in
  H.teardown ();
  T.teardown_pool pool;
  Printf.printf "fib_heartbeat(%d) = %d\n" n res

let () = main
