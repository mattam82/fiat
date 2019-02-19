Require Import
        Fiat.Computation
        Fiat.Common.DecideableEnsembles
        Fiat.Narcissus.Common.Specs
        Fiat.Narcissus.Common.ComposeOpt
        Fiat.Narcissus.Common.Notations
        Fiat.Narcissus.Formats.Base.FMapFormat
        Fiat.Narcissus.Formats.Base.LaxTerminalFormat.

Section SequenceFormat.

  Context {T : Type}. (* Target Type *)
  Context {cache : Cache}. (* State Type *)
  Context {monoid : Monoid T}. (* Target type is a monoid. *)

  Definition sequence_Format
             {S : Type}
             (format1 format2 : FormatM S T)
    := (fun s => compose _ (format1 s) (format2 s))%comp.

  Definition sequence_Decode
             {S S' : Type}
             (decode1 : DecodeM (S' * T) T)
             (decode2 : S' -> DecodeM S T)
    : DecodeM S T
    := (fun t env =>
          match decode1 t env with
          | Some (s', t', env') => decode2 s' t' env'
          | None => None
          end).

  Definition sequence_Decode'
             {S S' : Type}
             (decode1 : DecodeM (S' * T) T)
             (decode2 : S' -> DecodeM (S * T) T)
    : DecodeM (S' * S * T) T :=
    fun t env =>
      match decode1 t env with
      | Some (s', t', env') =>
        match decode2 s' t' env' with
        | Some (s, t', env'') => Some ((s', s), t', env'')
        | None => None
        end
      | None => None
      end.

  Definition sequence_Encode
             {S : Type}
             (encode1 encode2 : EncodeM S T)
    := (fun s env =>
          `(t1, env') <- encode1 s env ;
          `(t2, env'') <- encode2 s env';
          Some (mappend t1 t2, env'')).

  Notation "x ++ y" := (sequence_Format x y) : format_scope .

  Lemma CorrectEncoder_sequence
        {S : Type}
        (format1 format2 : FormatM S T)
        (encode1 encode2 : EncodeM S T)
        (encode1_correct : CorrectEncoder format1 encode1)
        (encode1_consistent : (* If the first format produces *some*
                                 environment that makes the second format
                                 (and thus the composite format) non-empty,
                                 the encoder must also produce an environment
                                 that makes the second format non-empty. *)
           forall s env tenv' tenv'',
             format1 s env ∋ tenv'
             -> format2 s (snd tenv') ∋ tenv''
             -> exists tenv3 tenv4,
                 encode1 s env = Some tenv3
                 /\ format2 s (snd tenv3) ∋ tenv4)
        (encode2_correct : CorrectEncoder format2 encode2)
    : CorrectEncoder (format1 ++ format2)
                     (sequence_Encode encode1 encode2).
  Proof.
    unfold CorrectEncoder, sequence_Encode, sequence_Format, compose,
    DecodeBindOpt, BindOpt in *; intuition; intros.
    - destruct (encode1 a env) as [ [t1 xxenv] | ] eqn: ? ;
        simpl in *; try discriminate.
      destruct (encode2 a xxenv) as [ [t2 xxxenv] | ] eqn: ? ;
        simpl in *; try discriminate; injections.
      repeat computes_to_econstructor; eauto.
    -  unfold Bind2 in *; computes_to_inv; destruct v;
         destruct v0; simpl in *.
       destruct (encode1 a env) as [ [t1 xxenv] | ] eqn: ? ;
        simpl in *; try discriminate; eauto.
       eapply H2; try eassumption.
       destruct (encode2 a xxenv) as [ [t2' xxxenv] | ] eqn: ? ;
        simpl in *; try discriminate; injections.
       specialize (encode1_consistent _ _ _ _ H4 H4');
         destruct_ex; split_and.
       rewrite H6 in Heqo; injections; simpl in *.
       destruct x0; elimtype False; eauto.
  Qed.

  Lemma Sequence_decode_correct
        {S V1 V2 : Type}
        {P : CacheDecode -> Prop}
        {P_inv1 P_inv2 : (CacheDecode -> Prop) -> Prop}
        (P_inv_pf : cache_inv_Property P (fun P => P_inv1 P /\ P_inv2 P))
        (view1 : S -> V1 -> Prop)
        (view2 : V1 -> S -> V2 -> Prop)
        (Source_Predicate : S -> Prop)
        (View_Predicate2 : V1 -> V2 -> Prop)
        (View_Predicate1 : V1 -> Prop)
        (consistency_predicate : V1 -> S -> Prop)
        (format1 format2 : FormatM S T )
        (decode1 : DecodeM (V1 * T) T)
        (view_format1 : FormatM V1 T)
        (consistency_predicate_OK :
           forall s v1 t1 t2 env xenv xenv',
             computes_to (format1 s env) (t1, xenv)
             -> computes_to (view_format1 v1 env) (t2, xenv')
             -> view1 s v1
             -> consistency_predicate v1 s)
      (*consistency_predicate_refl :
         forall a, consistency_predicate (proj' a) (proj a))
      (proj_predicate_OK :
         forall s, predicate (proj s)
                   -> proj_predicate (proj' s) *)
      (decode1_pf :
         cache_inv_Property P P_inv1
         -> CorrectDecoder monoid Source_Predicate View_Predicate1 view1 format1 decode1 P view_format1)
      (*pred_pf : forall s, predicate s -> predicate' s *)
      (decode2 : V1 -> DecodeM (V2 * T) T)
      (view_format2 : V1 -> FormatM V2 T)
      (view_format3 : FormatM (V1 * V2) T)
      (decode2_pf : forall v1 : V1,
          cache_inv_Property P P_inv2 ->
          View_Predicate1 v1 ->
          CorrectDecoder monoid (fun s => Source_Predicate s
                                          /\ consistency_predicate v1 s)
                         (View_Predicate2 v1) (view2 v1) format2 (decode2 v1) P (view_format2 v1))
      (view_format3_OK : forall v1 t1 env1 xenv1 v2 t2 xenv2,
          view_format1 v1 env1 (t1, xenv1)
          -> view_format2 v1 v2 xenv1 (t2, xenv2)
          -> View_Predicate2 v1 v2
          -> View_Predicate1 v1
          -> view_format3 (v1, v2) env1 (mappend t1 t2, xenv2))
    : CorrectDecoder
      monoid
      Source_Predicate
      (fun v1v2 => View_Predicate1 (fst v1v2) /\ View_Predicate2 (fst v1v2) (snd v1v2))
      (fun s v1v2 => view1 s (fst v1v2) /\ view2 (fst v1v2) s (snd v1v2))
      (format1 ++ format2)
      (sequence_Decode' decode1 decode2) P
      view_format3.
Proof.
  unfold cache_inv_Property, sequence_Decode, sequence_Format, compose in *;
    split.
  { intros env env' xenv s t ext ? env_pm pred_pm com_pf.
    unfold compose, Bind2 in com_pf; computes_to_inv; destruct v;
      destruct v0.
    destruct (fun H => proj1 (decode1_pf (proj1 P_inv_pf)) _ _ _ _ _ (mappend t1 ext) env_OK env_pm H com_pf); eauto; destruct_ex; split_and; simpl in *; injections; eauto.
    unfold sequence_Decode'.
    setoid_rewrite <- mappend_assoc; rewrite H0.
    pose proof (proj2 (decode1_pf H2) _ _ _ _ _ _ env_pm env_OK H0);
      split_and; destruct_ex; split_and.
    destruct (fun H => proj1 (decode2_pf x H4 H8)
                             _ _ _ _ _ ext H3 H1 H com_pf').
    split; try eassumption.
    eauto.
    destruct_ex; split_and.
    rewrite H11; eexists _, _; eauto.
  }
  { intros ? ? ? ? t; intros.
    unfold sequence_Decode' in H1.
    destruct (decode1 t env') as [ [ [? ?] ? ] | ] eqn : ? ;
      simpl in *; try discriminate.
    generalize Heqo; intros Heqo'.
    eapply (proj2 (decode1_pf (proj1 P_inv_pf))) in Heqo; eauto.
    split_and; destruct_ex; split_and.
    subst.
    destruct (decode2 v0 t0 c) as [ [ [? ?] ? ] | ] eqn : ? ;
      simpl in *; try discriminate; injections.
    eapply (proj2 (decode2_pf _ H5 H7)) in Heqo; eauto.
    destruct Heqo as [? ?]; destruct_ex; split_and; subst.
    setoid_rewrite mappend_assoc.
    split; eauto.
    eexists _, _; repeat split; eauto.
    apply unfold_computes.
    eapply view_format3_OK; try eassumption.
    apply unfold_computes; eassumption.
    apply unfold_computes; eassumption.
  }
Qed.

  (*Corollary CorrectDecoder_sequence_Done
            {S : Type}
            (P : S -> Prop)
            (format : FormatM (S * T) T)
            (s : S)
            (singleton_format : forall (s' : S) (t : T) env tenv',
                format (s', t) env ∋ tenv' <-> s' = s
                                               /\ fst tenv' = mempty
                                               /\ snd tenv' = env)
    : CorrectDecoder_simpl (format ++ ?* ) (LaxTerminal_Decode s).
  Proof.
    unfold CorrectDecoder_simpl, LaxTerminal_Format,
    LaxTerminal_Decode, sequence_Format, Compose_Format; split; intros.
    - unfold Bind2 in H0; computes_to_inv; subst.
      injections.
      destruct data; eapply singleton_format in H0; simpl in *; intuition; subst.
      destruct v; simpl in *; subst.
      eexists; split; eauto.
      rewrite mempty_left; reflexivity.
    - injections; unfold Bind2; eexists.

      simpl.
      destruct v; destruct v0; simpl in *; injections.
      destruct decode1_correct as [? _].
      destruct (decode2_correct x) as [? _].
      destruct (H0 env env' c (x, t0) (mappend t t0)) as (xenv', (decode1_eq, Equiv_xenv));
        eauto.
      rewrite decode1_eq; eauto.
      eapply H3; eauto.
      unfold Restrict_Format, Compose_Format; apply unfold_computes.
      setoid_rewrite unfold_computes; eexists; intuition eauto.
    - destruct (decode1 bin env') as [ [ [s' t'] xenv'']  | ] eqn: ?; try discriminate.
      destruct decode1_correct as [decode1_correct' decode1_correct].
      specialize (decode2_correct s'); destruct decode2_correct as [_ decode2_correct].
      generalize Heqo; intro Heqo'.
      eapply decode1_correct in Heqo; eauto.
      destruct_ex; split_and.
      eapply decode2_correct in H0; eauto.
      destruct_ex; split_and.
      eexists; intuition eauto.
      unfold Restrict_Format, Compose_Format, LaxTerminal_Format, sequence_Format,
        Bind2 in *; computes_to_inv.
      rewrite @unfold_computes in H1.
      destruct_ex; split_and; simpl in *; subst.
      eapply format1'_overlap in H2; destruct_ex; split_and; subst; eauto.
  Qed.
    unfold

    eapply (CorrectDecoder_sequence (fun s s' => f s = s')); eauto; intros;
      unfold Projection_Format, Compose_Format, sequence_Format, Bind2, LaxTerminal_Format in *.
    - rewrite @unfold_computes in H.
      destruct_ex; split_and; subst.
      eexists; intros; intuition.
      destruct tenv'; simpl; computes_to_econstructor.
      rewrite unfold_computes; eauto.
      simpl; computes_to_econstructor; eauto.
    - computes_to_inv; subst.
      apply_in_hyp @unfold_computes; destruct_ex; split_and; subst.
      eexists; simpl; intuition eauto.
      destruct v; apply unfold_computes; eauto.
  Qed. *)


End SequenceFormat.

Notation "x ++ y" := (sequence_Format x y) : format_scope .