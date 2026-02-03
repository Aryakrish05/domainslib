(*pending = 0, claimed=1 , promoted=2*)
type t={
  mutable queue_entries: Obj.t array;
  mutable queue_types: int array;
  mutable capacity: int;
  mutable head: int;
  mutable tail: int;
}
let default_capacity=16

let create ()={
  queue_entries=Array.make default_capacity (Obj.repr 0);
  queue_types=Array.make default_capacity 0;
  capacity=default_capacity;
  head=0;
  tail=0;
}

let grow q=
  let new_capacity=q.capacity*2 in
  let new_entries=Array.make new_capacity (Obj.repr 0) in
  let new_types=Array.make new_capacity 0 in
  for i=0 to q.tail-1 do
    new_entries.(i)<-q.queue_entries.(i);
    new_types.(i)<-q.queue_types.(i);
  done;
  q.queue_entries<-new_entries;
  q.queue_types<-new_types;
  q.capacity<-new_capacity

(*always added as a closure*)
let add entry q=
  if q.tail>=q.capacity then grow q;
  q.queue_entries.(q.tail)<-Obj.repr entry;
  q.tail<-(q.tail+1);
  q.tail-1

let take_opt q=
  if q.tail=q.head then None
  else
    (q.head<-(q.head+1);
    Some (q.head-1))

let unsafe_set_promoted idx promise q=
  q.queue_entries.(idx)<-Obj.repr promise;
  q.queue_types.(idx)<-2

let unsafe_set_claimed idx q=
  q.queue_types.(idx)<-1

let is_pending idx q=
  (q.queue_types.(idx)=0)

let is_promoted idx q=
  (q.queue_types.(idx)=2)  

let unsafe_get_closure idx q : (unit->'a)=
  let actual_type = q.queue_types.(idx) in
  if actual_type <> 0 then
    Printf.eprintf "ERROR: Expected type 0 (Pending) for task %d, got %d\n%!" idx actual_type;
  assert(q.queue_types.(idx)=0);
  Obj.magic q.queue_entries.(idx)

let unsafe_get_promise idx q : ('a*int) Task.promise =
  let actual_type = q.queue_types.(idx) in
  if actual_type <> 2 then
    Printf.eprintf "ERROR: Expected type 2 for task %d, got %d\n%!" idx actual_type;
  assert(q.queue_types.(idx)=2);
  Obj.magic q.queue_entries.(idx)