(** Refinement rules for disjoint rules *)
Require Import Fiat.Parsers.Refinement.PreTactics.
Require Import Fiat.Computation.Refinements.General.
Require Import Fiat.Parsers.StringLike.Properties.
Require Import Fiat.Parsers.StringLike.FirstChar.
Require Import Fiat.Common.Equality.
Require Import Fiat.Common.List.Operations.
Require Import Fiat.Parsers.ContextFreeGrammar.ValidReflective.
Require Import Fiat.Parsers.Refinement.DisjointLemmas.
Require Import Fiat.Parsers.Refinement.DisjointRulesCommon.
Require Import Fiat.Parsers.ParserInterface.
Require Import Fiat.Parsers.StringLike.Core.
Export DisjointLemmas.Exports.

Set Implicit Arguments.

Lemma find_first_char_such_that'_short {Char HSLM HSL}
      str P len
  : @find_first_char_such_that' Char HSLM HSL P len str <= len.
Proof.
  revert str; induction len; simpl; intros; [ reflexivity | ].
  destruct (get (length str - S len) str) eqn:H.
  { edestruct P; try omega.
    apply Le.le_n_S, IHlen. }
  { apply Le.le_n_S, IHlen. }
Qed.

Lemma find_first_char_such_that_short {Char HSLM HSL}
      str P
  : @find_first_char_such_that Char HSLM HSL str P <= length str.
Proof.
  apply find_first_char_such_that'_short.
Qed.

Lemma is_first_char_such_that__find_first_char_such_that {Char} {HSLM HSL} {HSLP : @StringLikeProperties Char HSLM HSL} str P
      might_be_empty
      (H : exists n, is_first_char_such_that might_be_empty str n (fun ch => is_true (P ch)))
  : is_first_char_such_that might_be_empty str (@find_first_char_such_that Char HSLM HSL str P) (fun ch => is_true (P ch)).
Proof.
  unfold find_first_char_such_that.
  destruct H as [n H].
  set (len := length str).
  setoid_replace str with (drop (length str - len) str) at 1
    by (subst; rewrite Minus.minus_diag, drop_0; reflexivity).
  setoid_replace str with (drop (length str - len) str) in H
    by (subst; rewrite Minus.minus_diag, drop_0; reflexivity).
  assert (len <= length str) by reflexivity.
  clearbody len.
  generalize dependent str; revert n.
  induction len; simpl; intros n str IH Hlen.
  { apply first_char_such_that_0.
    rewrite drop_length.
    rewrite NPeano.Nat.sub_0_r in IH |- *.
    rewrite Minus.minus_diag.
    split.
    { apply for_first_char_nil.
      rewrite drop_length; omega. }
    { generalize dependent str.
      induction n; intros str H Hlen.
      { apply first_char_such_that_0 in H.
        rewrite drop_length, Minus.minus_diag in H.
        destruct_head and; trivial. }
      { apply first_char_such_that_past_end in H; [ | rewrite drop_length; omega ].
        left; assumption. } } }
  { pose proof (singleton_exists (take 1 (drop (length str - S len) str))) as H'.
    rewrite take_length, drop_length in H'.
    destruct H' as [ch H']; [ apply Min.min_case_strong; intros; omega | ].
    rewrite get_drop.
    rewrite (proj1 (get_0 _ _) H').
    destruct (P ch) eqn:H''.
    { apply first_char_such_that_0.
      rewrite drop_length.
      split; [ | right; omega ].
      apply (for_first_char__take 0).
      rewrite <- for_first_char_singleton by eassumption; trivial. }
    { apply is_first_char_such_that_drop.
      destruct n.
      { apply first_char_such_that_0 in IH.
        destruct IH as [IH _].
        apply (for_first_char__take 0) in IH.
        rewrite <- for_first_char_singleton in IH by eassumption; unfold is_true in *; congruence. }
      { apply is_first_char_such_that_drop in IH.
        destruct IH as [IH _].
        rewrite drop_drop in IH |- *; simpl in IH |- *.
        replace (S (length str - S len)) with (length str - len) in IH |- * by omega.
        split.
        { eapply IHlen; try eassumption; [].
          omega. }
        { apply (for_first_char__take 0).
          rewrite <- for_first_char_singleton by eassumption; congruence. } } } }
