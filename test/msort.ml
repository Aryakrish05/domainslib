let array_size = try int_of_string Sys.argv.(1) with _ -> 10000

(* Sequential merge sort *)
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

let rec merge_sort arr tmp left right =
  if left < right then begin
    let mid = left + (right - left) / 2 in
    merge_sort arr tmp left mid;
    merge_sort arr tmp (mid + 1) right;
    merge arr tmp left mid right
  end

let sort arr =
  let tmp = Array.copy arr in
  if Array.length arr > 0 then
    merge_sort arr tmp 0 (Array.length arr - 1)

let main =
  (* Create input array *)
  let input = Array.init array_size (fun i -> array_size - i) in
  Printf.printf "Starting sequential merge sort with array_size=%d\n%!" array_size;
  
  sort input;
  
  (* Verify it's sorted *)
  let is_sorted = ref true in
  for i = 0 to Array.length input - 2 do
    if input.(i) > input.(i+1) then is_sorted := false
  done;
  Printf.printf "Sorted correctly: %b\n%!" !is_sorted

let () = main
