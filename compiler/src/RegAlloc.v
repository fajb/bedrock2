Require Import compiler.FlatImp.
Require Import compiler.StateCalculus.
Require Import compiler.NameGen.
Require Import compiler.Decidable.
Require Import compiler.Memory.
Require Import riscv.util.BitWidths.
Require Import Coq.Lists.List.
Require Import compiler.util.Common.
Require Import riscv.Utility.

Section Injective.

  Context {A B: Type} {sf: SetFunctions A}.

  Definition injective_over(f: A -> B)(s: set A): Prop :=
    forall a1 a2, a1 \in s -> a2 \in s -> f a1 = f a2 -> a1 = a2.

  Lemma injective_over_union: forall (f: A -> B) (s1 s2: set A),
      injective_over f (union s1 s2) -> injective_over f s1 /\ injective_over f s2.
  Proof.
    unfold injective_over; intuition (set_solver_generic A).
  Qed.

End Injective.

(* require extensionality, and usually only needed for debugging *)
Section EmptySetOps.

  Context {A: Type} {sf: SetFunctions A}.

  Axiom union_empty_l: forall (s: set A), union empty_set s = s.
  Axiom union_empty_r: forall (s: set A), union s empty_set = s.
  Axiom intersect_empty_l: forall (s: set A), intersect empty_set s = empty_set.
  Axiom intersect_empty_r: forall (s: set A), intersect s empty_set = empty_set.
  Axiom diff_empty_l: forall (s: set A), diff empty_set s = empty_set.
  Axiom diff_empty_r: forall (s: set A), diff s empty_set = s.

End EmptySetOps.

Hint Rewrite
    @union_empty_l
    @union_empty_r
    @intersect_empty_l
    @intersect_empty_r
    @diff_empty_l
    @diff_empty_r
: rew_EmptySetOps.

Notation "｛｝" := (@empty_set _ _) : set_scope.

Notation "｛ x ｝" := (singleton_set x) (format "｛ x ｝") : set_scope.

Notation "E ∪ F" := (union E F)
  (at level 37, F at level 0) : set_scope.

Notation "E ∩ F" := (intersect E F)
  (at level 36, F at level 0) : set_scope.

Notation "E — F" := (diff E F)
  (at level 35, F at level 0) : set_scope.

Notation "x ∈ E" := (contains E x) (at level 39) : set_scope.

Notation "x ∉ E" := (~ contains E x) (at level 39) : set_scope.

Notation "E ⊆ F" := (subset E F)
  (at level 38) : set_scope.


(*
Notation "\{}" := (@empty_set _ _) : set_scope.

Notation "\{ x }" := (singleton_set x) : set_scope.

Notation "E \u F" := (union E F)
  (at level 37, F at level 0) : set_scope.

Notation "E \n F" := (intersect E F)
  (at level 36, F at level 0) : set_scope.

Notation "E \- F" := (diff E F)
  (at level 35, F at level 0) : set_scope.

Notation "x \in E" := (contains x E) (at level 39) : set_scope.

Notation "x \notin E" := (~ contains x E) (at level 39) : set_scope.

Notation "E \c F" := (subset E F)
  (at level 38) : set_scope.
*)