Qed.

Lemma refine_find_first_char_such_that {Char} {HSLM : StringLikeMin Char} {HSL : StringLike Char} {HSLP : StringLikeProperties Char}
      (str : String)
      (P : Char -> bool)
      might_be_empty
  : refine { n : nat | n <= length str
                       /\ ((exists n', is_first_char_such_that might_be_empty str n' P)
                           -> is_first_char_such_that might_be_empty str n P) }
           (ret (find_first_char_such_that str P)).
Proof.
  intros v H.
  computes_to_inv; subst.
  apply PickComputes.
  split; [ apply find_first_char_such_that_short | ].
  apply is_first_char_such_that__find_first_char_such_that.
Qed.

Section with_grammar.
  Context {HSLM : StringLikeMin Ascii.ascii}
          {HSL : StringLike Ascii.ascii}
          {HSI : StringIso Ascii.ascii}
          {HSLP : StringLikeProperties Ascii.ascii}
          {HSIP : StringIsoProperties Ascii.ascii}
          (G : pregrammar' Ascii.ascii)
          (Hvalid : grammar_rvalid G)
          (search_data : disjoint_search_data G).

  Local Notation possible_terminals_of := (possible_terminals_of G compiled_productions_possible_terminals).
  Local Notation possible_first_terminals_of_production :=
    (possible_first_terminals_of_production G compiled_productions_maybe_empty_of compiled_productions_possible_first_terminals).
  Local Notation possible_terminals_of_production :=
    (possible_terminals_of_production G compiled_productions_possible_terminals).
  Local Notation possible_last_terminals_of :=
    (possible_last_terminals_of G compiled_productions_maybe_empty_of compiled_productions_possible_last_terminals).

  Definition search_for_condition
             str its (n : nat)
    := is_first_char_such_that
         (might_be_empty (possible_first_terminals_of_production its))
         str
         n
         (fun ch => list_bin ascii_beq ch (possible_first_terminals_of_production its)).

  Lemma refine_disjoint_search_for'
        {str offset len nt its}
        (H_disjoint : disjoint ascii_beq
                               (possible_terminals_of nt)
                               (possible_first_terminals_of_production its))
    : refine {splits : list nat
             | split_list_is_complete
                 G str offset len
                 (NonTerminal nt::its) splits}
             (n <- { n : nat | n <= length (substring offset len str)
                               /\ ((exists n', search_for_condition (substring offset len str) its n')
                                   -> search_for_condition (substring offset len str) its n) };
                ret [n]).
  Proof.
    intros ls H.
    computes_to_inv; subst.
    destruct H as [H0 H1].
    apply PickComputes.
    hnf; cbv zeta.
    intros Hlen it' its' Heq n ? H_reachable pit pits.
    inversion Heq; subst it' its'; clear Heq.
    left.
    pose proof (terminals_disjoint_search_for _ Hvalid _ H_disjoint pit pits H_reachable) as H'.
    specialize (H1 (ex_intro _ n H')).
    pose proof (is_first_char_such_that_eq_nat_iff H1 H') as H''.
    destruct_head or; destruct_head and; subst;
      rewrite ?Min.min_r, ?Min.min_l by assumption;
      omega.
  Qed.

  Definition search_for_not_condition
             str nt its n
    := is_first_char_such_that
         (might_be_empty (possible_first_terminals_of_production its))
         str
         n
         (fun ch => negb (list_bin ascii_beq ch (possible_terminals_of nt))).

  Lemma refine_disjoint_search_for_not'
        {str offset len nt its}
        (H_disjoint : disjoint ascii_beq
                               (possible_terminals_of nt)
                               (possible_first_terminals_of_production its))
    : refine {splits : list nat
             | split_list_is_complete
                 G str offset len
                 (NonTerminal nt::its)
                 splits}
             (n <- { n : nat | n <= length (substring offset len str)
                               /\ ((exists n', search_for_not_condition (substring offset len str) nt its n')
                                   -> search_for_not_condition (substring offset len str) nt its n) };
                ret [n]).
  Proof.
    intros ls H.
    computes_to_inv; subst.
    destruct H as [H0 H1].
    apply PickComputes.
    hnf; cbv zeta.
    intros Hlen it' its' Heq n ? H_reachable pit pits.
    inversion Heq; subst it' its'; clear Heq.
    left.
    pose proof (terminals_disjoint_search_for_not _ Hvalid _ H_disjoint pit pits H_reachable) as H'.
    specialize (H1 (ex_intro _ n H')).
    pose proof (is_first_char_such_that_eq_nat_iff H1 H') as H''.
    destruct_head or; destruct_head and; subst;
      rewrite ?Min.min_r by assumption;
      omega.
  Qed.

  Lemma refine_disjoint_search_for
        {str offset len nt its}
        (H_disjoint : disjoint ascii_beq
                               (possible_terminals_of nt)
                               (possible_first_terminals_of_production its))
    : refine {splits : list nat
             | split_list_is_complete
                 G str offset len
                 (NonTerminal nt::its)
                 splits}
             (ret [find_first_char_such_that (substring offset len str) (fun ch => list_bin ascii_beq ch (possible_first_terminals_of_production its))]).
  Proof.
    rewrite refine_disjoint_search_for' by assumption.
    setoid_rewrite refine_find_first_char_such_that.
    simplify with monad laws; reflexivity.
  Qed.

  Lemma refine_disjoint_search_for_not
        {str offset len nt its}
        (H_disjoint : disjoint ascii_beq
                               (possible_terminals_of nt)
                               (possible_first_terminals_of_production its))
    : refine {splits : list nat
             | split_list_is_complete
                 G str offset len
                 (NonTerminal nt::its)
                 splits}
             (ret [find_first_char_such_that (substring offset len str) (fun ch => negb (list_bin ascii_beq ch (possible_terminals_of nt)))]).
  Proof.
    rewrite refine_disjoint_search_for_not' by assumption.
    setoid_rewrite refine_find_first_char_such_that.
    simplify with monad laws; reflexivity.
  Qed.

  Lemma refine_disjoint_search_for_idx
        {str offset len nt its idx}
        (Heq : default_to_production (G := G) idx = NonTerminal nt :: its)
        (H_disjoint : disjoint ascii_beq
                               (possible_terminals_of nt)
                               (possible_first_terminals_of_production its))
    : refine {splits : list nat
             | split_list_is_complete_idx
                 G str offset len
                 idx
                 splits}
             (ret [find_first_char_such_that (substring offset len str) (fun ch => list_bin ascii_beq ch (possible_first_terminals_of_production its))]).
  Proof.
    unfold split_list_is_complete_idx.
    erewrite <- refine_disjoint_search_for by eassumption.
    rewrite Heq.
    apply refine_pick_pick; intro; trivial.
  Qed.

  Lemma refine_disjoint_search_for_not_idx
        {str offset len nt its idx}
        (Heq : default_to_production (G := G) idx = NonTerminal nt :: its)
        (H_disjoint : disjoint ascii_beq
                               (possible_terminals_of nt)
                               (possible_first_terminals_of_production its))
    : refine {splits : list nat
             | split_list_is_complete_idx
                 G str offset len
                 idx
                 splits}
             (ret [find_first_char_such_that (substring offset len str) (fun ch => negb (list_bin ascii_beq ch (possible_terminals_of nt)))]).
  Proof.
    unfold split_list_is_complete_idx.
    erewrite <- refine_disjoint_search_for_not by eassumption.
    rewrite Heq.
    apply refine_pick_pick; intro; trivial.
  Qed.
End with_grammar.

Ltac solve_disjoint_side_conditions :=
  idtac;
  lazymatch goal with
  | [ |- Carriers.default_to_production (G := ?G) ?k = ?e ]
    => try cbv delta [G];
       cbv beta iota zeta delta [Carriers.default_to_production Lookup_idx fst snd List.map pregrammar_productions pregrammar_rproductions List.length List.nth minus Operations.List.drop];
       try reflexivity
  | [ |- is_true (Operations.List.disjoint _ _ _) ]
    => vm_compute; try reflexivity
  end.

Ltac replace_with_native_compute_in c H :=
  let c' := (eval native_compute in c) in
  (* By constrast [set ... in ...] seems faster than [change .. with ... in ...] in 8.4?! *)
  replace c with c' in H by (clear; native_cast_no_check (eq_refl c')).

Ltac pose_disjoint_search_for lem :=
  idtac;
  let G := match goal with |- context[ParserInterface.split_list_is_complete_idx ?G ?str ?offset ?len ?idx] => G end in
  let HSLM := match goal with |- context[@ParserInterface.split_list_is_complete_idx ?Char ?G ?HSLM ?HSL] => HSLM end in
  let HSL := match goal with |- context[@ParserInterface.split_list_is_complete_idx ?Char ?G ?HSLM ?HSL] => HSL end in
  let H' := get_hyp_of_shape (is_true (grammar_rvalid G)) in
  let search_data := get_hyp_of_shape (disjoint_search_data G) in
  let lem' := constr:(@refine_disjoint_search_for_idx HSLM HSL _ G H' search_data) in
  let lem' := match goal with
              | [ |- context[ParserInterface.split_list_is_complete_idx ?G ?str ?offset ?len ?idx] ]
                => constr:(fun idx' nt its => lem' str offset len nt its idx')
              end in
  pose proof lem' as lem.
Ltac rewrite_once_disjoint_search_for_specialize lem lem' :=
  idtac;
  let G := (lazymatch goal with
             | [ |- context[ParserInterface.split_list_is_complete_idx ?G ?str ?offset ?len ?idx] ]
               => G
             end) in
  match goal with
  | [ |- context[ParserInterface.split_list_is_complete_idx G ?str ?offset ?len ?idx] ]
    => pose proof (lem idx) as lem';
       do 2 (lazymatch type of lem' with
              | forall a : ?T, _ => idtac; let x := fresh in evar (x : T); specialize (lem' x); subst x
              end);
       let T := match type of lem' with forall a : ?T, _ => T end in
       let H' := fresh in
       assert (H' : T) by solve_disjoint_side_conditions;
       specialize (lem' H'); clear H';
       let x := match type of lem' with
                | context[DisjointLemmas.actual_possible_first_terminals ?ls]
                  => constr:(DisjointLemmas.actual_possible_first_terminals ls)
                end in
       replace_with_vm_compute_in x lem';
       unfold Equality.list_bin in lem';
       change (orb false) with (fun bv : bool => bv) in lem';
       cbv beta in lem';
       let T := match type of lem' with forall a : ?T, _ => T end in
       let H' := fresh in
       assert (H' : T) by solve_disjoint_side_conditions;
       specialize (lem' H'); clear H'
  end.
Ltac rewrite_once_disjoint_search_for lem :=
  let lem' := fresh "lem'" in
  rewrite_once_disjoint_search_for_specialize lem lem';
  setoid_rewrite lem'; clear lem'.
Ltac rewrite_disjoint_search_for_no_clear lem :=
  pose_disjoint_search_for lem;
  progress repeat rewrite_once_disjoint_search_for lem.
Ltac rewrite_disjoint_search_for :=
  idtac;
  let lem := fresh "lem" in
  rewrite_disjoint_search_for_no_clear lem;
  clear lem.
Ltac refine_disjoint_search_for :=
  idtac;
  let lem := fresh "lem" in
  pose_disjoint_search_for lem;
  let lem' := fresh "lem'" in
  rewrite_once_disjoint_search_for_specialize lem lem';
  refine lem'; clear lem'.
