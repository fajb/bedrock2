Require Import coqutil.sanity coqutil.Macros.subst coqutil.Macros.unique.
Require Import coqutil.Datatypes.PrimitivePair coqutil.Datatypes.HList.
Require Import bedrock2.Notations bedrock2.Syntax coqutil.Map.Interface.
Require Import Coq.ZArith.BinIntDef.

Class parameters := {
  syntax :> Syntax.parameters;

  word : Set;
  word_zero : word;
  word_succ : word -> word;
  word_test : word -> bool;
  word_of_Z : BinNums.Z -> option word;
  interp_binop : bopname -> word -> word -> word;

  byte : Type;
  bytes_per : access_size -> nat;
  combine : forall sz, tuple byte (bytes_per sz) -> word;
  split : forall sz, word -> tuple byte (bytes_per sz);

  mem :> map.map word byte;
  locals :> map.map varname word;

  funname_eqb : funname -> funname -> bool
}.

Section semantics.
  Context {pp : unique! parameters}.
  
  Section WithMem.
    Context (m:mem).
    Fixpoint load_bytes (n : nat) (a : word) {struct n} : option (tuple byte n) :=
      match n with
      | O => Some tt
      | S n =>
        'Some b <- map.get m a | None;
        'Some bs <- load_bytes n (word_succ a) | None;
        Some (pair.mk b bs)
      end.
  End WithMem.
  Definition load m a sz : option word :=
    'Some bs <- load_bytes m (bytes_per sz) a | None;
    Some (combine sz bs).
  Fixpoint store_bytes (n : nat) (m:mem) (a : word) : forall (bs : tuple byte n), mem :=
    match n with
    | O => fun bs => m
    | S n => fun bs => store_bytes n (map.put m a (pair._1 bs)) (word_succ a) (pair._2 bs)
    end.
  Definition store sz m a v : option mem :=
    'Some _ <- load m a sz | None;
    Some (store_bytes (bytes_per sz) m a (split sz v)).
  Definition trace := list ((mem * actname * list word) * (mem * list word)).
End semantics.