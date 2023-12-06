type level = FATAL | ERROR | WARNING | INFO | DEBUG

val verbosity : level ref

val level_encoding : level TzPervasives.Data_encoding.t

type t

(** Return a new logger with a unique identity defined by current executable name and an automatically appended number. *)
val logger : unit -> t

val fatal : t -> (unit -> string) -> unit

val error : t -> (unit -> string) -> unit

val warning : t -> (unit -> string) -> unit

val info : t -> (unit -> string) -> unit

val debug : t -> (unit -> string) -> unit
