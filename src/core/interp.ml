(*************************************************************************)
(*  This file is part of Witan.                                          *)
(*                                                                       *)
(*  Copyright (C) 2017                                                   *)
(*    CEA   (Commissariat à l'énergie atomique et aux énergies           *)
(*           alternatives)                                               *)
(*    INRIA (Institut National de Recherche en Informatique et en        *)
(*           Automatique)                                                *)
(*    CNRS  (Centre national de la recherche scientifique)               *)
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

open Witan_popop_lib
open Std
    
module Register = struct

  let ids : (Term.id -> Nodes.Value.t list -> Nodes.Value.t option) list ref = ref []
  let id f = ids := f::!ids

  module ThInterp = Nodes.ThTermKind.MkVector(struct
      type ('a,_) t = (interp:(Nodes.Node.t -> Nodes.Value.t) -> 'a -> Nodes.Value.t)
    end)

  let thterms = ThInterp.create 10
  let thterm sem f =
    if not (ThInterp.is_uninitialized thterms sem)
    then invalid_arg (Format.asprintf "Interpretation for semantic value %a already done" Nodes.ThTermKind.pp sem);
    ThInterp.set thterms sem f

  let models = Ty.H.create 16
  let model ty (f:Egraph.t -> Nodes.Node.t -> Nodes.Value.t) =
    Ty.H.add models ty f

end

exception NoInterpretation of Term.id
exception CantInterpretTerm of Term.t
exception CantInterpretThTerm of Nodes.ThTerm.t

type leaf = Term.t -> Nodes.Value.t option

(** No cache currently because there is no guaranty
    that the variable in the let is unique *)
let term ?(leaf=(fun _ -> None)) t =
  let rec interp leaf t =
    match leaf t with
    | Some v -> v
    | None ->
      let rec aux leaf args = function
        | { Term.term = App (f, arg); _ } ->
          aux leaf ((interp leaf arg) :: args) f
        | { Term.term = Let (v,e,t); _ } ->
          let v' = interp leaf e in
          let leaf t = match t.Term.term with
            | Id id when Term.Id.equal v id -> Some v'
            | _ -> leaf t in
          aux leaf args t
        | { Term.term = Id id; _ } ->
          let rec find = function
            | [] -> raise (NoInterpretation id)
            | f::l ->
              match f id args with
              | None -> find l
              | Some v -> v
          in
          find !Register.ids
        | t -> raise (CantInterpretTerm t)
      in
      aux leaf [] t
  in
  interp leaf t

let rec node ?(leaf=(fun _ -> None)) n =
  match Nodes.Only_for_solver.open_node n with
  | Nodes.Only_for_solver.ThTerm t -> thterm ~leaf t
  | Nodes.Only_for_solver.Value v -> v

and thterm  ?(leaf=(fun _ -> None)) t =
  match Nodes.Only_for_solver.sem_of_node t with
  | Nodes.Only_for_solver.ThTerm (sem,v) ->
    (** check if it is not a synterm *)
    match Nodes.ThTermKind.Eq.eq_type sem SynTerm.key with
    | Poly.Eq  -> term ~leaf (v:Term.t)
    | Poly.Neq ->
      if Register.ThInterp.is_uninitialized Register.thterms sem
      then raise (CantInterpretThTerm t);
      (Register.ThInterp.get Register.thterms sem) ~interp:(node ~leaf) v

let model d n =
  match Ty.H.find_opt Register.models (Nodes.Node.ty n) with
  | None -> invalid_arg "Uninterpreted type"
  | Some f -> f d n

let () = Exn_printer.register (fun fmt exn ->
    match exn with
    | NoInterpretation id ->
      Format.fprintf fmt "Can't interpret the id %a."
        Term.Id.pp id
    | CantInterpretTerm t ->
      Format.fprintf fmt "Can't interpret the term %a."
        Term.pp t
    | CantInterpretThTerm th ->
      Format.fprintf fmt "Can't interpret the thterm %a."
        Nodes.ThTerm.pp th
    | exn -> raise exn
  )
