let num_domains = try int_of_string Sys.argv.(1) with _ -> 4
let array_size = try int_of_string Sys.argv.(2) with _ -> 10000
let cutoff = try int_of_string Sys.argv.(3) with _ -> 1000

module T = Domainslib.Task
module H = Domainslib.Heartbeat

(* Sequential merge *)
let merge arr tmp left mid right =
  let i = ref left in
  let j = ref (mid + 1) in
  let k = ref left in
  
  while !i <= mid && !j <= right do
    if arr.(!i) <= arr.(!j) then begin
      tmp.(!k) <- arr.(!i);
      incr i
    end else begin
      tmp.(!k) <- arr.(!j);
      incr j
    end;
    incr k
  done;
  
  while !i <= mid do
    tmp.(!k) <- arr.(!i);
    incr i; incr k
  done;
  
  while !j <= right do
    tmp.(!k) <- arr.(!j);
    incr j; incr k
  done;
  
  for idx = left to right do
    arr.(idx) <- tmp.(idx)
  done

(* Parallel merge sort using heartbeat fork2join *)
let rec merge_sort pool cutoff arr tmp left right =
  if left < right then begin
    let size = right - left + 1 in
    if size <= cutoff then begin
      (* Sequential for small arrays *)
      let rec seq_sort l r =
        if l < r then begin
          let mid = l + (r - l) / 2 in
          seq_sort l mid;
          seq_sort (mid + 1) r;
          merge arr tmp l mid r
        end
      in
      seq_sort left right
    end else begin
      (* Parallel for large arrays *)
      let mid = left + (right - left) / 2 in
      let ((), ()) = H.fork2join pool
        (fun () -> merge_sort pool cutoff arr tmp left mid)
        (fun () -> merge_sort pool cutoff arr tmp (mid + 1) right)
      in
      merge arr tmp left mid right
    end
  end

let sort pool cutoff arr =
  let tmp = Array.copy arr in
  if Array.length arr > 0 then
    merge_sort pool cutoff arr tmp 0 (Array.length arr - 1)

let main =
  let pool = T.setup_pool ~num_domains:(num_domains - 1) () in
  H.setup pool;
  (* Create input array *)
  let input = Array.init array_size (fun i -> array_size - i) in
  Printf.printf "Starting heartbeat merge sort with num_domains=%d array_size=%d cutoff=%d\n%!" num_domains array_size cutoff;
  
  let result = T.run pool (fun _ -> 
    sort pool cutoff input;
    H.teardown ();
    input
  ) in
  
  (* Verify it's sorted *)
  let is_sorted = ref true in
  for i = 0 to Array.length result - 2 do
    if result.(i) > result.(i+1) then is_sorted := false
  done;
  Printf.printf "Sorted correctly: %b\n%!" !is_sorted;
  T.teardown_pool pool

let () = main
