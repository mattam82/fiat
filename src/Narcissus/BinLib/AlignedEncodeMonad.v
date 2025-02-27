Require Import
        Bedrock.Word
        Coq.omega.Omega
        Coq.NArith.NArith
        Coq.Arith.Arith
        Coq.Numbers.Natural.Peano.NPeano
        Coq.Logic.Eqdep_dec
        Fiat.Narcissus.Common.Specs
        Fiat.Narcissus.Common.ComposeOpt
        Fiat.Narcissus.Common.ComposeIf
        Fiat.Narcissus.BaseFormats
        Fiat.Narcissus.BinLib.Core
        Fiat.Narcissus.BinLib.AlignedByteString.

Section AlignedEncodeM.

  Context {cache : Cache}.
  Context {cacheAddNat : CacheAdd cache nat}.
  Context {S : Type}.

  Definition AlignedEncodeM
             (n : nat) :=
    ByteBuffer.t n (* Vector of bytes that is being written to *)
    -> nat          (* The current index *)
    -> S
    -> CacheFormat  (* The current environment *)
    -> option (ByteBuffer.t n * nat * CacheFormat) (* Error monad + value + updated index + updated cache *).

  Definition AppendAlignedEncodeM
             {n : nat}
             (a : AlignedEncodeM n)
             (b : AlignedEncodeM n)
    : AlignedEncodeM n :=
    fun v idx s c => (Ifopt a v idx s c  as a' Then (b (fst (fst a')) (snd (fst a')) s (snd a')) Else None).

  Definition ReturnAlignedEncodeM
             {numBytes : nat}
    : AlignedEncodeM numBytes :=
    fun v idx s c => Some (v, idx, c).

  Definition AlignedEncodeMEquiv
             {n}
             (a1 a2 : AlignedEncodeM n) : Prop :=
    forall v idx s c, a1 v idx s c = a2 v idx s c.

  Lemma AlignedEncodeMEquiv_refl  {n}:
    forall (a : AlignedEncodeM n),
      AlignedEncodeMEquiv a a.
  Proof.
    unfold AlignedEncodeMEquiv; intros; reflexivity.
  Qed.

  Lemma AlignedEncodeMEquiv_sym  {n}:
    forall (a1 a2 : AlignedEncodeM n),
      AlignedEncodeMEquiv a1 a2 -> AlignedEncodeMEquiv a2 a1.
  Proof.
    unfold AlignedEncodeMEquiv; intros; congruence.
  Qed.

  Lemma AlignedEncodeMEquiv_trans  {n}:
    forall (a1 a2 a3 : AlignedEncodeM n),
      AlignedEncodeMEquiv a1 a2 ->
      AlignedEncodeMEquiv a2 a3 ->
      AlignedEncodeMEquiv a1 a3.
  Proof.
    unfold AlignedEncodeMEquiv; intros; congruence.
  Qed.

  Global Instance PreOrder_AlignedEncodeMEquiv  {n} :
    PreOrder (@AlignedEncodeMEquiv n) :=
    {| PreOrder_Reflexive := AlignedEncodeMEquiv_refl;
       PreOrder_Transitive := AlignedEncodeMEquiv_trans|}.

  Lemma AppendAlignedEncodeM_assoc {n}:
    forall (a : AlignedEncodeM n)
           (f : AlignedEncodeM n)
           (g : AlignedEncodeM n),
      AlignedEncodeMEquiv (AppendAlignedEncodeM (AppendAlignedEncodeM a f) g)
                          (AppendAlignedEncodeM a (AppendAlignedEncodeM f g)).
  Proof.
    unfold AppendAlignedEncodeM, AlignedEncodeMEquiv; simpl; intros.
    destruct (a v idx s c); simpl; eauto.
  Qed.

  Lemma ReturnAlignedEncodeM_LeftUnit {n}:
    forall (f : AlignedEncodeM n),
      AlignedEncodeMEquiv (AppendAlignedEncodeM (@ReturnAlignedEncodeM _) f)
                          f.
  Proof.
    intros; reflexivity.
  Qed.

  Lemma ReturnAlignedEncodeM_RightUnit {n}:
    forall (f : AlignedEncodeM n),
      AlignedEncodeMEquiv (AppendAlignedEncodeM f ReturnAlignedEncodeM) f.
  Proof.
    unfold ReturnAlignedEncodeM, AppendAlignedEncodeM, AlignedEncodeMEquiv; simpl; intros.
    destruct (f v idx s c) as [ [ [? ?] ?] | ] ; simpl; reflexivity.
  Qed.

  Definition ThrowAlignedEncodeM
             {n : nat}
    : AlignedEncodeM n:=
    fun _ _ _ _ => None.

  Fixpoint set_nth'
           {n : nat}
           (v : ByteBuffer.t n)
           (m : nat)
           (a : char)
    : ByteBuffer.t n :=
    match m, v with
    | 0,  Vector.cons _ _ v' => Vector.cons _ a _ v'
    | Datatypes.S m', Vector.cons a' _ v' => Vector.cons _ a' _ (set_nth' v' m' a)
    | _, _ => @Vector.nil _
    end.

  (* Equivalence Criteria:
     A bit-aligned encoder and byte-aligned encoder are equivalent when
\backsimeq     - the byte aligned encoder fails when the bit aligned encoder would write past
       the end of the bytestring
     - encodes the same bit sequence values as the bit-aligned encoder (and who can
       say about the rest of the .
   *)

  Definition EncodeMEquivAlignedEncodeM
             (f : EncodeM S ByteString)
             (f' : forall numBytes, AlignedEncodeM numBytes)
    := forall env s idx,
      (forall t env',
          f s env = Some (t, env')
          -> padding t = 0 ->
          forall (v1 : Vector.t char idx) v m v2,
          exists v',
            f' _ (Vector.append v1 (Vector.append (n := numBytes t) (p := m)
                                                  v v2)) idx s env = Some (v', idx + numBytes t, env') /\
            ByteString_enqueue_ByteString (build_aligned_ByteString v1)
                                          (ByteString_enqueue_ByteString t (build_aligned_ByteString v2))
            = build_aligned_ByteString v')%nat
      /\ (forall t env' numBytes' v,
             f s env = Some (t, env')
             -> 8 + 8 * numBytes' <= length_ByteString t + (8 * idx)
          -> f' numBytes' v idx s env = None)%nat
      /\ (forall t env' numBytes' v,
             f s env = Some (t, env')
             -> padding t <> 0 -> f' numBytes' v idx s env = None)%nat
      /\ (forall numBytes' v, f s env = None -> f' numBytes' v idx s env = None).

  Lemma EncodeMEquivAlignedEncodeM_trans :
    forall bit_decoder1 byte_decoder1 bit_decoder2 byte_decoder2,
      EncodeMEquivAlignedEncodeM bit_decoder1 byte_decoder1
      -> (forall s env, bit_decoder1 s env  = bit_decoder2 s env)
      -> (forall n, AlignedEncodeMEquiv (byte_decoder1 n) (byte_decoder2 n))
      -> EncodeMEquivAlignedEncodeM bit_decoder2 byte_decoder2.
  Proof.
    unfold EncodeMEquivAlignedEncodeM; intros; intuition.
    - revert v1 v v2 H2; rewrite <- ?H0, <- ?H1; intros.
      destruct (proj1 (H _ _ _) _ _ H2 H3 v1 v m v2); intuition.
      eexists; intuition eauto.
      rewrite <- H1; eauto.
    - rewrite <- ?H0, <- ?H1; intros.
      eapply (proj1 (proj2 (H _ _ _))); eauto; rewrite H0; eauto.
    - rewrite <- ?H0, <- ?H1; intros.
      eapply (proj1 (proj2 (proj2 (H _ _ _)))); rewrite ?H0; eauto.
    - rewrite <- ?H0 in H2.
      rewrite <- H1; eapply H; eauto.
  Qed.

  Local Arguments mult : simpl never.

  Definition AlignedEncode_Nil
             numBytes
    : AlignedEncodeM numBytes :=
    (fun v idx s env => (if idx <? Datatypes.S numBytes then @ReturnAlignedEncodeM _ v idx s env else None)).

  Lemma Return_EncodeMEquivAlignedEncodeM
    : EncodeMEquivAlignedEncodeM
        (fun (s : S) (env : CacheFormat) => Some (mempty, env))
        AlignedEncode_Nil.
  Proof.
    unfold EncodeMEquivAlignedEncodeM, AlignedEncode_Nil, ReturnAlignedEncodeM;
      intros; injections; simpl in *; intuition.
    - injections; simpl.
      assert (idx < Datatypes.S (idx + m))%nat as H' by omega;
        rewrite <- ltb_lt in H'; rewrite H'.
      revert v.
      eapply Vector.case0; simpl.
      rewrite (plus_comm idx 0); simpl; eexists _; intuition.
      pose proof (mempty_left (build_aligned_ByteString v2)) as H'';
        simpl in H'';
      rewrite H'', <- build_aligned_ByteString_append; reflexivity.
    - injections; simpl in *.
      destruct (idx <? (Datatypes.S numBytes')) eqn: ?; auto.
      rewrite ltb_lt in Heqb.
      omega.
    - injections; simpl in *; omega.
    - discriminate.
  Qed.

  Local Arguments plus : simpl never.

  Lemma Append_EncodeMEquivAlignedEncodeM
        (encode1 encode2 : EncodeM S ByteString)
        (encode1_aligned encode2_aligned : forall {numBytes}, AlignedEncodeM numBytes)
        (encode1_OK : forall s env t env',
            encode1 s env = Some (t, env') -> padding t = 0)
    : EncodeMEquivAlignedEncodeM encode1 (@encode1_aligned)
      -> EncodeMEquivAlignedEncodeM encode2 (@encode2_aligned)
      -> EncodeMEquivAlignedEncodeM
           (sequence_Encode encode1 encode2)
           (fun numBytes => AppendAlignedEncodeM encode1_aligned encode2_aligned).
  Proof.
    unfold EncodeMEquivAlignedEncodeM; intros; specialize (encode1_OK s env); repeat split; intros.
    - destruct (H env s idx) as [ H' [? ?] ].
      revert H1 v H' H2 H3 H4;
        unfold sequence_Encode;
        destruct (encode1 s env) as [ [t1 env''] | ] eqn: ? ;
        [ | intros; try discriminate];
        simpl; destruct (encode2 s env'') as [ [t2 env'''] | ] eqn: ? ; simpl in *;
          try (intros; discriminate);
          intro; injection H1; intros ? ?; subst;
            simpl; rewrite numBytes_ByteString_enqueue_ByteString;
              intros; eauto.
      destruct (H0 env'' s (idx + (numBytes t1))) as [H0' [? [? ?] ] ].
      specialize (H0' _ _ Heqo0).
      erewrite <- padding_ByteString_enqueue_aligned_ByteString in H0'.
      destruct (H' _ _ (eq_refl _) (encode1_OK _ _ (eq_refl _)) v1 (fst (Vector_split _ _ v)) _
                   (Vector.append (snd (Vector_split _ _ v)) v2)) as [? [? ?] ].
      assert (idx + (numBytes t1 + (numBytes t2 + m)) =
              (idx + numBytes t1) + (numBytes t2 + m)) by omega; simpl in *.
      destruct (H0' H2 (fst (Vector_split _ _ (eq_rect _ (Vector.t char) x _ H10)))
                    (fst (Vector_split _ _ (snd (Vector_split _ _ (eq_rect _ (Vector.t char) x _ H10)))))
                    _ (snd (Vector_split _ _ (snd (Vector_split _ _ (eq_rect _ (Vector.t char) x _ H10)))))
               ).
      assert (idx + numBytes t1 + (numBytes t2 + m) =
              idx + (numBytes t1 + numBytes t2 + m)) as H11' by omega.
      assert (idx + (numBytes t1 + (numBytes t2 + m)) =
              (idx + (numBytes t1 + numBytes t2 + m))) by omega; simpl in *.
      unfold AppendAlignedEncodeM.
      replace (encode1_aligned (idx + ((numBytes t1 + numBytes t2) + m))
                               (Vector.append v1 (Vector.append v v2)) idx s env)
        with (Some (eq_rect _ (Vector.t char) x _ H12, idx + numBytes t1, env''));
        simpl.
      + revert H12; rewrite <- H11'; intros.
        rewrite (plus_assoc idx (numBytes t1) (numBytes t2)).
        eexists _; intuition.
        * etransitivity; [ | apply H4].
          f_equal.
          rewrite <- !Vector_split_append.
          f_equal; eapply UIP_dec; intros; decide equality.
        * rewrite <- H15.
          rewrite ByteString_enqueue_ByteString_assoc.
          rewrite ByteString_enqueue_ByteString_assoc.
          rewrite <- ByteString_enqueue_ByteString_assoc.
          symmetry in H9; destruct (build_aligned_ByteString_split' _ _ _ H9)
            as [? H'']; symmetry in H''; destruct (build_aligned_ByteString_split _ _ _ H'').
          revert H16 H9; clear.
          intro.
          revert H10 x v.
          assert (idx + (numBytes t1 + (numBytes t2 + m)) - idx - (numBytes t2 + m) = numBytes t1)
            as H''' by omega; revert x2 H16; rewrite H'''; clear H'''.
          generalize (numBytes t1); intros; subst.
          rewrite <- !build_aligned_ByteString_append in H9;
            apply build_aligned_ByteString_inj in H9; subst.
          rewrite <- !build_aligned_ByteString_append; repeat f_equal.
          erewrite Vector_append_assoc.
          rewrite <- Equality.transport_pp.
          erewrite (UIP_dec _ _ (eq_refl _)); simpl.
          rewrite <- Vector_append_split_fst; reflexivity.
          erewrite Vector_append_assoc.
          rewrite <- Equality.transport_pp.
          erewrite (UIP_dec _ _ (eq_refl _)); simpl.
          rewrite <- !Vector_append_split_snd; reflexivity.
      + generalize x H8 H12; clear; intros.
         replace (Some
                    (eq_rect (idx + (numBytes t1 + (numBytes t2 + m)))
                             (Vector.t char) x (idx + (numBytes t1 + numBytes t2 + m)) H12,
                     idx + numBytes t1, env'')) with
             (eq_rect _ (fun x => option ((Vector.t char x) * nat * CacheFormat))%type (Some (x, idx + numBytes t1, env'')) _ H12).
         rewrite <- H8.
         assert (idx + (numBytes t1 + numBytes t2 + m) =
                 idx + (numBytes t1 + (numBytes t2 + m))) by omega.
         replace (Vector.append v1 (Vector.append (fst (Vector_split (numBytes t1) (numBytes t2) v))
                                                  (Vector.append (snd (Vector_split (numBytes t1) (numBytes t2) v)) v2)))
           with (eq_rect _ (Vector.t char) (Vector.append v1 (Vector.append v v2)) _ H).
         assert (forall n m (H' : n = m) (v : Vector.t char n),
                    encode1_aligned m (eq_rect n (Vector.t char) v _ H') idx s env =
                    eq_rect n (fun x => option ((Vector.t char x) * nat * CacheFormat))%type
                            (encode1_aligned _ v idx s env) _ H') as H'
             by (intros ? ? H'; rewrite H'; reflexivity).
         rewrite H', <- Equality.transport_pp.
         erewrite (UIP_dec _ _ (eq_refl _)); reflexivity.
         assert (numBytes t1 + numBytes t2 + m = numBytes t1 + (numBytes t2 + m)) by omega.
         replace (Vector.append (fst (Vector_split (numBytes t1) (numBytes t2) v))
                                (Vector.append (snd (Vector_split (numBytes t1) (numBytes t2) v)) v2))
           with (eq_rect _ (Vector.t char) (Vector.append v v2) _ H0)
           by (erewrite Vector_append_assoc, <- Vector_split_append; reflexivity).
         erewrite Vector_append_assoc', Vector_append_assoc, <- Equality.transport_pp.
         reflexivity.
         destruct H12; reflexivity.
      + eapply encode1_OK; eauto.
    - specialize (H env s idx);
        unfold sequence_Encode in *;
        destruct (encode1 s env) as [ [t1 env''] | ] eqn: ? ;
        simpl in *; [ | intros; try discriminate];
        simpl; destruct (encode2 s env'') as [ [t2 env'''] | ] eqn: ? ; simpl in *;
          try (intros; discriminate).
      pose proof (proj1 H _ _ (eq_refl _) (encode1_OK _ _ (eq_refl _))).
      injections.
      rewrite length_ByteString_enqueue_ByteString in H2.
      unfold AppendAlignedEncodeM; destruct (encode1_aligned numBytes' v idx s env) eqn: ? ;
          simpl; eauto.
        destruct (le_lt_dec (8 + 8 * numBytes')
                            (length_ByteString t1 + 8 * idx)).
        { eauto; simpl in l; eapply (proj1 (proj2 H)) in l; eauto; rewrite Heqo1 in l; discriminate. }
        rewrite length_ByteString_no_padding in l by eauto.
        pose proof (proj1 (proj2 (H0 env'' s (snd (fst p))))) as H'.
        assert (numBytes t1 + idx < Datatypes.S numBytes')%nat by omega; clear l.
        assert (idx + numBytes t1 <= numBytes')%nat by omega.
        destruct (Vector_split_lt _ _ H4 v) as [? [? [? [? ?] ] ] ].
        pose proof (proj1 (proj2 (H))) as H'' .
        destruct (H3 (fst (Vector_split _ _ x0)) (snd (Vector_split _ _ x0)) _ x1) as [v' [? ?] ].
        erewrite <- H'; f_equal; clear H'.
      + revert p Heqo1 H6.
        rewrite H5.
        rewrite <- x2; simpl; clear.
        rewrite Vector_append_assoc with (H := sym_eq (plus_assoc idx (numBytes t1) x)), <- Vector_split_append.
        generalize v' (eq_sym (plus_assoc idx (numBytes t1) x)).
        rewrite (plus_assoc idx (numBytes t1) x).
        intros. erewrite (UIP_dec _ _ (eq_refl _)) in H6; simpl in H6.
        rewrite Heqo1 in H6; destruct p as [ [? ?] ?]; simpl in *; congruence.
      + rewrite Heqo0; simpl; eauto.
      + replace (8 * snd (fst p)) with (length_ByteString t1 + 8 * idx); try omega.
        rewrite length_ByteString_no_padding by eauto.
        revert p Heqo1 H6.
        rewrite H5.
        rewrite <- x2; simpl; clear.
        rewrite Vector_append_assoc with (H := sym_eq (plus_assoc idx (numBytes t1) x)), <- Vector_split_append.
        generalize v' (eq_sym (plus_assoc idx (numBytes t1) x)).
        rewrite (plus_assoc idx (numBytes t1) x).
        intros. erewrite (UIP_dec _ _ (eq_refl _)) in H6; simpl in H6.
        rewrite Heqo1 in H6; destruct p as [ [? ?] ?]; simpl in *; injections.
        omega.
      - specialize (H env s idx);
        unfold sequence_Encode in *;
        destruct (encode1 s env) as [ [t1 env''] | ] eqn: ? ;
        simpl in *; [ | intros; try discriminate];
        simpl; destruct (encode2 s env'') as [ [t2 env'''] | ] eqn: ? ; simpl in *;
          try (intros; discriminate); injections.
        pose proof (proj1 H _ _ (eq_refl _) (encode1_OK _ _ (eq_refl _))).
        rewrite padding_ByteString_enqueue_aligned_ByteString in H2 by eauto.
        unfold AppendAlignedEncodeM; destruct (encode1_aligned numBytes' v idx s env) eqn: ? ;
          simpl; eauto.
        destruct (le_lt_dec (8 + 8 * numBytes')
                            (length_ByteString t1 + 8 * idx)).
        { eauto; simpl in l; eapply (proj1 (proj2 H)) in l; eauto; rewrite l in Heqo1; discriminate. }
        rewrite length_ByteString_no_padding in l by eauto.
        pose proof (proj1 (proj2 (proj2 (H0 env'' s (snd (fst p)))))) as H'.
        assert (numBytes t1 + idx < Datatypes.S numBytes')%nat by omega; clear l.
        assert (idx + numBytes t1 <= numBytes')%nat by omega.
        destruct (Vector_split_lt _ _ H4 v) as [? [? [? [? ?] ] ] ].
        pose proof (proj2 (proj2 (H))) as H'' .
        destruct (H1 (fst (Vector_split _ _ x0)) (snd (Vector_split _ _ x0)) _ x1) as [v' [? ?] ].
        erewrite <- H'; f_equal; clear H'; eauto.
        * revert p Heqo1 H6.
          rewrite H5.
          rewrite <- x2; simpl; clear.
          rewrite Vector_append_assoc with (H := sym_eq (plus_assoc idx (numBytes t1) x)), <- Vector_split_append.
          generalize v' (eq_sym (plus_assoc idx (numBytes t1) x)).
          rewrite (plus_assoc idx (numBytes t1) x).
          intros. erewrite (UIP_dec _ _ (eq_refl _)) in H6; simpl in H6.
          rewrite Heqo1 in H6; destruct p as [ [? ?] ?]; simpl in *; try congruence.
      - specialize (H env s idx);
        unfold sequence_Encode in *;
        destruct (encode1 s env) as [ [t1 env''] | ] eqn: ? ; simpl in *.
        + destruct (encode2 s env'') as [ [t2 env'''] | ] eqn: ? ; simpl in *;
             try discriminate.
          unfold AppendAlignedEncodeM.
          destruct (Nat.le_decidable (8 + 8 * numBytes') (length_ByteString t1 + 8 * idx)).
          erewrite (proj1 (proj2 H)); eauto.
          destruct (PeanoNat.Nat.eq_dec (padding t1) 0).
          unfold length_ByteString in H2; rewrite e in H2; simpl in H2.
          assert (exists m, numBytes' = idx + (numBytes t1 + m)).
          exists (numBytes' - (idx + numBytes t1)).
          omega.
          destruct H3.
          pose proof (proj1 H _ _ (eq_refl _) (encode1_OK _ _ (eq_refl _))) as H'.
          destruct (H' (fst (Vector_split _ _ (eq_rect _ _ v _ H3)))
                         (fst (Vector_split _ _ (snd (Vector_split _ _ (eq_rect _ _ v _ H3)))))
                         _
                         (snd (Vector_split _ _ (snd (Vector_split _ _ (eq_rect _ _ v _ H3))))))
            as [v' [? ?] ].
          replace (encode1_aligned _ v idx s env)
            with (Some (eq_rect _ (Vector.t char) v' _ (sym_eq H3), idx + numBytes t1, env'')).
          * simpl; eapply H0; rewrite <- Heqo0; f_equal.
          * generalize v' H3 H4; clear; intros.
            revert v v' H4; rewrite H3; intros; simpl; f_equal.
            unfold ByteBuffer.t in *.
            rewrite <- H4; f_equal.
            rewrite <- !Vector_split_append; reflexivity.
          * erewrite (proj1 (proj2 (proj2 H))); eauto.
        + unfold AppendAlignedEncodeM; rewrite (proj2 (proj2 (proj2 H))); simpl; eauto.
          Grab Existential Variables.
          decide equality.
          decide equality.
          decide equality.
          omega.
          decide equality.
          decide equality.
          omega.
          decide equality.
          omega.
  Qed.

  Definition CorrectAlignedEncoder
             (format : FormatM S ByteString)
             (encoder : forall sz, AlignedEncodeM sz)
    := {encoder' : EncodeM S ByteString &
                   (forall s env,
                       (forall t env', encoder' s env = Some (t, env')
                                       -> refine (format s env) (ret (t, env')))
                       /\ (encoder' s env = None ->
                           forall benv', ~ computes_to (format s env) benv'))
                   /\ (forall s env t env',
                          encoder' s env = Some (t, env')
                       -> padding t = 0)
                   /\ EncodeMEquivAlignedEncodeM encoder' encoder}.

  Lemma CorrectAlignedEncoderForDoneC
    : CorrectAlignedEncoder (fun s e => Return (ByteString_id, e)) AlignedEncode_Nil.
  Proof.
    unfold CorrectAlignedEncoder; intros.
    eexists (fun _ env => Some (ByteString_id, env)); split; [ | split]; intros.
    - split; intros.
      + congruence.
      + congruence.
    - injections; reflexivity.
    - eapply Return_EncodeMEquivAlignedEncodeM.
  Defined.

  (* Lemma CorrectAlignedEncoderForDoneC A
        (format_A : FormatM A ByteString)
        (encode_A : A -> forall sz, AlignedEncodeM sz)
        (encoder_A_OK : CorrectAlignedEncoder format_A encode_A)
    : CorrectAlignedEncoder
        (fun a => format_A a DoneC)
        encode_A.
  Proof.
    unfold CorrectAlignedEncoder; intros.
    destruct encoder_A_OK as [encoder [? [? ?] ] ].
    exists encoder; split; intros; eauto.
    intros; rewrite <- H.
    unfold compose, Bind2.
    setoid_rewrite Monad.refineEquiv_bind_unit; simpl.
    pose proof mempty_right as H'; simpl in H'; setoid_rewrite H'.
    intros v Comp_v; computes_to_inv; subst.
    destruct v; simpl in *; auto.
    computes_to_econstructor; eauto.
  Qed. *)

  Lemma CorrectAlignedEncoderForThenC
        (format_A format_B : FormatM S ByteString)
        (encode_A : forall sz, AlignedEncodeM sz)
        (encode_B : forall sz, AlignedEncodeM sz)
        (encoder_A_OK : CorrectAlignedEncoder format_A encode_A)
        (encoder_B_OK : CorrectAlignedEncoder format_B encode_B)
        (encoder_A_OK' :
           forall (s : S) (env : CacheFormat) (tenv' tenv'' : ByteString * CacheFormat),
            format_B s env ∋ tenv' ->
            format_A s (snd tenv') ∋ tenv'' ->
            exists tenv3 tenv4 : _ * CacheFormat,
              projT1 encoder_B_OK s env = Some tenv3
              /\ format_A s (snd tenv3) ∋ tenv4)
    : CorrectAlignedEncoder
        (format_B ++ format_A)
        (fun sz => AppendAlignedEncodeM (encode_B sz) (encode_A sz)).
  Proof.
    unfold CorrectAlignedEncoder; intros.
    destruct encoder_A_OK as [encoder_A ?], encoder_B_OK as [encoder_B ?]; intuition.
    destruct a0 as [? [? ?] ].
    eexists (sequence_Encode encoder_B encoder_A); split; [ | split];
      intros; simpl in *.
    3: eapply Append_EncodeMEquivAlignedEncodeM.
    4: apply e0.
    4: apply H2.
    3: apply e.
    pose proof (fun H a => CorrectEncoder_sequence format_B format_A encoder_B encoder_A H encoder_A_OK' a).
    destruct H0.
    - unfold CorrectEncoder; split; intros.
      specialize (proj1 (a _ _) _ _ H0); intro.
      unfold refine in H3; eauto.
      specialize (proj2 (a _ _) H0); intro.
      intro.
      eapply H3; eauto.
    - unfold CorrectEncoder; split; intros.
      specialize (proj1 (H _ _) _ _ H0); intro.
      unfold refine in H3; eauto.
      specialize (proj2 (H _ _) H0); intro.
      intro.
      eapply H3; eauto.
    - split; intros.
      + apply H0 in H4.
        intros ? ?; computes_to_inv; subst.
        eauto.
      + destruct benv'.
        eapply H3 in H4.
        eauto.
    - unfold sequence_Format, sequence_Encode, Bind2 in *.
      apply_in_hyp DecodeBindOpt_inv; destruct_ex; split_and.
      symmetry in H4.
      apply_in_hyp DecodeBindOpt_inv; destruct_ex; split_and.
      injections.
      rewrite padding_ByteString_enqueue_aligned_ByteString; eauto.
  Defined.

End AlignedEncodeM.

Lemma refine_CorrectAlignedEncoder
      {S : Type}
      {cache : Cache}
  : forall format format' encode,
    (forall (s : S) (env : CacheFormat),
        refine (format s env) (format' s env)
        /\ ((forall v, ~ computes_to (format' s env) v)
            -> (forall v, ~ computes_to (format s env) v)))
    -> (CorrectAlignedEncoder format' encode)
    -> (CorrectAlignedEncoder format encode).
Proof.
  unfold CorrectAlignedEncoder; intros.
  destruct X as [? [? ?] ]; eexists; intuition eauto.
  rewrite (proj1 (H _ _)); eauto.
  eapply H0; eauto.
  eapply H; eauto.
  intros.
  eapply H0 in H1; eauto.
Defined.

Lemma EncodeMEquivAlignedEncodeM_morphism
      {S : Type}
      {cache : Cache}
  : forall x (encode encode': forall sz : nat, AlignedEncodeM sz),
    (forall sz v idx w c, encode' sz v idx w c = encode sz v idx w c) ->
    EncodeMEquivAlignedEncodeM (S := S) x encode ->
    EncodeMEquivAlignedEncodeM (S := S) x encode'.
Proof.
  unfold EncodeMEquivAlignedEncodeM; intros * Heq Hequiv.
  setoid_rewrite <- Heq in Hequiv.
  assumption.
Qed.

Lemma CorrectAlignedEncoder_morphism
      {S : Type}
      {cache : Cache}
  : forall format format' (encode encode': forall sz : nat, AlignedEncodeM sz),
    (EquivFormat format' format) ->
    (forall sz v idx w c, encode' sz v idx w c = encode sz v idx w c) ->
    CorrectAlignedEncoder (S := S) format encode ->
    CorrectAlignedEncoder (S := S) format' encode'.
Proof.
  unfold CorrectAlignedEncoder; intros.
  destruct X as [? [? ?] ]; eexists; intuition eauto.
  eapply H1 in H2; rewrite <- H2; eapply H.
  eapply H1 in H2; eauto.
  eapply H; eauto.
  eauto using EncodeMEquivAlignedEncodeM_morphism.
Defined.

Lemma CorrectAlignedEncoderThenCAssoc
      {S : Type}
      {cache : Cache}
      (format_A format_B format_C : FormatM S ByteString)
      (encode : forall sz, AlignedEncodeM sz)
  : CorrectAlignedEncoder
      ((format_A ++ format_B) ++ format_C)
      encode
    -> CorrectAlignedEncoder
         (format_A ++ format_B ++ format_C)
         encode.
Proof.
  intros; eapply refine_CorrectAlignedEncoder; eauto.
  unfold sequence_Format, compose; intros.
  unfold Bind2.
  split.
  - repeat setoid_rewrite Monad.refineEquiv_bind_bind.
    setoid_rewrite Monad.refineEquiv_bind_unit; simpl.
    f_equiv; intro.
    simpl; f_equiv; intro.
    simpl; f_equiv; intro.
    rewrite ByteString_enqueue_ByteString_assoc; reflexivity.
  - intros.
    intro; eapply (H v).
    computes_to_inv; repeat computes_to_econstructor; eauto.
    simpl; subst.
    rewrite <- ByteString_enqueue_ByteString_assoc; reflexivity.
Defined.

Corollary Guarded_CorrectAlignedEncoderThenCAssoc
          {S : Type}
          {cache : Cache}
          (format_A format_B format_C : FormatM S ByteString)
          (encode : forall sz, AlignedEncodeM sz)
  : (forall env s bs env', computes_to (format_A s env) (bs, env') ->
                       length_ByteString bs < 8)%nat
    -> CorrectAlignedEncoder
         ((format_A ++ format_B) ++ format_C)
         encode
    -> CorrectAlignedEncoder
         (format_A ++ format_B ++ format_C)
         encode.
Proof.
  intros; eapply CorrectAlignedEncoderThenCAssoc; eauto.
Defined.

Lemma CorrectAlignedEncoderThenCAssoc'
      {S : Type}
      {cache : Cache}
      (format_A format_B format_C : FormatM S ByteString)
      (encode : forall sz, AlignedEncodeM sz)
  : CorrectAlignedEncoder
      (format_A ++ format_B ++ format_C)
      encode
    -> CorrectAlignedEncoder
         ((format_A ++ format_B) ++ format_C)
         encode.
Proof.
  intros; eapply refine_CorrectAlignedEncoder; eauto.
  unfold sequence_Format, compose; intros.
  unfold Bind2.
  split.
  - repeat setoid_rewrite Monad.refineEquiv_bind_bind.
    setoid_rewrite Monad.refineEquiv_bind_unit; simpl; f_equiv; intro.
    simpl; f_equiv; intro.
    simpl; f_equiv; intro.
    rewrite ByteString_enqueue_ByteString_assoc; reflexivity.
  - intros ? ? ?; eapply (H v).
    computes_to_inv; subst; repeat computes_to_econstructor; eauto.
    simpl; subst.
    rewrite  ByteString_enqueue_ByteString_assoc; reflexivity.
Defined.

Definition Format_Source_Intersection
           {A B}
           {cache}
           (format : @FormatM A B cache)
           (predicate : A -> Prop)
  : @FormatM A B cache
  := fun a env benv =>
       predicate a /\
       format a env benv.

Definition CorrectAlignedEncoderFor {S} {cache}
           (format : @FormatM S ByteString cache)
  := {encode : _ & CorrectAlignedEncoder format encode}.

Definition SetCurrentByte (* Sets a single byte at the current index and increments the current index. *)
           {cache : Cache}
           {cacheAddNat : CacheAdd cache nat}
           {n : nat}
  : @AlignedEncodeM cache char n :=
  fun v idx s ce => if (idx <? n) then Some (set_nth' v idx s, Datatypes.S idx, addE ce 8) else None.

Definition Projection_AlignedEncodeM
           {S' S'' : Type}
           {cache : Cache}
           (encode : forall sz, AlignedEncodeM (S := S'') sz)
           (f : S' -> S'')
           (n : nat)
  : AlignedEncodeM (S := S') n :=
  fun v idx s' env =>
    encode n v idx (f s') env.

Lemma CorrectAlignedEncoderProjection
      {S S' : Type}
      {cache : Cache}
      (format_S : FormatM S' ByteString)
      (f : S -> S')
      (encode : forall sz, AlignedEncodeM sz)
  : CorrectAlignedEncoder format_S encode
    -> CorrectAlignedEncoder
         (Projection_Format format_S f)
         (Projection_AlignedEncodeM encode f).
Proof.
  intros H; destruct H as [? [? [? ?] ] ].
  eexists (Basics.compose x f); intuition.
  - intros; intros ? ?.
    eapply H in H3.
    unfold Projection_Format, Compose_Format; apply unfold_computes; eexists; split; eauto.
    apply H2.
  - unfold Projection_Format, Compose_Format in H3.
    rewrite @unfold_computes in H3; destruct_ex; intuition.
    eapply H in H2; eauto.
    subst; eauto.
  - eapply H0.
    unfold Basics.compose in H2; eauto.
  - unfold EncodeMEquivAlignedEncodeM, Basics.compose; intuition.
    + eapply H1; eauto.
    + edestruct H1 as [? [? [? ?] ] ].
      eapply H5; eassumption.
    + edestruct H1 as [? [? [? ?] ] ].
      eapply H6; eassumption.
    + edestruct H1 as [? [? [? ?] ] ].
      eapply H6; eassumption.
Defined.

Definition AlignEncode_Alt
           {S : Type}
           {cache : Cache}
           (encode_T encode_E : forall sz, AlignedEncodeM (S := S) sz)
           sz
  : AlignedEncodeM sz :=
  fun v idx s c => (Ifopt (encode_T sz) v idx s c as a' Then Some a' Else encode_E sz v idx s c).

(*Lemma CorrectAlignedEncoderEither_Both
      {S : Type}
      {cache : Cache}
      (format_T format_E : FormatM S ByteString)
      (encode_T encode_E : forall sz, AlignedEncodeM sz)
  : CorrectAlignedEncoder format_T encode_T
    -> CorrectAlignedEncoder format_E encode_E
    -> CorrectAlignedEncoder
         (composeIf format_T format_E)
         (AlignEncode_Alt encode_T encode_E).
Proof.
  intros.
  destruct X as [? [? [? ?] ] ].
  destruct X0 as [? [? [? ?] ] ].
  eexists (fun s ce => Ifopt x s ce as a' Then
                                          Ifopt x0 s ce as a'' Then (If (Nat.ltb (length_ByteString (fst a')) (length_ByteString (fst a''))) Then Some a' Else Some a'')
                                                               Else Some a' Else x0 s ce); intuition.
  - destruct (x s env) as [ [ [? ?] ? ] | ] eqn: ?; simpl in *.
    destruct (x0 s env) as [ [ [? ?] ? ] | ] eqn: ?; simpl in *.
    destruct (length_ByteString
             {|
             padding := padding;
             front := front;
             paddingOK := paddingOK;
             numBytes := numBytes;
             byteString := byteString |} <?
           length_ByteString
             {|
             padding := padding0;
             front := front0;
             paddingOK := paddingOK0;
             numBytes := numBytes0;
             byteString := byteString0 |}) eqn: ?; simpl in H5.
    + injections; subst.
      unfold composeIf, Union_Format.
      intros ? ?; apply unfold_computes; eexists Fin.F1; simpl; eauto.
      eapply H; eauto.
    + injections; subst;
        unfold composeIf, Union_Format.
      intros ? ?; apply unfold_computes; eexists (Fin.FS Fin.F1); simpl; eauto.
      eapply H2; eauto.
    + injections; subst.
      unfold composeIf, Union_Format.
      intros ? ?; apply unfold_computes; eexists Fin.F1; simpl; eauto.
      eapply H; eauto.
    +  injections; subst;
        unfold composeIf, Union_Format.
      intros ? ?; apply unfold_computes; eexists (Fin.FS Fin.F1); simpl; eauto.
      eapply H2; eauto.
  - destruct (x s env) as [ [ [? ?] ? ] | ] eqn: ?; simpl in *.
    + destruct (x0 s env) as [ [ [? ?] ? ] | ] eqn: ?; simpl in *.
      destruct (length_ByteString
             {|
             padding := padding;
             front := front;
             paddingOK := paddingOK;
             numBytes := numBytes;
             byteString := byteString |} <?
           length_ByteString
             {|
             padding := padding0;
             front := front0;
             paddingOK := paddingOK0;
             numBytes := numBytes0;
             byteString := byteString0 |}) eqn: ?; simpl in H5; try discriminate.
      discriminate.
    + unfold composeIf, Union_Format in H6;
        rewrite unfold_computes in H6.
      destruct_ex.
      revert H6; pattern x1.
      eapply IterateBoundedIndex.Lookup_Iterate_Dep_Type; simpl.
      econstructor; intros.
      eapply H in Heqo; eauto.
      econstructor; intros.
      eapply H2 in H5; eauto.
      constructor.
  - destruct (x s env) as [ [ [? ?] ? ] | ] eqn: ?; simpl in *; try discriminate.
    + destruct (x0 s env) as [ [ [? ?] ? ] | ] eqn: ?; simpl in *.
      * destruct (length_ByteString
                    {|
                      padding := padding;
                      front := front;
                      paddingOK := paddingOK;
                      numBytes := numBytes;
                      byteString := byteString |} <?
                  length_ByteString
                    {|
                      padding := padding0;
                      front := front0;
                      paddingOK := paddingOK0;
                      numBytes := numBytes0;
                      byteString := byteString0 |}) eqn: ?; simpl in H5.
        -- injections.
           eapply H0 in Heqo; simpl in *; eauto.
        -- injections.
           eapply H3 in Heqo0; simpl in *; eauto.
      * injections.
        eapply H0 in Heqo; simpl in *; eauto.
    + eapply H3 in H5; simpl in *; eauto.
  - unfold EncodeMEquivAlignedEncodeM; intros.
    unfold AlignEncode_Alt.
    destruct (x s env) as [ [ [? ?] ? ] | ] eqn: ?.
    + destruct (x0 s env) as [ [ [? ?] ? ] | ] eqn: ?; simpl in *.
      destruct (length_ByteString
                    {|
                      padding := padding;
                      front := front;
                      paddingOK := paddingOK;
                      numBytes := numBytes;
                      byteString := byteString |} <?
                  length_ByteString
                    {|
                      padding := padding0;
                      front := front0;
                      paddingOK := paddingOK0;
                      numBytes := numBytes0;
                      byteString := byteString0 |}) eqn: ?; simpl.
      * unfold EncodeMEquivAlignedEncodeM in *.
          specialize (H1 env s idx); injections.
          simpl If_Opt_Then_Else; intuition eauto.
        -- injections.
           specialize (H5 _ _ Heqo H9 v1 v m v2); simpl in *.
           destruct H5; intuition.
           eexists _; rewrite H7; simpl; split; eauto.
        -- injections.
           specialize (H1 _ _ _ v Heqo H9); simpl in *.
           rewrite H1; simpl.
           specialize (H4 env s idx); eapply (proj1 (proj2 H4)); eauto.
           eapply PeanoNat.Nat.ltb_lt in Heqb.
           Omega.omega.
        -- injections.
           apply H0 in Heqo.
           rewrite Heqo in H9; intuition.
        -- discriminate.
      * unfold EncodeMEquivAlignedEncodeM in *.
          specialize (H4 env s idx); injections.
          simpl If_Opt_Then_Else; intuition eauto.
        -- injections.
           specialize (H5 _ _ Heqo0 H9 v1 v m v2); simpl in *.
           destruct H5; intuition.
           eexists _; rewrite H7; simpl; split; eauto.
        -- injections.
           specialize (H1 _ _ _ v Heqo H9); simpl in *.
           rewrite H1; simpl.
           specialize (H4 env s idx); eapply (proj1 (proj2 H4)); eauto.
           eapply PeanoNat.Nat.ltb_lt in Heqb.
           Omega.omega.
        -- injections.
           apply H0 in Heqo.
           rewrite Heqo in H9; intuition.
        -- discriminate.
    + simpl; specialize (H4 env s idx); specialize (H1 env s idx);
        intuition.
      * rewrite H10; simpl; eauto.
      * rewrite H10; simpl; eauto.
      * rewrite H10; simpl; eauto.
      * rewrite H10; simpl; eauto.
Qed. *)

Lemma CorrectAlignedEncoderEither_E
      {S : Type}
      {cache : Cache}
      (format_T format_E : FormatM S ByteString)
      (encode : forall sz, AlignedEncodeM sz)
      (encode_E_OK : CorrectAlignedEncoder format_E encode)
  : (forall s env, exists (v : ByteString * CacheFormat), projT1 encode_E_OK s env = Some v)
    -> CorrectAlignedEncoder
         (composeIf format_T format_E)
         encode.
Proof.
  intros; eapply refine_CorrectAlignedEncoder; eauto.
  unfold composeIf, Union_Format; split; intros.
  - intros ? ?; apply unfold_computes; eexists (Fin.FS Fin.F1); simpl; eauto.
  - intros ? ;
      specialize (H s env); destruct_ex.
    apply (H0 x); eauto.
    destruct x.
    apply (proj1 (projT2 encode_E_OK)) in H; eapply H.
    eauto.
Defined.

Lemma CorrectAlignedEncoderEither_T
      {S : Type}
      {cache : Cache}
      (format_T format_E : FormatM S ByteString)
      (encode : forall sz, AlignedEncodeM sz)
      (encode_T_OK : CorrectAlignedEncoder format_T encode)
  : (forall s env, exists (v : ByteString * CacheFormat), projT1 encode_T_OK s env = Some v)
    -> CorrectAlignedEncoder
         (composeIf format_T format_E)
         encode.
Proof.
  intros; eapply refine_CorrectAlignedEncoder; eauto.
  unfold composeIf, Union_Format; split; intros.
  - intros ? ?; apply unfold_computes; eexists Fin.F1; simpl; eauto.
  - intros ? ;
      specialize (H s env); destruct_ex.
    apply (H0 x); eauto.
    destruct x.
    apply (proj1 (projT2 encode_T_OK)) in H; eapply H.
    eauto.
Defined.

Definition SetByteAt (* Sets the bytes at the specified index and sets the current index
                        to the following position. *)
           {cache : Cache}
           {cacheAddNat : CacheAdd cache nat}
           {n : nat}
           (idx' : nat)
  : AlignedEncodeM n :=
  fun v idx s ce => if (Coq.Init.Nat.ltb idx' n) then Some (set_nth' v idx' s, Datatypes.S idx', addE ce 8) else None.

Delimit Scope AlignedEncodeM_scope with AlignedEncodeM.
Notation "y >> z" := (AppendAlignedEncodeM y z) : AlignedEncodeM_scope.