Section RegAlloc.

  Context {mword: Set}.
  Context {MW: MachineWidth mword}.

  Variable var: Set.
  Context {var_eq_dec: DecidableEq var}.
  Variable register: Set.
  Context {register_eq_dec: DecidableEq register}.
  Variable func: Set.
  Context {func_eq_dec: DecidableEq func}.

  Context {allocMap: MapFunctions var register}.
  Notation alloc := (map var register).
  Notation vars := (@set var (@map_domain_set _ _ allocMap)).
  Notation registers := (@set register (@map_range_set _ _ allocMap)).
  Existing Instance map_domain_set.
  Existing Instance map_range_set.
  (* don't do this, it might pick up the wrong typeclasses
  Notation vars := (set var).
  Notation registers := (set register).
  *)

  Local Notation stmt  := (FlatImp.stmt var func).      (* input type *)
  Local Notation stmt' := (FlatImp.stmt register func). (* output type *)

  (* set of variables which is certainly written while executing s *)
  Fixpoint certainly_written(s: stmt): vars :=
    match s with
    | SLoad x y    => singleton_set x
    | SStore x y   => singleton_set x
    | SLit x v     => singleton_set x
    | SOp x op y z => singleton_set x
    | SSet x y     => singleton_set x
    | SIf cond s1 s2 => intersect (certainly_written s1) (certainly_written s2)
    | SLoop s1 cond s2 => certainly_written s1
    | SSeq s1 s2 => union (certainly_written s1) (certainly_written s2)
    | SSkip => empty_set
    | SCall argnames fname resnames => of_list resnames
    end.

  (* set of variables which is live before executing s *)
  Fixpoint live(s: stmt): vars :=
    match s with
    | SLoad x y    => singleton_set y
    | SStore x y   => union (singleton_set x) (singleton_set y)
    | SLit x v     => empty_set
    | SOp x op y z => union (singleton_set y) (singleton_set z)
    | SSet x y     => singleton_set y
    | SIf cond s1 s2   => union (singleton_set cond) (union (live s1) (live s2))
    | SLoop s1 cond s2 => union (live s1) (diff (union (singleton_set cond) (live s2))
                                                (certainly_written s1))
    | SSeq s1 s2       => union (live s1) (diff (live s2) (certainly_written s1))
    | SSkip => empty_set
    | SCall argnames fname resnames => of_list argnames
    end.

  Definition holds_forall_livesets(P: vars -> Prop): stmt -> Prop :=
    fix rec(s: stmt) :=
      P (live s) /\
      match s with
      (* recursive cases: *)
      | SIf _ s1 s2 | SLoop s1 _ s2 | SSeq s1 s2 => rec s1 /\ rec s2
      (* non-recursive cases: *)
      | _ => True
      end.

  Definition injective_over_all_livesets{B: Type}(f: var -> B): stmt -> Prop :=
    holds_forall_livesets (fun liveset => injective_over f liveset).

  Variable dummy_register: register.

  Definition start_interval(current: vars * registers * alloc)(x: var)
    : vars * registers * alloc :=
    let '(o, a, m) := current in
    let o := union o (singleton_set x) in
    let '(r, a) := pick_or_else a dummy_register in
    let m := put m x r in
    (o, a, m).

  Fixpoint regalloc
           (o: vars)             (* occupants: variables which currently occupy a register *)
           (a: registers)        (* available registers (those not used currently) *)
           (m: alloc)            (* mapping from variables to registers *)
           (s: stmt)             (* current sub-statement *)
           (l: vars)             (* variables which have a life after statement s *)
    : (vars * registers * alloc) (* new occupants, new available registers, new mapping *)
    :=
    let o_original := o in
    (* these are the variables which actually deserve to occupy a register: *)
    let o := union (live s) (diff l (certainly_written s)) in
    (* intervals which ended... *)
    let dead := diff o_original o in
    (* ... allow allow us to add new available registers to a: *)
    let a := union a (range (restrict m dead)) in
    match s with
    | SLoad x _ | SLit x _ | SOp x _ _ _ | SSet x _ =>
        match get m x with
        | Some rx => (o, a, m) (* nothing to do because no new interval starts *)
        | None    => start_interval (o, a, m) x
        end
    | SStore x y => (o, a, m)
    | SIf cond s1 s2   =>
        let '(o1, a1, m1) := regalloc o a  m  s1 l in
        let '(o2, a2, m2) := regalloc o a1 m1 s2 l in
        (union o1 o2, a2, m2)
    | SLoop s1 cond s2 =>
        let '(o, a, m) := regalloc o a m s1 (union (union (singleton_set cond) (live s2)) l) in
        regalloc o a m s2 l
    | SSeq s1 s2 =>
        let '(o, a, m) := regalloc o a m s1 (union (live s2) l) in
        regalloc o a m s2 l
    | SSkip => (o, a, m)
    | SCall argnames fname resnames => fold_left start_interval resnames (o, a, m)
    end.

  Ltac head e :=
    match e with
    | ?a _ => head a
    | _ => e
    end.

  Goal forall (s: stmt), False.
    intro s.
    destruct s eqn: E;
    match type of E with
    | _ = ?r => let h := head r in idtac "| set ( case :=" h ")"
    end.
  Abort.

  Lemma regalloc_ok: forall  (s: stmt) (l: vars) (o o': vars) (a a': registers) (m m': alloc),
      injective_over (get m) o ->
      injective_over (get m) l ->
      subset (live s) o ->
      regalloc o a m s l = (o', a', m') ->
      injective_over_all_livesets (get m') s /\ injective_over (get m') l.
  Proof.
    induction s;
      intros;
      [ set ( case := @SLoad )
      | set ( case := @SStore )
      | set ( case := @SLit )
      | set ( case := @SOp )
      | set ( case := @SSet )
      | set ( case := @SIf )
      | set ( case := @SLoop )
      | set ( case := @SSeq )
      | set ( case := @SSkip )
      | set ( case := @SCall ) ];
      move case at top;
      repeat destruct_one_match;
      simpl in *;
      repeat destruct_one_match_hyp;
      try destruct_pair_eqs;
      subst.

   (*   unfold injective_over in * *)
   (*   try solve [ intuition (state_calc_generic var register) ]. *)

    Focus 11.
    {
      repeat match goal with
      | IH: _, E: regalloc _ _ _ _ _  = (_, _, _) |- _ => specialize IH with (4 := E)
      end.

      clear E H2.
      destruct IHs1.
      - clear IHs2.

        repeat intro.

        (* this should hold: *)
        assert (subset l (union o (certainly_written (SLoop s1 cond s2)))) as C by admit.
        simpl in C.

        (* counterexample: *)
        assert (varval0: var) by admit.
        assert (varval1: var) by admit.
        assert (varval2: var) by admit.
        assert (regval0: option register) by admit.
        let E := fresh "E" in assert (cond = varval1) as E by admit; rewrite E in *.
        let E := fresh "E" in assert (a1 = varval0)   as E by admit; rewrite E in *.
        let E := fresh "E" in assert (a2 = varval2)   as E by admit; rewrite E in *.
        let E := fresh "E" in assert (live s1 = empty_set) as E by admit; rewrite E in *.
        let E := fresh "E" in assert (l = singleton_set varval2) as E by admit; rewrite E in *.
        let E := fresh "E" in assert (get m = fun _ => regval0) as E by admit; rewrite E in *.
        let E := fresh "E" in assert (o = singleton_set varval0) as E by admit; rewrite E in *.
        let E := fresh "E" in assert (live s2 = union (singleton_set varval0)
                                                      (singleton_set varval1)) as E by admit;
                                rewrite E in *.
        let E := fresh "E" in assert (certainly_written s1 = singleton_set varval1) as E
          by admit; rewrite E in *.

        unfold injective_over in *.
        repeat autorewrite with rew_EmptySetOps in *.

        Open Scope set_scope.

        (* The following form a contradiction:
             E2: live s1 = ｛｝
             E7: certainly_written s1 = ｛varval1｝
             E6: live s2 = ｛varval0｝ ∪ ｛varval1｝
           because varval0 cannot be live before s2 if s1 doesn't certainly write it.
           More generally:
           If s1 is followed by s2, (live s2) ⊆ (live s1) ∪ (certainly_written s1)

           Actually, not quite:
           (live s1) means "the variables which are live before s1 is executed and which
           are read in s1", or equivalently, "the variables which are live before s1 if
           we only consider s1".
           If we want "the variables which are live before s1", we need
           (live (SLoop s1 cond s2)).
        *)

        idtac.

        forget (certainly_written s1) as cws1.
        forget (live s1) as ls1.
        forget (live s2) as ls2.

Require Import Coq.Logic.Classical_Prop.

Definition marker(P: Prop): Prop := P.
Definition marker2(P: Prop): Prop := P.

Lemma EE: forall AA (P: AA -> Prop), (exists a: AA, ~ P a) <-> ~ forall (a: AA), P a.
Proof.
  intros. split.
  - intros. destruct H as [a H]. intro. apply H. auto.
  - intro. destruct (classic (exists a : AA, ~ P a)) as [C | C]; [assumption|].
    exfalso. apply H. intro. destruct (classic (P a)) as [D | D]; [assumption |].
    exfalso. apply C. exists a. assumption.
Qed.

Lemma K: forall (P Q: Prop), (~ marker (P -> Q)) <-> marker (~ (P -> Q)).
Proof.
  cbv [marker]. intros. reflexivity.
Qed.

Definition Func(A B: Type) := A -> B.

(* intro as much as we can *)
repeat intro.

(* map to fun *)
repeat match goal with
       | m: map _ _ |- _ =>
         let f := fresh "f" in
         let H := fresh "HE" in
         remember (get m) as f eqn: H;
           clear m H
       end.

(* clear everything except used vars and Props *)
repeat match goal with
       | H: ?T |- _ =>
         match type of T with
         | Prop => fail 1
         | _ => clear H
         end
       end.

(* revert all Props *)
repeat match goal with
       | H: ?T |- _ =>
         match type of T with
         | Prop => revert H
         end
       end.

(* express set operations in terms of "_ \in _" *)
unfold subset.
repeat (setoid_rewrite union_spec ||
        setoid_rewrite intersect_spec ||
        setoid_rewrite diff_spec).

(* protect functions from being treated as implications *)
repeat match goal with
       | x: ?T1 -> ?T2 |- _ => change (Func T1 T2) in x
       end.

(* mark where hyps begin *)
match goal with
| |- ?G => change (marker G)
end.

(* revert vars *)
repeat match goal with
       | x: ?T |- _ =>
         match T with
         | Type => fail 1
         | SetFunctions _ => fail 1
         | DecidableEq _ => fail 1
         | MapFunctions _ _ => fail 1
         | MachineWidth _ => fail 1
         | _ => idtac
         end;
           revert x
       end.

(* negate goal *)
match goal with
| |- ?P => assert (~P); [|admit]
end.

(* "not forall" to "exists such that not" *)
repeat match goal with
 | |- context[~ (forall (x: ?T), _)] =>
   (assert (forall (P: T -> Prop), (exists x: T, ~ P x) <-> ~ (forall x: T, P x)) as EEE
    by apply EE);
   setoid_rewrite <- EEE;
   clear EEE
end.

(* push "not" into marker *)
setoid_rewrite K.

(* marker for check_sat *)
match goal with
| |- ?P => change (marker2 P)
end.

(* SMT notations *)
Notation "'forall' '((' a T '))' body" := (forall (a: T), body)
   (at level 10, body at level 0, format "forall  (( a  T )) '//' body", only printing).
Notation "'and' A B" := (Logic.and A B) (at level 10, A at level 0, B at level 0).
Notation "'or' A B" := (Logic.or A B) (at level 10, A at level 0, B at level 0).
Notation "'implies' A B" := (A -> B) (at level 10, A at level 0, B at level 0).
Notation "= A B" := (@eq _ A B) (at level 10, A at level 0, B at level 0, only printing).
Notation "E x" := (contains E x) (at level 10, E at level 0, x at level 0, only printing).
Notation "= x y" := (contains (singleton_set x) y) (at level 10, x at level 0, y at level 0, only printing).
Notation "'not' A" := (not A) (at level 10, A at level 0).
Notation "'(assert' P ')'" := (marker P)
                                (at level 10, P at level 0,
                                 format "(assert  P )").
Notation "'(declare-const' a T ')' body" :=
  (ex (fun (a: T) => body))
    (at level 10, body at level 10,
     format "(declare-const  a  T ')' '//' body").
Notation "'(declare-fun' f '(' A ')' B ')' body" :=
  (ex (fun (f: Func A B) => body))
    (at level 10, body at level 10,
     format "(declare-fun  f  '(' A ')'  B ')' '//' body").
Notation "'(declare-fun' a '(' T ')' 'Bool)' body" :=
  (ex (fun (a: set T) => body))
    (at level 10, body at level 10,
     format "(declare-fun  a  '(' T ')'  'Bool)' '//' body").
Notation "'(declare-sort' 'var)' '(declare-sort' 'reg)' x '(check-sat)' '(get-model)'" :=
  (marker2 x) (at level 200, format "'(declare-sort'  'var)' '//' '(declare-sort'  'reg)' '//' x '//' '(check-sat)' '//' '(get-model)'").
Notation reg := (option register).

(* refresh *)
idtac.

(* yields the following SMT query:

   ...

for which Z3 answers:

sat
(model
  ;; universe for var:
  ;;   var!val!1 var!val!0 var!val!2
  ;; -----------
  ;; definitions for universe elements:
  (declare-fun var!val!1 () var)
  (declare-fun var!val!0 () var)
  (declare-fun var!val!2 () var)
  ;; cardinality constraint:
  (forall ((x var)) (or (= x var!val!1) (= x var!val!0) (= x var!val!2)))
  ;; -----------
  ;; universe for reg:
  ;;   reg!val!0
  ;; -----------
  ;; definitions for universe elements:
  (declare-fun reg!val!0 () reg)
  ;; cardinality constraint:
  (forall ((x reg)) (= x reg!val!0))
  ;; -----------
  (define-fun cond () var
    var!val!1)
  (define-fun a2 () var
    var!val!2)
  (define-fun a1 () var
    var!val!0)
  (define-fun l!17 ((x!1 var)) Bool
    (ite (= x!1 var!val!2) true
      false))
  (define-fun k!16 ((x!1 var)) var
    (ite (= x!1 var!val!2) var!val!2
    (ite (= x!1 var!val!0) var!val!0
      var!val!1)))
  (define-fun l ((x!1 var)) Bool
    (l!17 (k!16 x!1)))
  (define-fun f0 ((x!1 var)) reg
    reg!val!0)
  (define-fun ls2!19 ((x!1 var)) Bool
    (ite (= x!1 var!val!2) false
      true))
  (define-fun o!20 ((x!1 var)) Bool
    (ite (= x!1 var!val!0) true
      false))
  (define-fun o ((x!1 var)) Bool
    (o!20 (k!16 x!1)))
  (define-fun ls2 ((x!1 var)) Bool
    (ls2!19 (k!16 x!1)))
  (define-fun cws1!18 ((x!1 var)) Bool
    (ite (= x!1 var!val!1) true
      false))
  (define-fun cws1 ((x!1 var)) Bool
    (cws1!18 (k!16 x!1)))
  (define-fun ls1 ((x!1 var)) Bool
    false)


which, more readably, corresponds to the following counterexample:

universe for var = {varval0, varval1, varval2}
universe for reg = {regval0}
cond = varval1
a1 = varval0
a2 = varval2
ls1 = {}
o20 = {varval0}
l17 = {varval2}
k16 = {varval0 -> varval0,
       varval2 -> varval2,
       _       -> varval1}
l(x) = l17(k16(x)), i.e.
l = {varval2}
f0 = {_ -> regval0}
ls219 = universe for var \ {varval2}, i.e.
ls219 = {varval0, varval1}
o(x) = o20(k16(x)), i.e.
o = {varval0}
ls2(x) = ls219(k16(x)), i.e.
ls2 = universe for var \ {varval2}, i.e.
ls2 = {varval0, varval1}
cws118 = {varval1}
cws1(x) = csw118(k16(x)), i.e.
cws1 = universe for var \ {varval0, varval2}, i.e.
cws1 = {varval1}

sorted and auxiliary vars removed:
...
*)

        Open Scope set_scope.

        (* here is better *)

        unfold injective_over (* in * *).
        intros.
        set_solver_generic var.
        + unfold injective_over in *.
          (*
          specialize H with (3 := H4).
          specialize H0 with (3 := H4).
          *)
  Admitted.

  Inductive inspect{T: Type}: T -> Prop := .

  Goal forall o a m l cond s1 s2 s3, inspect (regalloc o a m (SSeq (SIf cond s1 s2) s3) l).
    intros.
    let b := eval cbv delta [regalloc] in regalloc in change regalloc with b.
    cbv beta iota. fold regalloc.
    simpl live.
  Abort.

  Definition make_total(m: alloc): var -> register :=
    fun x => match get m x with
          | Some r => r
          | None => dummy_register
          end.

  Definition apply_alloc(m: var -> register): stmt -> stmt' :=
    fix rec(s: stmt) :=
      match s with
      | SLoad x y => SLoad (m x) (m y)
      | SStore x y => SStore (m x) (m y)
      | SLit x v => SLit (m x) v
      | SOp x op y z => SOp (m x) op (m y) (m z)
      | SSet x y => SSet (m x) (m y)
      | SIf cond s1 s2   => SIf (m cond) (rec s1) (rec s2)
      | SLoop s1 cond s2 => SLoop (rec s1) (m cond) (rec s2)
      | SSeq s1 s2 => SSeq (rec s1) (rec s2)
      | SSkip => SSkip
      | SCall argnames fname resnames => SCall (List.map m argnames) fname (List.map m resnames)
      end.

  Context {RF: MapFunctions var mword}.
  Notation RegisterFile := (map var mword).

  Context {RF': MapFunctions register mword}.
  Notation RegisterFile' := (map register mword).

  Notation Mem := (@mem mword).

  Context {funcMap: MapFunctions func (list var * list var * stmt)}.
  Context {funcMap': MapFunctions func (list register * list register * stmt')}.

  Definition eval: nat -> RegisterFile -> Mem -> stmt -> option (RegisterFile * Mem) :=
    FlatImp.eval_stmt var func empty_map.

  Definition eval': nat -> RegisterFile' -> Mem -> stmt' -> option (RegisterFile' * Mem) :=
    FlatImp.eval_stmt register func empty_map.

  Lemma apply_alloc_ok: forall (mapping: var -> register) (fuel: nat) (s: stmt) (l: vars)
                          (rf1 rf2: RegisterFile) (rf1': RegisterFile') (m1 m2: Mem),
      injective_over_all_livesets mapping s ->
      injective_over mapping l ->
      (forall x, x \in (live s) -> get rf1 x = get rf1' (mapping x)) ->
      eval fuel rf1 m1 s = Some (rf2, m2) ->
      exists (rf2': RegisterFile'),
        eval' fuel rf1' m1 (apply_alloc mapping s) = Some (rf2', m2) /\
        (forall x, x \in l -> get rf2 x = get rf2' (mapping x)).
  Proof.
  Admitted.

  Variable available_registers: registers. (* r1..r31 on RISCV *)

  (* c: mapping of registers we care about at end (which contain results we want to read) *)
  Definition register_mapping(s: stmt)(c: alloc): var -> register :=
    let '(_, _, m) := regalloc empty_set (diff available_registers (range c)) c s (domain c) in
    (make_total m).

  Definition register_allocation(s: stmt)(c: alloc): stmt' :=
    apply_alloc (register_mapping s c) s.

  Lemma register_allocation_ok: forall (fuel: nat) (s: stmt) (c: alloc)
                                  (rf1 rf2: RegisterFile) (rf1': RegisterFile') (m1 m2: Mem),
      (forall x, get rf1 x = get rf1' (register_mapping s c x)) ->
      eval fuel rf1 m1 s = Some (rf2, m2) ->
      exists (rf2': RegisterFile'),
        eval' fuel rf1' m1 (register_allocation s c) = Some (rf2', m2) /\
        (forall x, x \in domain c -> get rf2 x = get rf2' (register_mapping s c x)).
  Proof.
    intros.
    pose proof (regalloc_ok s (domain c)) as Q.
    destruct (regalloc empty_set (diff available_registers (range c)) c s (domain c))
      as [[? ?] m'] eqn: E.
    specialize Q with (o := empty_set) (a := (diff available_registers (range c))) (m := c).
    specialize Q with (4 := E).
    destruct Q as [I1 I2].
    - admit.
    - admit.
    - admit.
    - pose proof (apply_alloc_ok (register_mapping s c) fuel s (domain c) rf1 rf2 rf1' m1 m2)
        as P.
      specialize P with (4 := H0).
      destruct P as [rf2' [Ev Eq]].
      + unfold register_mapping.
        rewrite E.
        admit. (* lift make_total over injective_over_all_livesets *)
      + unfold register_mapping.
        rewrite E.
        admit. (* lift make_total over injective_over_all_livesets *)
      + intros. apply H.
      + eauto.
  Admitted.

End RegAlloc.
