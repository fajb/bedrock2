(*
Simulations usually talk about single executions:
"All low-level executions have a high-level explanation".
Our simulations, however, talk about all executions at once and about single states:
"All states in the low-level outcome set have a corresponding state in the high-level outcome set".
*)

Definition simulation{State1 State2: Type}
           (exec1: State1 -> (State1 -> Prop) -> Prop)
           (exec2: State2 -> (State2 -> Prop) -> Prop)
           (related: State1 -> State2 -> Prop): Prop :=
  forall s1 s2 post1,
    related s1 s2 ->
    exec1 s1 post1 ->
    exec2 s2 (fun s2' => exists s1', related s1' s2' /\ post1 s1').

Definition compile_inv{State1 State2: Type}
           (related: State1 -> State2 -> Prop)(inv: State1 -> Prop): State2 -> Prop :=
  fun s2 => exists s1, related s1 s2 /\ inv s1.

(* More readable if inlined.
   Note: only meaningful if exec is guaranteed to make progress.
Definition is_inv{State: Type}(exec: State -> (State -> Prop) -> Prop)(inv: State -> Prop): Prop :=
  forall s, inv s -> exec s inv.
*)

Lemma compile_inv_is_inv{State1 State2: Type}
      (exec1: State1 -> (State1 -> Prop) -> Prop)
      (exec2: State2 -> (State2 -> Prop) -> Prop)
      (related: State1 -> State2 -> Prop)
      (Sim: simulation exec1 exec2 related)
      (inv1: State1 -> Prop)
      (inv1_is_inv: forall s1, inv1 s1 -> exec1 s1 inv1):
  forall s2, compile_inv related inv1 s2 -> exec2 s2 (compile_inv related inv1).
Proof.
  unfold compile_inv, simulation in *.
  intros s2 (s1 & R & I1).
  eapply Sim.
  - exact R.
  - eapply inv1_is_inv. exact I1.
Qed.

Definition compose_relation{State1 State2 State3: Type}
           (R12: State1 -> State2 -> Prop)(R23: State2 -> State3 -> Prop):
  State1 -> State3 -> Prop :=
  fun s1 s3 => exists s2, R12 s1 s2 /\ R23 s2 s3.

Definition weakening{State: Type}(exec: State -> (State -> Prop) -> Prop): Prop :=
  forall (post1 post2: State -> Prop),
    (forall s, post1 s -> post2 s) ->
    forall s, exec s post1 -> exec s post2.

Lemma compose_simulation{State1 State2 State3: Type}
      (exec1: State1 -> (State1 -> Prop) -> Prop)
      (exec2: State2 -> (State2 -> Prop) -> Prop)
      (exec3: State3 -> (State3 -> Prop) -> Prop)
      (W3: weakening exec3)
      (R12: State1 -> State2 -> Prop)
      (R23: State2 -> State3 -> Prop)
      (S12: simulation exec1 exec2 R12)
      (S23: simulation exec2 exec3 R23):
  simulation exec1 exec3 (compose_relation R12 R23).
Proof.
  unfold simulation, compose_relation in *.
  intros s1 s3 post1 (s2 & HR12 & HR23) E1.
  specialize S12 with (1 := HR12) (2 := E1).
  specialize S23 with (1 := HR23) (2 := S12).
  simpl in S23.
  eapply W3. 2: exact S23.
  simpl. intros s3' (s2' & HR23' & s1' & HR12' & P1).
  eauto.
Qed.
