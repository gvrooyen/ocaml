(* TEST
 flags = "-dlambda";
 expect;
*)

(* The original example of unsoundness in #7421. *)
type t = {a: bool; mutable b: int option}

let f x =
  match x with
  | {a = false; b = _} -> 0
  | {a = _;     b = None} -> 1
  | {a = _;     b = _} when (x.b <- None; false) -> 2
  | {a = true;  b = Some y} -> y
;;
(* Correctness condition: there should either be a single
   (field_mut 1) access, or the second access should include
   a Match_failure case.

   PASS: the second access includes a Match_failure case. *)
[%%expect {|
0
type t = { a : bool; mutable b : int option; }
(let
  (f/280 =
     (function x/282 : int
       (if (field_int 0 x/282)
         (let (*match*/286 =o (field_mut 1 x/282))
           (if *match*/286
             (if (seq (setfield_ptr 1 x/282 0) 0) 2
               (let (*match*/287 =o (field_mut 1 x/282))
                 (if *match*/287 (field_imm 0 *match*/287)
                   (raise
                     (makeblock 0 (global Match_failure/20!) [0: "" 4 2])))))
             1))
         0)))
  (apply (field_mut 1 (global Toploop!)) "f" f/280))
val f : t -> int = <fun>
|}]



(* A simple example of a complete switch
   inside a mutable position. *)
type t = {a: bool; mutable b: int option}

let simple x =
  match x with
  | {b = None} -> 1
  | {b = Some y} -> y
;;
(* Performance expectation: there should not be a Match_failure case. *)
[%%expect {|
0
type t = { a : bool; mutable b : int option; }
(let
  (simple/291 =
     (function x/293 : int
       (let (*match*/296 =o (field_mut 1 x/293))
         (if *match*/296 (field_imm 0 *match*/296) 1))))
  (apply (field_mut 1 (global Toploop!)) "simple" simple/291))
val simple : t -> int = <fun>
|}]

(* This more complex case has the switch on [b] split across two cases
   on [a], so it may need a [Match_failure] for soundness -- it does
   if the two accesses to [b] are done on different reads of the same
   mutable field.

   PASS: a single read of [field_mut 1 x], no Match_failure case. *)
let f x =
  match x with
  | {a = false; b = _} -> 0
  | {a = _;     b = None} -> 1
  | {a = true;  b = Some y} -> y
;;
[%%expect {|
(let
  (f/297 =
     (function x/298 : int
       (if (field_int 0 x/298)
         (let (*match*/302 =o (field_mut 1 x/298))
           (if *match*/302 (field_imm 0 *match*/302) 1))
         0)))
  (apply (field_mut 1 (global Toploop!)) "f" f/297))
val f : t -> int = <fun>
|}]



(* A variant of the #7421 example. *)
let f r =
  match Some r with
  | Some { contents = None } -> 0
  | _ when (r := None; false) -> 1
  | Some { contents = Some n } -> n
  | None -> 3
;;
(* Correctness condition: there should either be a single
   (field_mut 0) access, or the second access should include
   a Match_failure case.

   FAIL: the second occurrence of (field_mut 0) is used with a direct
   (field_imm 0) access without a constructor check. The compiler is
   unsound here. *)
[%%expect {|
(let
  (f/304 =
     (function r/305 : int
       (let (*match*/307 = (makeblock 0 r/305))
         (catch
           (if *match*/307
             (let (*match*/309 =o (field_mut 0 (field_imm 0 *match*/307)))
               (if *match*/309 (exit 13) 0))
             (exit 13))
          with (13)
           (if (seq (setfield_ptr 0 r/305 0) 0) 1
             (if *match*/307
               (let (*match*/311 =o (field_mut 0 (field_imm 0 *match*/307)))
                 (field_imm 0 *match*/311))
               3))))))
  (apply (field_mut 1 (global Toploop!)) "f" f/304))
val f : int option ref -> int = <fun>
|}]



(* This example has an ill-typed counter-example: the type-checker
   finds it Total, but the pattern-matching compiler cannot see that
   (Some (Some (Bool b))) cannot occur. *)
type _ t = Int : int -> int t | Bool : bool -> bool t

let test = function
  | None -> 0
  | Some (Int n) -> n
;;
(* Performance expectation: there should not be a Match_failure case. *)
[%%expect {|
0
type _ t = Int : int -> int t | Bool : bool -> bool t
(let
  (test/315 =
     (function param/318 : int
       (if param/318 (field_imm 0 (field_imm 0 param/318)) 0)))
  (apply (field_mut 1 (global Toploop!)) "test" test/315))
val test : int t option -> int = <fun>
|}]


(* This example has an ill-typed counter-example, inside
   a mutable position.  *)
type _ t = Int : int -> int t | Bool : bool -> bool t

let test = function
  | { contents = None } -> 0
  | { contents = Some (Int n) } -> n
;;
(* Performance expectation: there should not be a Match_failure case. *)
[%%expect {|
0
type _ t = Int : int -> int t | Bool : bool -> bool t
(let
  (test/323 =
     (function param/325 : int
       (let (*match*/326 =o (field_mut 0 param/325))
         (if *match*/326 (field_imm 0 (field_imm 0 *match*/326)) 0))))
  (apply (field_mut 1 (global Toploop!)) "test" test/323))
val test : int t option ref -> int = <fun>
|}]



(* This example has a ill-typed counter-example,
   and also mutable sub-patterns, but in different places. *)
type _ t = Int : int -> int t | Bool : bool -> bool t

let test n =
  match Some (ref true, Int 42) with
  | Some ({ contents = true }, Int n) -> n
  | Some ({ contents = false }, Int n) -> -n
  | None -> 3
;;
(* Performance expectation: there should not be a Match_failure case. *)
[%%expect {|
0
type _ t = Int : int -> int t | Bool : bool -> bool t
(let
  (test/331 =
     (function n/332 : int
       (let
         (*match*/335 =
            (makeblock 0 (makeblock 0 (makemutable 0 (int) 1) [0: 42])))
         (if *match*/335
           (let
             (*match*/336 =a (field_imm 0 *match*/335)
              *match*/338 =o (field_mut 0 (field_imm 0 *match*/336)))
             (if *match*/338 (field_imm 0 (field_imm 1 *match*/336))
               (~ (field_imm 0 (field_imm 1 *match*/336)))))
           3))))
  (apply (field_mut 1 (global Toploop!)) "test" test/331))
val test : 'a -> int = <fun>
|}]



(* In this example, the constructor on which unsound assumptions could
   be made is not located directly below a mutable constructor, but
   one level deeper inside an immutable pair constructor (below the
   mutable constructor). This checks that there is a form of
   "transitive" propagation of mutability.

   Correctness condition: either there is a single mutable field read,
   or the accesses below the second mutable read have a Match_failure
   case.
*)
let deep r =
  match Some r with
  | Some { contents = ((), None) } -> 0
  | _ when (r := ((), None); false) -> 1
  | Some { contents = ((), Some n) } -> n
  | None -> 3
;;
(* FAIL: two different reads (field_mut 0), but no Match_failure case. *)
[%%expect {|
(let
  (deep/341 =
     (function r/343 : int
       (let (*match*/345 = (makeblock 0 r/343))
         (catch
           (if *match*/345
             (let (*match*/347 =o (field_mut 0 (field_imm 0 *match*/345)))
               (if (field_imm 1 *match*/347) (exit 21) 0))
             (exit 21))
          with (21)
           (if (seq (setfield_ptr 0 r/343 [0: 0 0]) 0) 1
             (if *match*/345
               (let (*match*/351 =o (field_mut 0 (field_imm 0 *match*/345)))
                 (field_imm 0 (field_imm 1 *match*/351)))
               3))))))
  (apply (field_mut 1 (global Toploop!)) "deep" deep/341))
val deep : (unit * int option) ref -> int = <fun>
|}]


(* In this example:
   - the pattern-matching is total, with subtle GADT usage
     (only the type-checker can tell that it is Total)
   - there are no mutable fields

   Performance expectation: there should not be a Match_failure clause.

   This example is a reduction of a regression caused by #13076 on the
   'CamlinternalFormat.trans' function in the standard library.
*)
type _ t = Bool : bool t | Int : int t | Char : char t;;
let test : type a . a t * a t -> unit = function
  | Int, Int -> ()
  | Bool, Bool -> ()
  | _, Char -> ()
;;
(* FAIL: currently a Match_failure clause is generated. *)
[%%expect {|
0
type _ t = Bool : bool t | Int : int t | Char : char t
(let
  (test/358 =
     (function param/360 : int
       (catch
         (catch
           (switch* (field_imm 0 param/360)
            case int 0:
             (switch* (field_imm 1 param/360)
              case int 0: 0
              case int 1: (exit 23)
              case int 2: (exit 24))
            case int 1:
             (switch* (field_imm 1 param/360)
              case int 0: (exit 23)
              case int 1: 0
              case int 2: (exit 24))
            case int 2: (exit 24))
          with (24) 0)
        with (23)
         (raise (makeblock 0 (global Match_failure/20!) [0: "" 2 40])))))
  (apply (field_mut 1 (global Toploop!)) "test" test/358))
val test : 'a t * 'a t -> unit = <fun>
|}];;

(* Another regression testcase from #13076, proposed by Nick Roberts.

   Performance expectation: no Match_failure clause.
*)
type nothing = |
type t = A | B | C of nothing
let f : bool * t -> int = function
  | true, A -> 3
  | false, A -> 4
  | _, B -> 5
  | _, C _ -> .
(* FAIL: a Match_failure clause is generated. *)
[%%expect {|
0
type nothing = |
0
type t = A | B | C of nothing
(let
  (f/370 =
     (function param/371 : int
       (catch
         (catch
           (if (field_imm 0 param/371)
             (let (*match*/373 =a (field_imm 1 param/371))
               (if (isint *match*/373) (if *match*/373 (exit 26) 3)
                 (exit 25)))
             (let (*match*/374 =a (field_imm 1 param/371))
               (if (isint *match*/374) (if *match*/374 (exit 26) 4)
                 (exit 25))))
          with (26) 5)
        with (25)
         (raise (makeblock 0 (global Match_failure/20!) [0: "" 3 26])))))
  (apply (field_mut 1 (global Toploop!)) "f" f/370))
val f : bool * t -> int = <fun>
|}];;


(* Another regression testcase from #13076, proposed by Nick Roberts.

   Performance expectation: no Match_failure clause.
*)
type t =
  | A of int
  | B of string
  | C of string
  | D of string

let compare t1 t2 =
  match t1, t2 with
  | A i, A j -> Int.compare i j
  | B l1, B l2 -> String.compare l1 l2
  | C l1, C l2 -> String.compare l1 l2
  | D l1, D l2 -> String.compare l1 l2
  | A _, (B _ | C _ | D _ ) -> -1
  | (B _ | C _ | D _ ), A _ -> 1
  | B _, (C _ | D _) -> -1
  | (C _ | D _), B _ -> 1
  | C _, D _ -> -1
  | D _, C _ -> 1
(* FAIL: a Match_failure clause is generated. *)
[%%expect {|
0
type t = A of int | B of string | C of string | D of string
(let
  (compare/381 =
     (function t1/382 t2/383 : int
       (catch
         (catch
           (switch* t1/382
            case tag 0:
             (switch t2/383
              case tag 0:
               (apply (field_imm 8 (global Stdlib__Int!))
                 (field_imm 0 t1/382) (field_imm 0 t2/383))
              default: -1)
            case tag 1:
             (catch
               (switch* t2/383
                case tag 0: (exit 30)
                case tag 1:
                 (apply (field_imm 9 (global Stdlib__String!))
                   (field_imm 0 t1/382) (field_imm 0 t2/383))
                case tag 2: (exit 35)
                case tag 3: (exit 35))
              with (35) -1)
            case tag 2:
             (switch* t2/383
              case tag 0: (exit 30)
              case tag 1: (exit 30)
              case tag 2:
               (apply (field_imm 9 (global Stdlib__String!))
                 (field_imm 0 t1/382) (field_imm 0 t2/383))
              case tag 3: -1)
            case tag 3:
             (switch* t2/383
              case tag 0: (exit 30)
              case tag 1: (exit 30)
              case tag 2: 1
              case tag 3:
               (apply (field_imm 9 (global Stdlib__String!))
                 (field_imm 0 t1/382) (field_imm 0 t2/383))))
          with (30)
           (switch* t2/383
            case tag 0: 1
            case tag 1: 1
            case tag 2: (exit 27)
            case tag 3: (exit 27)))
        with (27)
         (raise (makeblock 0 (global Match_failure/20!) [0: "" 8 2])))))
  (apply (field_mut 1 (global Toploop!)) "compare" compare/381))
val compare : t -> t -> int = <fun>
|}];;
