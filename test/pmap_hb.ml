let work_fn = try Sys.argv.(1) with _ -> "fib"
let num_domains = try int_of_string Sys.argv.(2) with _ -> 4
let array_size = try int_of_string Sys.argv.(3) with _ -> 10000
let cutoff = try int_of_string Sys.argv.(4) with _ -> 10

module T = Domainslib.Task
module H = Domainslib.Heartbeat

(* Work functions *)
let rec fib n =
  if n < 2 then 1
  else fib (n-1) + fib (n-2)

let is_prime n =
  if n < 2 then 0
  else if n = 2 then 1
  else if n mod 2 = 0 then 0
  else
    let rec check d =
      if d * d > n then 1
      else if n mod d = 0 then 0
      else check (d + 2)
    in
    check 3

let poly n =
  let x = float_of_int n in
  int_of_float (x *. x *. x +. 2.0 *. x *. x -. 5.0 *. x +. 3.0)

let trig n =
  let x = float_of_int n /. 100.0 in
  int_of_float (sin x *. cos x *. tan x *. 1000.0)

let hash_work n =
  let rec loop i acc =
    if i = 0 then acc
    else loop (i - 1) ((acc * 31 + i) land 0x7FFFFFFF)
  in
  loop (n * 100) n

let get_work_fn name =
  match name with
  | "fib" -> fib
  | "prime" -> is_prime
  | "poly" -> poly
  | "trig" -> trig
  | "hash" -> hash_work
  | _ -> failwith ("Unknown work function: " ^ name)

(* Parallel map using heartbeat fork2join *)
let rec parallel_map_range pool cutoff f arr start finish result =
  if finish - start <= cutoff then begin
    (* Base case: sequential *)
    for i = start to finish do
      result.(i) <- f arr.(i)
    done
  end else begin
    let mid = start + (finish - start) / 2 in
    let ((), ()) = H.fork2join pool
      (fun () -> parallel_map_range pool cutoff f arr start mid result)
      (fun () -> parallel_map_range pool cutoff f arr (mid + 1) finish result)
    in
    ()
  end

let parallel_map pool cutoff f arr =
  let result = Array.copy arr in
  if Array.length arr > 0 then
    parallel_map_range pool cutoff f arr 0 (Array.length arr - 1) result;
  result

let main =
  let work = get_work_fn work_fn in
  let pool = T.setup_pool ~num_domains:(num_domains - 1) () in
  H.setup pool;
  (* Create input array with values to compute on *)
  let input = Array.init array_size (fun i -> 10 + (i mod 10)) in
  Printf.printf "Starting heartbeat parallel map with work=%s num_domains=%d array_size=%d cutoff=%d\n%!" work_fn num_domains array_size cutoff;
  
  let result = T.run pool (fun _ -> 
    let res = parallel_map pool cutoff work input in
    H.teardown ();
    res
  ) in
  
  Printf.printf "Sum of results: %d\n%!" (Array.fold_left (+) 0 result);
  T.teardown_pool pool

let () = main
