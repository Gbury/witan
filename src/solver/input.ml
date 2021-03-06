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

(* The Dolmen library is used to parse input languages *)
(* ************************************************************************ *)

exception File_not_found of string
(** Raised when file is not found. *)

(** See documentation at
    {{:http://gbury.github.io/dolmen/dev/Logic.Make.html} Logic.Make} *)
module P = Dolmen.Logic.Make
    (Dolmen.ParseLocation)
    (Dolmen.Id)
    (Dolmen.Term)
    (Dolmen.Statement)

(* Some re-export of definitions *)
type language = P.language =
  | Dimacs
  | ICNF
  | Smtlib
  | Tptp
  | Zf

let enum = P.enum

(** Convenience function to expand includes *)
let read_aux ~language ~dir input =
  let acc = ref [input] in
  let rec aux () =
    match !acc with
    | [] -> None
    | g :: r ->
      begin match g () with
        | None -> acc := r; aux ()
        | Some { Dolmen.Statement.descr = Dolmen.Statement.Include f; _ } ->
          let file = match P.find ~language ~dir f with
            | None -> raise (File_not_found f)
            | Some f -> f
          in
          let _, g', _ = P.parse_input ~language (`File file) in
          acc := g' :: !acc;
          aux ()
        | (Some _) as res -> res
      end
  in
  aux

let read ?language ~dir f =
  (** Formats Dimacs and Tptp are descriptive and lack the emission
      of formal solve/prove instructions, so we need to add them. *)
  let s = Dolmen.Statement.include_ f [] in
  (* Auto-detect input format *)
  let language =
    match language with
    | Some l -> l
    | None -> let res, _, _ = P.of_filename f in res
  in
  let g =
    match language with
    | P.Zf
    | P.ICNF
    | P.Smtlib -> Gen.singleton s
    | P.Dimacs
    | P.Tptp -> Gen.of_list [s; Dolmen.Statement.prove ()]
  in
  read_aux ~language ~dir g

