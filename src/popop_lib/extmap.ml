(***********************************************************************)
(*                                                                     *)
(*                           Objective Caml                            *)
(*                                                                     *)
(*            Xavier Leroy, projet Cristal, INRIA Rocquencourt         *)
(*                                                                     *)
(*  Copyright 1996 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under the terms of the GNU Library General Public License, with    *)
(*  the special exception on linking described in file ../LICENSE.     *)
(*                                                                     *)
(***********************************************************************)

(* This file originates from the OCaml v 3.12 Standard Library.
   It was extended and modified for the needs of the Why3 project.
   It is distributed under the terms of its initial license, which
   is provided in the file OCAML-LICENSE. *)

module type S = sig
  include Map_intf.Map with type 'a data = 'a

  type 'a view =
    | Empty
    | Node of 'a view * key * 'a * 'a view * int

  val view: 'a t -> 'a view

end

module Make(Ord: Map_intf.OrderedType) = struct
  type key = Ord.t
  type 'a data = 'a
  type 'a t =
      Empty
    | Node of 'a t * key * 'a * 'a t * int

  type 'a view = 'a t =
    | Empty
    | Node of 'a view * key * 'a * 'a view * int

  let view x = x

  let height = function
      Empty -> 0
    | Node(_,_,_,_,h) -> h

  let create l x d r =
    let hl = height l and hr = height r in
    Node(l, x, d, r, (if hl >= hr then hl + 1 else hr + 1))

  let singleton x d = Node(Empty, x, d, Empty, 1)

  let bal l x d r =
    let hl = match l with Empty -> 0 | Node(_,_,_,_,h) -> h in
    let hr = match r with Empty -> 0 | Node(_,_,_,_,h) -> h in
    if hl > hr + 2 then begin
      match l with
        Empty -> invalid_arg "Map.bal"
      | Node(ll, lv, ld, lr, _) ->
        if height ll >= height lr then
          create ll lv ld (create lr x d r)
        else begin
          match lr with
            Empty -> invalid_arg "Map.bal"
          | Node(lrl, lrv, lrd, lrr, _)->
            create (create ll lv ld lrl) lrv lrd (create lrr x d r)
        end
    end else if hr > hl + 2 then begin
      match r with
        Empty -> invalid_arg "Map.bal"
      | Node(rl, rv, rd, rr, _) ->
        if height rr >= height rl then
          create (create l x d rl) rv rd rr
        else begin
          match rl with
            Empty -> invalid_arg "Map.bal"
          | Node(rll, rlv, rld, rlr, _) ->
            create (create l x d rll) rlv rld (create rlr rv rd rr)
        end
    end else
      Node(l, x, d, r, (if hl >= hr then hl + 1 else hr + 1))

  let empty = Empty

  let is_empty = function Empty -> true | _ -> false

  let rec add x data = function
      Empty ->
      Node(Empty, x, data, Empty, 1)
    | Node(l, v, d, r, h) ->
      let c = Ord.compare x v in
      if c = 0 then
        Node(l, x, data, r, h)
      else if c < 0 then
        bal (add x data l) v d r
      else
        bal l v d (add x data r)

  let rec find x = function
      Empty ->
      raise Not_found
    | Node(l, v, d, r, _) ->
      let c = Ord.compare x v in
      if c = 0 then d
      else find x (if c < 0 then l else r)

  let rec mem x = function
      Empty ->
      false
    | Node(l, v, _d, r, _) ->
      let c = Ord.compare x v in
      c = 0 || mem x (if c < 0 then l else r)

  let rec min_binding = function
      Empty -> raise Not_found
    | Node(Empty, x, d, _r, _) -> (x, d)
    | Node(l, _x, _d, _r, _) -> min_binding l

  let rec max_binding = function
      Empty -> raise Not_found
    | Node(_l, x, d, Empty, _) -> (x, d)
    | Node(_l, _x, _d, r, _) -> max_binding r

  let rec remove_min_binding = function
      Empty -> invalid_arg "Map.remove_min_elt"
    | Node(Empty, _x, _d, r, _) -> r
    | Node(l, x, d, r, _) -> bal (remove_min_binding l) x d r

  let merge t1 t2 =
    match (t1, t2) with
      (Empty, t) -> t
    | (t, Empty) -> t
    | (_, _) ->
      let (x, d) = min_binding t2 in
      bal t1 x d (remove_min_binding t2)

  let merge_bal = merge

  let rec remove x = function
      Empty ->
      Empty
    | Node(l, v, d, r, _h) ->
      let c = Ord.compare x v in
      if c = 0 then
        merge l r
      else if c < 0 then
        bal (remove x l) v d r
      else
        bal l v d (remove x r)

  let rec iter f = function
      Empty -> ()
    | Node(l, v, d, r, _) ->
      iter f l; f v d; iter f r

  let rec map f = function
      Empty ->
      Empty
    | Node(l, v, d, r, h) ->
      let l' = map f l in
      let d' = f d in
      let r' = map f r in
      Node(l', v, d', r', h)

  let rec mapi f = function
      Empty ->
      Empty
    | Node(l, v, d, r, h) ->
      let l' = mapi f l in
      let d' = f v d in
      let r' = mapi f r in
      Node(l', v, d', r', h)

  let rec fold f m accu =
    match m with
      Empty -> accu
    | Node(l, v, d, r, _) ->
      fold f r (f v d (fold f l accu))

  let rec for_all p = function
      Empty -> true
    | Node(l, v, d, r, _) -> p v d && for_all p l && for_all p r

  let rec exists p = function
      Empty -> false
    | Node(l, v, d, r, _) -> p v d || exists p l || exists p r

  let filter p s =
    let rec filt accu = function
      | Empty -> accu
      | Node(l, v, d, r, _) ->
        filt (filt (if p v d then add v d accu else accu) l) r in
    filt Empty s

  let partition p s =
    let rec part (t, f as accu) = function
      | Empty -> accu
      | Node(l, v, d, r, _) ->
        part (part (if p v d then (add v d t, f)
                    else (t, add v d f)) l) r in
    part (Empty, Empty) s

  (* Same as create and bal, but no assumptions are made on the
     relative heights of l and r. *)

  let rec join l v d r =
    match (l, r) with
      (Empty, _) -> add v d r
    | (_, Empty) -> add v d l
    | (Node(ll, lv, ld, lr, lh), Node(rl, rv, rd, rr, rh)) ->
      if lh > rh + 2 then bal ll lv ld (join lr v d r) else
      if rh > lh + 2 then bal (join l v d rl) rv rd rr else
        create l v d r

  (* Merge two trees l and r into one.
     All elements of l must precede the elements of r.
     No assumption on the heights of l and r. *)

  let concat t1 t2 =
    match (t1, t2) with
      (Empty, t) -> t
    | (t, Empty) -> t
    | (_, _) ->
      let (x, d) = min_binding t2 in
      join t1 x d (remove_min_binding t2)

  let concat_or_join t1 v d t2 =
    match d with
    | Some d -> join t1 v d t2
    | None -> concat t1 t2

  let rec split x = function
      Empty ->
      (Empty, None, Empty)
    | Node(l, v, d, r, _) ->
      let c = Ord.compare x v in
      if c = 0 then (l, Some d, r)
      else if c < 0 then
        let (ll, pres, rl) = split x l in (ll, pres, join rl v d r)
      else
        let (lr, pres, rr) = split x r in (join l v d lr, pres, rr)

  let rec merge f s1 s2 =
    match (s1, s2) with
      (Empty, Empty) -> Empty
    | (Node (l1, v1, d1, r1, h1), _) when h1 >= height s2 ->
      let (l2, d2, r2) = split v1 s2 in
      concat_or_join (merge f l1 l2) v1 (f v1 (Some d1) d2) (merge f r1 r2)
    | (_, Node (l2, v2, d2, r2, _h2)) ->
      let (l1, d1, r1) = split v2 s1 in
      concat_or_join (merge f l1 l2) v2 (f v2 d1 (Some d2)) (merge f r1 r2)
    | _ ->
      assert false

  type 'a enumeration = End | More of key * 'a * 'a t * 'a enumeration

  let rec cons_enum m e =
    match m with
      Empty -> e
    | Node(l, v, d, r, _) -> cons_enum l (More(v, d, r, e))

  let compare cmp m1 m2 =
    let rec compare_aux e1 e2 =
      match (e1, e2) with
        (End, End) -> 0
      | (End, _)  -> -1
      | (_, End) -> 1
      | (More(v1, d1, r1, e1), More(v2, d2, r2, e2)) ->
        let c = Ord.compare v1 v2 in
        if c <> 0 then c else
          let c = cmp d1 d2 in
          if c <> 0 then c else
            compare_aux (cons_enum r1 e1) (cons_enum r2 e2)
    in compare_aux (cons_enum m1 End) (cons_enum m2 End)

  let equal cmp m1 m2 =
    let rec equal_aux e1 e2 =
      match (e1, e2) with
        (End, End) -> true
      | (End, _)  -> false
      | (_, End) -> false
      | (More(v1, d1, r1, e1), More(v2, d2, r2, e2)) ->
        Ord.compare v1 v2 = 0 && cmp d1 d2 &&
        equal_aux (cons_enum r1 e1) (cons_enum r2 e2)
    in equal_aux (cons_enum m1 End) (cons_enum m2 End)


  let pp pp fmt m =
    Pp.iter2 iter Pp.arrow Pp.colon
      Ord.pp pp
      fmt m

  let rec cardinal = function
      Empty -> 0
    | Node(l, _, _, r, _) -> cardinal l + 1 + cardinal r

  let rec keys_aux accu = function
      Empty -> accu
    | Node(l, v, _, r, _) -> keys_aux (v :: keys_aux accu r) l

  let keys s =
    keys_aux [] s

  let rec bindings_aux accu = function
      Empty -> accu
    | Node(l, v, d, r, _) -> bindings_aux ((v, d) :: bindings_aux accu r) l

  let bindings s =
    bindings_aux [] s

  let rec values_aux accu = function
      Empty -> accu
    | Node(l, _, v, r, _) -> values_aux (v :: values_aux accu r) l

  let values s =
    values_aux [] s

  let choose = min_binding

  (** Added into why stdlib version *)

  let rec change f x = function
    | Empty ->
      begin match f None with
        | None -> Empty
        | Some d -> Node(Empty, x, d, Empty, 1)
      end
    | Node(l, v, d, r, h) ->
      let c = Ord.compare x v in
      if c = 0 then
        (* concat or bal *)
        match f (Some d) with
        | None -> merge_bal l r
        | Some d -> Node(l, x, d, r, h)
      else if c < 0 then
        bal (change f x l) v d r
      else
        bal l v d (change f x r)

  let rec add_change empty add x b = function
    | Empty -> Node(Empty, x, empty b, Empty, 1)
    | Node(l, v, d, r, h) ->
      let c = Ord.compare x v in
      if c = 0 then
        Node(l, x, add b d, r, h)
      else if c < 0 then
        bal (add_change empty add x b l) v d r
      else
        bal l v d (add_change empty add x b r)

  let rec union f s1 s2 =
    match (s1, s2) with
      (Empty, t2) -> t2
    | (t1, Empty) -> t1
    | (Node(l1, v1, d1, r1, h1), Node(l2, v2, d2, r2, h2)) ->
      if h1 >= h2 then
        if h2 = 1 then
          change (function None -> Some d2 | Some d1 -> f v2 d1 d2) v2 s1
        else begin
          let (l2, d2, r2) = split v1 s2 in
          match d2 with
          | None -> join (union f l1 l2) v1 d1 (union f r1 r2)
          | Some d2 ->
            concat_or_join (union f l1 l2) v1 (f v1 d1 d2)
              (union f r1 r2)
        end
      else
      if h1 = 1 then
        change (function None -> Some d1 | Some d2 -> f v1 d1 d2) v1 s2
      else begin
        let (l1, d1, r1) = split v2 s1 in
        match d1 with
        | None -> join (union f l1 l2) v2 d2 (union f r1 r2)
        | Some d1 ->
          concat_or_join (union f l1 l2) v2 (f v2 d1 d2)
            (union f r1 r2)
      end

  let rec union_merge f s1 s2 =
    match (s1, s2) with
      (Empty, Empty) -> Empty
    | (t1,Empty) -> t1
    | (Node (l1, v1, d1, r1, h1), _) when h1 >= height s2 ->
      let (l2, d2, r2) = split v1 s2 in
      begin match d2 with
        | None -> join (union_merge f l1 l2) v1 d1 (union_merge f r1 r2)
        | Some d2 ->
          concat_or_join (union_merge f l1 l2) v1 (f v1 (Some d1) d2)
            (union_merge f r1 r2)
      end
    | (_, Node (l2, v2, d2, r2, _h2)) ->
      let (l1, d1, r1) = split v2 s1 in
      concat_or_join (union_merge f l1 l2) v2 (f v2 d1 d2)
        (union_merge f r1 r2)

  let rec inter f s1 s2 =
    match (s1, s2) with
    | (Empty, _) | (_, Empty) -> Empty
    | (Node(l1, v1, d1, r1, _), t2) ->
      match split v1 t2 with
        (l2, None, r2) ->
        concat (inter f l1 l2) (inter f r1 r2)
      | (l2, Some d2, r2) ->
        concat_or_join (inter f l1 l2) v1 (f v1 d1 d2) (inter f r1 r2)


  let rec diff f s1 s2 =
    match (s1, s2) with
      (Empty, _t2) -> Empty
    | (t1, Empty) -> t1
    | (Node(l1, v1, d1, r1, _), t2) ->
      match split v1 t2 with
      | (l2, None, r2) -> join (diff f l1 l2) v1 d1 (diff f r1 r2)
      | (l2, Some d2, r2) ->
        concat_or_join (diff f l1 l2) v1 (f v1 d1 d2) (diff f r1 r2)


  let rec submap pr s1 s2 =
    match (s1, s2) with
    | Empty, _ -> true
    | _, Empty -> false
    | Node (l1, v1, d1, r1, _), (Node (l2, v2, d2, r2, _) as t2) ->
      let c = Ord.compare v1 v2 in
      if c = 0 then
        pr v1 d1 d2 && submap pr l1 l2 && submap pr r1 r2
      else if c < 0 then
        submap pr (Node (l1, v1, d1, Empty, 0)) l2 && submap pr r1 t2
      else
        submap pr (Node (Empty, v1, d1, r1, 0)) r2 && submap pr l1 t2


  let rec disjoint pr s1 s2 =
    match (s1, s2) with
    | Empty, _ -> true
    | _, Empty -> true
    | Node (l1, v1, d1, r1, _), (Node (l2, v2, d2, r2, _) as t2) ->
      let c = Ord.compare v1 v2 in
      if c = 0 then
        pr v1 d1 d2 && disjoint pr l1 l2 && disjoint pr r1 r2
      else if c < 0 then
        disjoint pr (Node (l1, v1, d1, Empty, 0)) l2 && disjoint pr r1 t2
      else
        disjoint pr (Node (Empty, v1, d1, r1, 0)) r2 && disjoint pr l1 t2

  let set_union m1 m2 = union (fun _ x _ -> Some x) m1 m2
  let set_inter m1 m2 = inter (fun _ x _ -> Some x) m1 m2
  let set_diff m1 m2 = diff (fun _ _ _ -> None) m1 m2
  let set_submap m1 m2 = submap (fun _ _ _ -> true) m1 m2
  let set_disjoint m1 m2 = disjoint (fun _ _ _ -> false) m1 m2
  let set_compare m1 m2 = compare (fun _ _ -> 0) m1 m2
  let set_equal m1 m2 = equal (fun _ _ -> true) m1 m2

  let rec find_def def x = function
      Empty -> def
    | Node(l, v, d, r, _) ->
      let c = Ord.compare x v in
      if c = 0 then d
      else find_def def x (if c < 0 then l else r)

  let rec find_opt x = function
      Empty -> None
    | Node(l, v, d, r, _) ->
      let c = Ord.compare x v in
      if c = 0 then Some d
      else find_opt x (if c < 0 then l else r)

  let rec find_exn exn x = function
      Empty -> raise exn
    | Node(l, v, d, r, _) ->
      let c = Ord.compare x v in
      if c = 0 then d
      else find_exn exn x (if c < 0 then l else r)

  let rec find_remove x = function
      Empty ->
      Empty, None
    | Node(l, v, d, r, _h) ->
      let c = Ord.compare x v in
      if c = 0 then
        merge_bal l r, Some d
      else if c < 0 then
        let l,f = find_remove x l in
        bal l v d r,f
      else
        let r,f = find_remove x r in
        bal l v d r,f

  let rec find_smaller_opt cand x = function
    | Empty -> cand
    | Node(l, v, d, r, _) ->
      let c = Ord.compare x v in
      if c = 0 then Some(x,d)
      else if c < 0 then
        find_smaller_opt cand x l
      else
        find_smaller_opt (Some(x,d)) x r

  let find_smaller_opt x t = find_smaller_opt None x t

  let rec map_filter f = function
      Empty -> Empty
    | Node(l, v, d, r, _h) ->
      concat_or_join (map_filter f l) v (f d) (map_filter f r)

  let rec mapi_filter f = function
      Empty -> Empty
    | Node(l, v, d, r, _h) ->
      concat_or_join (mapi_filter f l) v (f v d) (mapi_filter f r)

  let rec mapi_fold f m acc =
    match m with
      Empty -> acc, Empty
    | Node(l, v, d, r, h) ->
      let acc,l' = mapi_fold f l acc in
      let acc,d' = f v d acc in
      let acc,r' = mapi_fold f r acc in
      acc,Node(l', v, d', r', h)

  let fold2_inter f m1 m2 acc =
    let rec aux acc e1_0 e2_0 =
      match (e1_0, e2_0) with
        (End, End) -> acc
      | (End, _)  -> acc
      | (_, End) -> acc
      | (More(v1, d1, r1, e1), More(v2, d2, r2, e2)) ->
        let c = Ord.compare v1 v2 in
        if c = 0 then
          aux (f v1 d1 d2 acc) (cons_enum r1 e1) (cons_enum r2 e2)
        else if c < 0 then
          aux acc (cons_enum r1 e1) e2_0
        else
          aux acc e1_0 (cons_enum r2 e2)
    in aux acc (cons_enum m1 End) (cons_enum m2 End)

  let fold2_union f m1 m2 acc =
    let rec aux acc e1_0 e2_0 =
      match (e1_0, e2_0) with
        (End, End) -> acc
      | (End, More(v2, d2, r2, e2)) ->
        aux (f v2 None (Some d2) acc) End (cons_enum r2 e2)
      | (More(v1, d1, r1, e1), End) ->
        aux (f v1 (Some d1) None acc) (cons_enum r1 e1) End
      | (More(v1, d1, r1, e1), More(v2, d2, r2, e2)) ->
        let c = Ord.compare v1 v2 in
        if c = 0 then
          aux (f v1 (Some d1) (Some d2) acc)
            (cons_enum r1 e1) (cons_enum r2 e2)
        else if c < 0 then
          aux (f v1 (Some d1) None acc) (cons_enum r1 e1) e2_0
        else
          aux (f v2 None (Some d2) acc) e1_0 (cons_enum r2 e2)
    in aux acc (cons_enum m1 End) (cons_enum m2 End)

  let translate f m =
    let rec aux last = function
      | Empty -> Empty,last
      | Node(l, v, d, r, h) ->
        let l,last = aux last l in
        let v = f v in
        begin match last with
          | None -> ()
          | Some last ->
            if Ord.compare last v >= 0
            then invalid_arg "Map.translate : given function incorrect"
        end;
        let r,last = aux (Some v) r in
        Node(l,v,d,r,h),last in
    let m,_ = aux None m in m

  let rec mapi_filter_fold f m acc =
    match m with
      Empty -> acc, Empty
    | Node(l, v, d, r, _h) ->
      let acc,l' = mapi_filter_fold f l acc in
      let acc,d' = f v d acc in
      let acc,r' = mapi_filter_fold f r acc in
      acc, concat_or_join l' v d' r'

  let add_new e x v m = change (function
      | Some _ -> raise e
      | None -> Some v) x m

  let is_num_elt n m =
    try
      fold (fun _ _ n -> if n < 0 then raise Exit else n-1) m n = 0
    with Exit -> false

  (** the goal is to choose randomly but often the same than [choose] *)
  let choose_rnd f m =
    let rec aux f m ret =
      match m with
      | Empty -> ()
      | Node(l, v, d, r, _) ->
        aux f l ret;
        if f () then (ret := (v,d); raise Exit) else aux f r ret
    in
    let ret = ref (Obj.magic 0) in
    try
      aux f m ret;
      choose m
    with Exit -> !ret

  let start_enum s = cons_enum s End

  let val_enum = function
    | End -> None
    | More (v,d,_,_) -> Some (v,d)

  let next_enum = function
    | End -> End
    | More(_,_,r,e) -> cons_enum r e

  let rec cons_ge_enum k m e =
    match m with
      Empty -> e
    | Node(l, v, d, r, _) ->
      let c = Ord.compare k v in
      if c = 0 then More(v,d,r,e)
      else if c < 0 then cons_ge_enum k l (More(v, d, r, e))
      else (* c > 0 *) cons_ge_enum k r e

  let start_ge_enum k m = cons_ge_enum k m End

  let rec next_ge_enum k l0 = function
    | End -> start_ge_enum k l0
    | More(v,_,r,e) as e0 ->
      let c = Ord.compare k v in
      if c = 0 then e0
      else if c < 0 then cons_ge_enum k l0 e0
      else (* c > 0 *)    next_ge_enum k r  e

  let next_ge_enum k e = next_ge_enum k Empty e

  let rec fold_left f accu m =
    match m with
      Empty -> accu
    | Node(l, v, d, r, _) ->
      fold_left f (f (fold_left f accu l) v d) r

  let rec fold_decr f accu m =
    match m with
      Empty -> accu
    | Node(l, v, d, r, _) ->
      fold_decr f (f (fold_decr f accu r) v d) l

  let of_list l =
    List.fold_left (fun acc (k,d) -> add k d acc) empty l

  let add_opt x o m =
    match o with
    | None -> remove x m
    | Some y -> add x y m

  let check_invariant m =
    let rec aux = function
      | Empty -> 0, true
      | Node(l,_,_,r,h) ->
        let h1,b1 = aux l in
        let h2,b2 = aux r in
        if b1 && b2
        then
          let h' = (if h1 >= h2 then h1 + 1 else h2 + 1) in
          h', h' = h
        else -1,false in
    snd (aux m)

end
