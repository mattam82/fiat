(** Reference implementation of a splitter and parser based on that splitter *)
Require Import Coq.Strings.String.
Require Import ADTNotation.BuildADT ADTNotation.BuildADTSig.
Require Import ADT.ComputationalADT.
Require Import ADTRefinement.GeneralRefinements.
Require Import ADTSynthesis.Parsers.ParserInterface.
Require Import ADTSynthesis.Parsers.ParserADTSpecification.
Require Import ADTSynthesis.Parsers.StringLike.String.
Require Import ADTSynthesis.Parsers.ContextFreeGrammarTransfer.
Require Import ADTSynthesis.Parsers.ContextFreeGrammarTransferProperties.
Require Import ADTSynthesis.ADTRefinement.Core.
Require Import ADTSynthesis.Common ADTSynthesis.Common.Equality.

Set Implicit Arguments.

Local Open Scope list_scope.
Local Open Scope ADTSig_scope.
Local Open Scope ADT_scope.
Local Open Scope string_scope.
Section parser.
  Context (G : grammar Ascii.ascii).
  Context (splitter_impl : FullySharpened (string_spec G)).

  Lemma fst_cMethods_ex {method arg}
        (st : { r : cRep (projT1 splitter_impl) | exists orig, AbsR (projT2 splitter_impl) orig r })
  : exists orig, AbsR (projT2 splitter_impl) orig (fst (cMethods (projT1 splitter_impl) method (proj1_sig st) arg)).
  Proof.
    destruct st as [st [ orig H ] ].
    pose proof (ADTRefinementPreservesMethods (projT2 splitter_impl) method _ _ arg H (cMethods (projT1 splitter_impl) method st arg) (ReturnComputes _)) as H''.
    computes_to_inv.
    match goal with
      | [ H : (_, _) = _ |- _ ]
        => pose proof (f_equal (@fst _ _) H);
          pose proof (f_equal (@snd _ _) H);
          clear H
    end.
    destruct_head' prod.
    simpl @fst in *.
    simpl @snd in *.
    subst.
    esplit; eassumption.
  Qed.

  Lemma fst_cMethods_comp {method st arg v retv}
        (H0 : Methods (string_spec G) method v arg = ret retv)
        (H1 : AbsR (projT2 splitter_impl) v st)
  : AbsR (projT2 splitter_impl) (fst retv) (fst (cMethods (projT1 splitter_impl) method st arg)).
  Proof.
    pose proof (ADTRefinementPreservesMethods (projT2 splitter_impl) method _ _ arg H1 (cMethods (projT1 splitter_impl) method st arg) (ReturnComputes _)) as H''.
    rewrite H0 in H''; clear H0.
    computes_to_inv.
    match goal with
      | [ H : (_, _) = _ |- _ ]
        => pose proof (f_equal (@fst _ _) H);
          pose proof (f_equal (@snd _ _) H);
          clear H
    end.
    subst.
    destruct_head' prod.
    simpl @fst in *.
    simpl @snd in *.
    subst.
    assumption.
  Qed.

  Lemma snd_cMethods_comp {method st arg v retv}
        (H0 : Methods (string_spec G) method v arg = ret retv)
        (H1 : AbsR (projT2 splitter_impl) v st)
  : snd (cMethods (projT1 splitter_impl) method st arg) = snd retv.
  Proof.
    pose proof (ADTRefinementPreservesMethods (projT2 splitter_impl) method _ _ arg H1 (cMethods (projT1 splitter_impl) method st arg) (ReturnComputes _)) as H''.
    rewrite H0 in H''; clear H0.
    computes_to_inv.
    match goal with
      | [ H : (_, _) = _ |- _ ]
        => pose proof (f_equal (@fst _ _) H);
          pose proof (f_equal (@snd _ _) H);
          clear H
    end.
    subst.
    destruct_head' prod.
    simpl @fst in *.
    simpl @snd in *.
    subst.
    reflexivity.
  Qed.

  Local Ltac snd_cMethods_comp' :=
    idtac;
    match goal with
      | [ |- appcontext G[snd (cMethods ?impl ?meth ?st ?arg)] ]
        => let G' := context G[snd (cMethods impl meth st arg)] in
           progress change G'
      | [ H : appcontext G[snd (cMethods ?impl ?meth ?st ?arg)] |- _ ]
        => let G' := context G[snd (cMethods impl meth st arg)] in
           progress change G' in H
      | [ H : appcontext G[snd (cMethods ?impl ?meth ?st ?arg)] |- _ ]
        => erewrite (@snd_cMethods_comp meth st arg) in H by (eassumption || reflexivity);
          simpl @snd in H
      | [ |- appcontext G[snd (cMethods ?impl ?meth ?st ?arg)] ]
        => erewrite (@snd_cMethods_comp meth st arg) by (eassumption || reflexivity);
          simpl @snd
    end.
  Local Ltac snd_cMethods_comp := repeat snd_cMethods_comp'.

  Local Notation StringT := { r : cRep (projT1 splitter_impl) | exists orig, AbsR (projT2 splitter_impl) orig r }%type (only parsing).

  Local Notation mcall0 proj s := (fun n st => (proj (cMethods (projT1 splitter_impl) {| StringBound.bindex := s |} st n))) (only parsing).
  Local Notation mcall1 s := (mcall0 fst s) (only parsing).
  Local Notation mcall2 s := (mcall0 snd s) (only parsing).

  Definition mto_string := Eval simpl in mcall2 "to_string".
  Definition mis_char := Eval simpl in mcall2 "is_char".
  Definition mlength := Eval simpl in mcall2 "length".
  Definition mtake := Eval simpl in mcall1 "take".
  Definition mdrop := Eval simpl in mcall1 "drop".
  Definition premsplits := Eval simpl in cMethods (projT1 splitter_impl) {| StringBound.bindex := "splits" |}.
  Definition msplits := Eval simpl in mcall2 "splits".

  Local Notation mcall1_R meth st arg str H :=
    (@fst_cMethods_comp {| StringBound.bindex := meth |} st arg str _ eq_refl H)
      (only parsing).

  Local Notation mcall2_eq meth st arg str H :=
    (@snd_cMethods_comp {| StringBound.bindex := meth |} st arg str _ eq_refl H)
      (only parsing).

  Definition mto_string_eq {arg st str} (H : AbsR (projT2 splitter_impl) str st)
  : mto_string arg st = str
    := mcall2_eq "to_string" st arg str H.
  Definition mis_char_eq {arg st str} (H : AbsR (projT2 splitter_impl) str st)
  : mis_char arg st = string_beq _ _
    := mcall2_eq "is_char" st arg str H.
  Definition mlength_eq {arg st str} (H : AbsR (projT2 splitter_impl) str st)
  : mlength arg st = String.length str
    := mcall2_eq "length" st arg str H.
  Definition mtake_R {arg st str} (H : AbsR (projT2 splitter_impl) str st)
  : AbsR (projT2 splitter_impl) (take arg str) (mtake arg st)
    := mcall1_R "take" st arg str H.
  Definition mdrop_R {arg st str} (H : AbsR (projT2 splitter_impl) str st)
  : AbsR (projT2 splitter_impl) (drop arg str) (mdrop arg st)
    := mcall1_R "drop" st arg str H.

  Create HintDb parser_adt_method_db discriminated.
  Hint Resolve @mtake_R @mdrop_R : parser_adt_method_db.

  Local Ltac handle_rep :=
    repeat intro;
    repeat match goal with
             | [ st : { r : cRep (projT1 splitter_impl) | exists orig, AbsR (projT2 splitter_impl) orig r }%type |- exists orig, AbsR (projT2 splitter_impl) orig (fst (cMethods ?impl ?method _ ?arg)) ]
               => refine (@fst_cMethods_ex method arg st)
             | [ |- exists orig, AbsR (projT2 splitter_impl) orig (?f ?arg ?st)  ]
               => unfold f
           end;
    destruct_head_hnf' sig;
    destruct_head_hnf' ex;
    unfold beq in *;
    simpl in *;
    repeat match goal with
             | _ => progress erewrite ?@mto_string_eq, ?@mis_char_eq, ?@mlength_eq by eauto with parser_adt_method_db
             | [ H : _ |- _ ] => progress erewrite ?@mto_string_eq, ?@mis_char_eq, ?@mlength_eq in H by eauto with parser_adt_method_db
           end.

  Local Obligation Tactic := handle_rep.

  Local Program Instance adt_based_StringLike : StringLike Ascii.ascii
    := { String := StringT;
         take n str := mtake n str;
         drop n str := mdrop n str;
         length str := mlength tt str;
         is_char str ch := mis_char ch str;
         bool_eq s1 s2 := string_beq (mto_string tt s1) (mto_string tt s2) }.

  Local Ltac t'' H meth :=
    pose proof (meth Ascii.ascii string_stringlike string_stringlike_properties) as H;
    simpl in H; unfold beq in H; simpl in H;
    unfold take, drop; simpl.
  Local Ltac t' meth :=
    let H := fresh in
    t'' H meth;
      eapply H; clear H; simpl.
  Local Ltac t meth := t' meth; eassumption.

  Local Program Instance adt_based_StringLikeProperties : @StringLikeProperties _ adt_based_StringLike
    := { bool_eq_Equivalence := {| Equivalence_Reflexive := _ |} }.
  Next Obligation. t @singleton_unique. Qed.
  Next Obligation. t @length_singleton. Qed.
  Next Obligation. t @bool_eq_char. Qed.
  Next Obligation. t @is_char_Proper. Qed.
  Next Obligation. t @length_Proper. Qed.
  Next Obligation. t @take_Proper. Qed.
  Next Obligation. t @drop_Proper. Qed.
  Next Obligation. t @bool_eq_Equivalence. Qed.
  Next Obligation. t @bool_eq_Equivalence. Qed.
  Next Obligation. t (fun x y z => @Equivalence_Transitive _ _ (@bool_eq_Equivalence x y z)). Qed.
  Next Obligation. t @bool_eq_empty. Qed.
  Next Obligation. t @take_short_length. Qed.
  Next Obligation. t @take_long. Qed.
  Next Obligation. t @take_take. Qed.
  Next Obligation. t @drop_length. Qed.
  Next Obligation. t @drop_0. Qed.
  Next Obligation. t @drop_drop. Qed.
  Next Obligation. t @drop_take. Qed.
  Next Obligation. t @take_drop. Qed.

  Lemma adt_based_splitter_splits_for_complete
  : forall (str : String) (it : item Ascii.ascii)
           (its : production Ascii.ascii),
      split_list_is_complete G str it its (msplits (it, its) (` str)).
  Proof.
    repeat intro.
    destruct_head_hnf sig.
    destruct_head ex.
    erewrite @mlength_eq in * by eassumption.
    lazymatch goal with
      | [ H : AbsR ?Ok ?str ?st
          |- appcontext[msplits ?arg ?st] ]
        => let T := type of Ok in
           let impl := (match eval cbv beta in T with refineADT _ (LiftcADT ?impl) => constr:impl end) in
           let H' := fresh in
           pose proof (ADTRefinementPreservesMethods Ok {| StringBound.bindex := "splits" |}  _ _ arg H ((cMethods impl {| StringBound.bindex := "splits" |} st arg)) (ReturnComputes _)) as H';
             change (msplits arg st) with (snd (premsplits st arg));
             match type of H' with
               | appcontext G[cMethods _ {| StringBound.bindex := "splits" |} ?st ?arg]
                 => let G' := context G[premsplits st arg] in
                    change G' in H'
             end
    end.
    simpl in *.
    computes_to_inv; subst; simpl in *.
    match goal with
      | [ H : ?x = premsplits _ _ |- _ ] => rewrite <- H; clear H; simpl
    end.
    lazymatch goal with
      | [ H : split_list_is_complete _ _ _ _ _, H' : ?n <= _,
          p0 : parse_of_item _ _ _, p1 : parse_of_production _ _ _,
          H'' : production_is_reachable _ _,
          p0H : ContextFreeGrammarProperties.Forall_parse_of_item _ _,
          p1H : ContextFreeGrammarProperties.Forall_parse_of_production _ _
          |- List.In ?n ?v ]
        => hnf in H;
          specialize (fun H0 H0' H1' =>
                        H n H' H''
                          (@transfer_parse_of_item
                             Ascii.ascii adt_based_StringLike string_stringlike G
                             (fun s1 s2 => AbsR (projT2 splitter_impl) s2 (` s1))
                             H0 _ _ _ H0' p0)
                          (@transfer_parse_of_production
                             Ascii.ascii adt_based_StringLike string_stringlike G
                             (fun s1 s2 => AbsR (projT2 splitter_impl) s2 (` s1))
                             H0 _ _ _ H1' p1)
                          (@transfer_forall_parse_of_item
                             Ascii.ascii adt_based_StringLike string_stringlike G
                             (fun s1 s2 => AbsR (projT2 splitter_impl) s2 (` s1))
                             H0 _ _ _ _ H0' p0 p0H)
                          (@transfer_forall_parse_of_production
                             Ascii.ascii adt_based_StringLike string_stringlike G
                             (fun s1 s2 => AbsR (projT2 splitter_impl) s2 (` s1))
                             H0 _ _ _ _ H1' p1 p1H));
          apply H; clear H p0H p1H p0 p1; try assumption; simpl
    end; [ split | | ];
    handle_rep;
    eauto with parser_adt_method_db.
    { pose proof (@mdrop_R).
      simpl in *; eauto. }
    { pose proof (@mdrop_R).
      simpl in *; eauto. }
  Qed.

  Definition adt_based_splitter : Splitter G
    := {| string_type := adt_based_StringLike;
          string_type_properties := adt_based_StringLikeProperties;
          splits_for str it its := msplits (it, its) (` str);
          splits_for_complete := adt_based_splitter_splits_for_complete |}.
End parser.
