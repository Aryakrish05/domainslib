(* Task states inferred from Obj.tag: pending=closure_tag, promoted=non-closure *)
type t={
  mutable queue_entries: Obj.t array;
  mutable capacity: int;
  mutable head: int;
  mutable tail: int;
}
let default_capacity=16

(*let max_capacity=1_00_000*)
let create ()={
  queue_entries=Array.make default_capacity (Obj.repr 0); 
  capacity=default_capacity;
  head=0;
  tail=0;
}

let resize q new_capacity=
  let new_entries=Array.make new_capacity (Obj.repr 0) in
  for i=0 to q.tail-1 do
    new_entries.(i)<-q.queue_entries.(i);
  done;
  q.queue_entries<-new_entries;
  q.capacity<-new_capacity

(*always added as a closure*)
let add entry q=
  if q.tail>=q.capacity then resize q (2*q.capacity);
  q.queue_entries.(q.tail)<-Obj.repr entry;
  q.tail<-(q.tail+1);
  q.tail-1

let pop_back q=
  if q.tail <= q.head then
    failwith "Cannot pop_back from empty queue";
  q.tail<-q.tail-1;
  if(2*q.tail<q.capacity && q.capacity > default_capacity) then 
    resize q (max default_capacity ((q.capacity+1)/2))
let take_opt q=
  if q.tail=q.head then None
  else
    (q.head<-(q.head+1);
    Some (q.head-1))

let unsafe_set_promoted idx promise q=
  q.queue_entries.(idx)<-Obj.repr promise

(*it is assumed that the tag of promise is not the same*)
let is_promoted idx q =
  let tag = Obj.tag q.queue_entries.(idx) in
  tag <> Obj.closure_tag
let is_pending idx q =
  let tag = Obj.tag q.queue_entries.(idx) in
  tag = Obj.closure_tag
let unsafe_get_closure idx q : (unit->'a)=
  let tag = Obj.tag q.queue_entries.(idx) in
  if tag <> Obj.closure_tag then
    failwith "ERROR: Expected closure tag for pending task";
  Obj.magic q.queue_entries.(idx)

let unsafe_get_promise idx q : ('a*int) Task.promise =
  let tag = Obj.tag q.queue_entries.(idx) in
  if tag = Obj.closure_tag then
    failwith "ERROR: Expected promoted task (non-closure), but found closure";
  Obj.magic q.queue_entries.(idx)