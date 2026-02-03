val setup : Task.pool -> unit
val teardown : unit -> unit
val fork2join : Task.pool -> (unit -> 'a) -> (unit -> 'b) -> 'a * 'b
val init_tokens : int -> unit
