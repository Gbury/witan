(*************************************************************************)
(*  This file is part of Witan.                                          *)
(*                                                                       *)
(*  Copyright (C) 2017                                                   *)
(*    CEA   (Commissariat à l'énergie atomique et aux énergies           *)
(*           alternatives)                                               *)
(*    INRIA (Institut National de Recherche en Informatique et en        *)
(*           Automatique)                                                *)
(*                                                                       *)
(*  you can redistribute it and/or modify it under the terms of the GNU  *)
(*  Lesser General Public License as published by the Free Software      *)
(*  Foundation, version 2.1.                                             *)
(*                                                                       *)
(*  It is distributed in the hope that it will be useful,                *)
(*  but WITHOUT ANY WARRANTY; without even the implied warranty of       *)
(*  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the        *)
(*  GNU Lesser General Public License for more details.                  *)
(*                                                                       *)
(*  See the GNU Lesser General Public License version 2.1                *)
(*  for more details (enclosed in the file licenses/LGPLv2.1).           *)
(*************************************************************************)

(** Solver is the main module of core *)

(** The solver contains all the information. It keeps track of
    equivalence classes, values. It take care to schedule event that
    happened. *)

open Explanation
open Typedef

exception NotRegistered

type exp_same_sem =
| ExpSameSem   : pexp * Node.t * NodeSem.t -> exp_same_sem
| ExpSameValue : pexp * Node.t * NodeValue.t -> exp_same_sem

val exp_same_sem : exp_same_sem Explanation.exp

exception UninitializedEnv of Env.K.t

module type Getter = sig
  type t

  val is_equal      : t -> Node.t -> Node.t -> bool
  val find_def  : t -> Node.t -> Node.t
  val get_dom   : t -> 'a Dom.t -> Node.t -> 'a option
    (** dom of the class *)
  val get_value   : t -> 'a value -> Node.t -> 'a option
    (** value of the class *)

  (** {4 The classes must have been registered} *)

  val find      : t -> Node.t -> Node.t
  val is_repr      : t -> Node.t -> bool

  val is_registered : t -> Node.t -> bool

  val get_env : t -> 'a Env.t -> 'a
  val set_env: t -> 'a Env.t -> 'a -> unit

end

module type Ro = sig
  include Getter

  val register : t -> Node.t -> unit
  (** Add a new class to register *)

  val is_current_env: t -> bool

end

module Ro : Ro

module Delayed : sig
  type t = private Ro.t
  include Ro with type t := t

  (** {3 Immediate modifications} *)
  val set_dom  : t -> pexp -> 'a Dom.t -> Node.t -> 'a -> unit
    (** change the dom of the equivalence class *)

  val set_sem  : t -> Explanation.pexp -> Node.t -> NodeSem.t -> unit
  (** attach a sem to an equivalence class *)

  val set_clvalue: t -> Explanation.pexp -> Node.t -> NodeValue.t -> unit
  (** attach value to an equivalence class *)

  val set_value: t -> Explanation.pexp -> 'a value -> Node.t -> 'a -> unit
  (** attach value to an equivalence class *)

  val set_dom_premerge  : t -> 'a Dom.t -> Node.t -> 'a -> unit
    (** [set_dom_premerge d node] must be used only during the merge of two class
        [cl1] and [cl2], with one of them being [node].
        The explication is the explication given for the merge
    *)

  val unset_dom  : t -> pexp -> 'a Dom.t -> Node.t -> unit
  (** remove the dom of the equivalence class *)

  (** {3 Delayed modifications} *)
  val merge    : t -> Explanation.pexp -> Node.t -> Node.t -> unit

  (** {3 Attach Event} *)
  val attach_dom: t -> Node.t -> 'a Dom.t -> ('event,'r) dem -> 'event -> unit
    (** wakeup when the dom change *)
  val attach_value: t -> Node.t -> 'a value -> ('event,'r) dem -> 'event -> unit
    (** wakeup when a value is attached to this equivalence class *)
  val attach_reg_cl: t -> Node.t -> ('event,'r) dem -> 'event -> unit
    (** wakeup when this node is registered *)
  val attach_reg_sem: t -> 'a sem -> ('event,'r) dem -> 'event -> unit
    (** wakeup when a new semantical class is registered *)
  val attach_cl: t -> Node.t -> ('event,'r) dem -> 'event -> unit
    (** wakeup when it is not anymore the representative class *)

  (** other event can be added *)

  val register_decision: t -> Explanation.chogen -> unit
  (** register a decision that would be scheduled later. The
      [make_decision] of the [Cho] will be called at that time to know
      if the decision is still needed. *)
  val mk_pexp: t -> ?age:age -> ?tags:tags -> 'a exp -> 'a -> Explanation.pexp
  val current_age: t -> age
  val contradiction: t -> Explanation.pexp -> 'b

  val flush: t -> unit
(** Apply all the modifications and direct consequences.
    Should be used only during wakeup of not immediate daemon
*)
end

type d = Delayed.t

module Wait : Events.Wait.S with type delayed = Delayed.t and type delayed_ro = Ro.t

(** {2 Domains and Semantic Values key creation} *)

module type Dom = Dom.Dom_partial with type delayed := Delayed.t and type pexp := Explanation.pexp

module RegisterDom (D:Dom) : sig end

(** {2 External use of the solver} *)
include Getter

val new_t    : unit -> t

val new_delayed :
  sched_daemon:(Events.Wait.daemon_key -> unit) ->
  sched_decision:(chogen -> unit) ->
  t -> Delayed.t
(** The solver shouldn't be used anymore before
    calling flush. (flushd doesn't count)
*)

exception Contradiction of Explanation.pexp

val run_daemon: Delayed.t -> Events.Wait.daemon_key -> unit
(** schedule the run of a deamon *)

val delayed_stop: Delayed.t -> unit
(** Apply all the modifications and direct consequences.
    The argument shouldn't be used anymore *)

val flush: Delayed.t -> unit
(** Apply all the modifications and direct consequences.
    The argument can be used after that *)


(*
val make_decisions : Delayed.t -> attached_daemons -> unit
*)

val get_trail : t -> Explanation.t
val new_dec : t -> Explanation.dec
val current_age : t -> Explanation.Age.t
val current_nbdec : t -> int

(** {2 Implementation Specifics } *)
(** Because this module is implemented with persistent datastructure *)

val new_handle: t -> t
(** Modification in one of the environnement doesn't modify the other *)

(** Debug *)
val draw_graph: ?force:bool -> t -> unit
val output_graph : string -> t -> unit

val check_initialization: unit -> bool
(** Check if the initialization of all the dom, sem and dem have been done *)

val print_dom: 'a Dom.t -> 'a Pp.pp
val print_dom_opt: 'a Dom.t -> 'a option Pp.pp
