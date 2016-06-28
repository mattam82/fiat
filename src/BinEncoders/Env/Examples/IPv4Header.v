Require Import
        Coq.Strings.String
        Coq.Vectors.Vector.

Require Import
        Fiat.Common.SumType
        Fiat.Common.EnumType
        Fiat.Common.BoundedLookup
        Fiat.Common.ilist
        Fiat.Computation
        Fiat.QueryStructure.Specification.Representation.Notations
        Fiat.QueryStructure.Specification.Representation.Heading
        Fiat.QueryStructure.Specification.Representation.Tuple
        Fiat.BinEncoders.Env.BinLib.Core
        Fiat.BinEncoders.Env.Common.Specs
        Fiat.BinEncoders.Env.Common.WordFacts
        Fiat.BinEncoders.Env.Common.ComposeCheckSum
        Fiat.BinEncoders.Env.Common.ComposeIf
        Fiat.BinEncoders.Env.Common.ComposeOpt
        Fiat.BinEncoders.Env.Automation.SolverOpt
        Fiat.BinEncoders.Env.Lib2.FixListOpt
        Fiat.BinEncoders.Env.Lib2.NoCache
        Fiat.BinEncoders.Env.Lib2.WordOpt
        Fiat.BinEncoders.Env.Lib2.Bool
        Fiat.BinEncoders.Env.Lib2.NatOpt
        Fiat.BinEncoders.Env.Lib2.Vector
        Fiat.BinEncoders.Env.Lib2.EnumOpt
        Fiat.BinEncoders.Env.Lib2.SumTypeOpt.

Require Import Bedrock.Word.

Import Vectors.VectorDef.VectorNotations.
Open Scope string_scope.
Open Scope Tuple_scope.

(* Start Example Derivation. *)

Definition IPv4_Packet :=
  @Tuple <"ID" :: word 16,
          "DF" :: bool, (* Don't fragment flag *)
          "MF" :: bool, (*  Multiple fragments flag *)
          "FragmentOffset" :: word 13,
          "TTL" :: char,
          "Protocol" :: EnumType ["ICMP"; "TCP"; "UDP"],
          (* So many to choose from: http://www.iana.org/assignments/protocol-numbers/protocol-numbers.xhtml*)
          "SourceAddress" :: word 32,
          "DestAddress" :: word 32,
          "Options" :: list (word 32)>.

Definition ProtocolTypeCodes : Vector.t (word 16) 3 :=
  [WO~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~1;
   WO~0~0~0~0~0~0~0~0~0~0~0~0~0~1~1~0;
   WO~0~0~0~0~0~0~0~0~0~0~0~1~0~0~0~1
  ].

Variable IPChecksum : ByteString -> ByteString.

Definition transformer : Transformer ByteString := ByteStringTransformer.

Definition encode_IPv4_Packet_Spec (ip4 : IPv4_Packet)  :=
          (encode_word_Spec (natToWord 4 4)
    ThenC encode_nat_Spec 4 (5 + |ip4!"Options"|)
    ThenC encode_unused_word_Spec 8 (* TOS Field! *)
    ThenC (fun ctx => payload_len <- {payload_len : nat | lt (20 + (4 * |ip4!"Options"|) + payload_len) (pow2 16)};
             encode_nat_Spec 16 (20 + (4 * |ip4!"Options"|) + payload_len) ctx) (* payload length is an argument *)
    ThenC encode_word_Spec ip4!"ID"
    ThenC encode_unused_word_Spec 1 (* Unused flag! *)
    ThenC encode_bool_Spec ip4!"DF"
    ThenC encode_bool_Spec ip4!"MF"
    ThenC encode_word_Spec ip4!"FragmentOffset"
    ThenC encode_word_Spec ip4!"TTL"
    ThenC encode_enum_Spec ProtocolTypeCodes ip4!"Protocol"
    DoneC)
    ThenChecksum IPChecksum
    ThenCarryOn (encode_word_Spec ip4!"SourceAddress"
    ThenC encode_word_Spec ip4!"DestAddress"
    ThenC encode_list_Spec encode_word_Spec ip4!"Options"
    DoneC).

Definition IPv4_Packet_OK (ipv4 : IPv4_Packet) :=
  lt (|ipv4!"Options"|) 11.

Variable IPChecksum_Valid : nat -> ByteString -> Prop.
Variable IPChecksum_Valid_dec : forall n b, {IPChecksum_Valid n b} + {~IPChecksum_Valid n b}.
Variable decodeChecksum : ByteString -> CacheDecode -> option (() * ByteString * CacheDecode).

Variable IPChecksum_OK : forall b ext : ByteString, IPChecksum_Valid (bin_measure (transform b (IPChecksum b))) (transform (transform b (IPChecksum b)) ext).

Variable IPChecksum_commute : forall b b' : ByteString, IPChecksum (transform b b') = IPChecksum (transform b' b).

Variable IPChecksum_Valid_commute :
  forall b b' ext : ByteString,
    IPChecksum_Valid (bin_measure (transform b b')) (transform (transform b b') ext) <-> IPChecksum_Valid (bin_measure (transform b' b)) (transform (transform b' b) ext).

Variable IPv4_Packet_encoded_measure  : ByteString -> nat.

Lemma IPv4_Packet_encoded_measure_OK :
  forall (a : IPv4_Packet) (ctx ctx' : ()) (b ext : ByteString),
    encode_IPv4_Packet_Spec a ctx ↝ (b, ctx')
    -> length_ByteString b = IPv4_Packet_encoded_measure (ByteString_transformer b ext).
Admitted.

Lemma decodeIPChecksum_pf
  : forall (b b' ext : ByteString) (ctx ctx' ctxD : ()),
    True ->
    decodeChecksum (ByteString_transformer (ByteString_transformer (IPChecksum (ByteString_transformer b b')) b') ext) ctxD = Some ((), ByteString_transformer b' ext, ctxD).
Admitted.

Lemma decodeIPChecksum_pf'
  : forall (u : ()) (b b' : ByteString),
    () -> forall ctxD ctxD' : (), True -> decodeChecksum b ctxD = Some (u, b', ctxD') -> True /\ (exists b'' : ByteString, b = ByteString_transformer b'' b').
Proof.
Admitted.

Transparent pow2.
Arguments pow2 : simpl never.

Definition EthernetHeader_decoder
  : { decodePlusCacheInv |
      exists P_inv,
        (cache_inv_Property (snd decodePlusCacheInv) P_inv
         -> encode_decode_correct_f _ transformer IPv4_Packet_OK (fun _ _ => True)
                                    encode_IPv4_Packet_Spec
                                    (fst decodePlusCacheInv) (snd decodePlusCacheInv))
        /\ cache_inv_Property (snd decodePlusCacheInv) P_inv}.
Proof.
  eexists (_, _); intros; eexists _; split; simpl.
  intros.
  unfold encode_IPv4_Packet_Spec; pose_string_ids.
  eapply (@composeChecksum_encode_correct
              IPv4_Packet _ transformer IPChecksum
              IPChecksum_Valid IPChecksum_Valid_dec
              IPChecksum_OK IPChecksum_commute IPChecksum_Valid_commute _
              (nat * (word 16 * (bool * (bool * (word 13 * (char * EnumType ["ICMP"; "TCP"; "UDP"]))))))
              _ _ _ decodeChecksum H
              (fun ip4 => (|ip4!StringId10|, (ip4!StringId, (ip4!StringId0,
                           (ip4!StringId1, (ip4!StringId2, (ip4!StringId3, ip4!StringId4)))))))
              (IPv4_Packet_OK)
              _ _ _
              (fun data' : nat * (word 16 * (bool * (bool * (word 13 * (char * EnumType ["ICMP"; "TCP"; "UDP"]))))) =>
                 (encode_word_Spec (natToWord 4 4)
                                   ThenC encode_nat_Spec 4 (5 + fst data')
                                   ThenC encode_unused_word_Spec 8 (* TOS Field! *)
                                   ThenC (fun ctx => payload_len <- {payload_len : nat | lt (20 + (4 * (fst data')) + payload_len) (pow2 16)};
             encode_nat_Spec 16 (20 + (4 * (fst data')) + payload_len) ctx)
                                   ThenC encode_word_Spec (fst (snd data'))
                                   ThenC encode_unused_word_Spec 1
                                   ThenC encode_bool_Spec (fst (snd (snd data')))
                                   ThenC encode_bool_Spec (fst (snd (snd (snd data'))))
                                   ThenC encode_word_Spec (fst (snd (snd (snd (snd data')))))
                                   ThenC encode_word_Spec (fst (snd (snd (snd (snd (snd data'))))))
                                   ThenC encode_enum_Spec ProtocolTypeCodes (snd (snd (snd (snd (snd (snd data'))))))
                                   DoneC)));
    simpl.
  intros; eapply IPv4_Packet_encoded_measure_OK; apply H0.
  apply_compose.
  eapply Word_decode_correct.
  solve_data_inv.
  solve_data_inv.
  apply_compose.
  eapply Nat_decode_correct.
  solve_data_inv.
  solve_data_inv.
  unfold encode_unused_word_Spec.
  apply_compose.
  eapply unused_word_decode_correct.
  solve_data_inv.
  solve_data_inv.
  simpl.
  apply_compose.
  eapply Nat_decode_correct.
  solve_data_inv.
  solve_data_inv.
  apply_compose.
  eapply Word_decode_correct.
  solve_data_inv.
  solve_data_inv.
  apply_compose.
  eapply unused_word_decode_correct.
  solve_data_inv.
  solve_data_inv.
  apply_compose.
  eapply bool_decode_correct.
  solve_data_inv.
  solve_data_inv.
  apply_compose.
  eapply bool_decode_correct.
  solve_data_inv.
  solve_data_inv.
  apply_compose.
  eapply Word_decode_correct.
  solve_data_inv.
  solve_data_inv.
  apply_compose.
  eapply Word_decode_correct.
  solve_data_inv.
  solve_data_inv.
  apply_compose.
  eapply Enum_decode_correct.
  Discharge_NoDupVector.
  solve_data_inv.
  solve_data_inv.
  unfold encode_decode_correct_f; intuition eauto.
  instantiate
    (1 := fun p b env => if Compare_dec.le_lt_dec proj 4 then None else _ p b env).
  simpl in *.
  rewrite <- H24; simpl.
  assert (a = proj - 5) by
      (rewrite <- H24; simpl; auto with arith).
  clear H24.
  computes_to_inv; injections; subst; simpl.
  pose proof transform_id_left as H'; simpl in H'; rewrite H'.
  eexists env'; simpl; intuition eauto.
  instantiate (1 := fun proj6 ext env' => Some (proj - 5, (proj1, (proj2, (proj3, (proj4, (proj5, proj6))))), ext, env')).
  simpl; rewrite <- Minus.minus_n_O; reflexivity.
  find_if_inside; try discriminate.
  simpl in H14; injections; eauto.
  simpl in H14; repeat find_if_inside; try discriminate.
  injections.
  simpl.
  eexists _; eexists tt;
    intuition eauto; injections; eauto using idx_ibound_eq;
      try match goal with
            |-  ?data => destruct data;
                           simpl in *; eauto
          end.
  destruct env; computes_to_econstructor.
  pose proof transform_id_left as H'; simpl in H'; rewrite H'.
  reflexivity.
  instantiate (1 := fun _ => True); simpl; eauto.
  revert H1 l payload_OK; clear; intros;
  unfold pow2 in H1; simpl in H1.
  omega.
  revert H1 l; unfold pow2; simpl; intros; omega.
  revert H1 l; unfold pow2; simpl; intros; omega.
  simpl.
  revert H1 l payload_OK; clear; intros;
  unfold pow2 in H1; simpl in H1.
  omega.
  unfold IPv4_Packet_OK; intros; destruct H0; repeat split; eauto.
  simpl.
  unfold StringId10.
  unfold pow2; simpl.
  match goal with
    |- context [length ?x] =>
    revert H0; simpl; remember (length x); clear;
      auto with arith
  end.
  instantiate (1 := fun _ _ => True);
    simpl; intros; exact I.
  intros; eapply decodeIPChecksum_pf; eauto.
  intros; eapply decodeIPChecksum_pf'; eauto.
  apply_compose.
  eapply Word_decode_correct.
  solve_data_inv.
  solve_data_inv.
  apply_compose.
  eapply Word_decode_correct.
  solve_data_inv.
  solve_data_inv.
  apply_compose.
  intro; eapply FixList_decode_correct.
  revert H3; eapply Word_decode_correct.
  simpl in *; split.
  intuition eauto.
  pose proof (f_equal fst H9).
  simpl in H4; apply H4.
  simpl in *; injections.
  simpl; auto with arith.
  eauto.
  simpl; intros; eauto using FixedList_predicate_rest_True.
  simpl; intros;
    unfold encode_decode_correct_f; intuition eauto.
  destruct data as [? [? [? [? [? [? [? [? [? [ ] ] ] ] ] ] ] ] ] ];
    unfold GetAttribute, GetAttributeRaw in *;
    simpl in *.
  pose proof (f_equal fst H14).
  pose proof (f_equal (fun z => fst (snd z)) H14).
  pose proof (f_equal (fun z => fst (snd (snd z))) H14).
  pose proof (f_equal (fun z => fst (snd (snd (snd z)))) H14).
  pose proof (f_equal (fun z => fst (snd (snd (snd (snd z))))) H14).
  pose proof (f_equal (fun z => fst (snd (snd (snd (snd (snd z)))))) H14).
  pose proof (f_equal (fun z => fst (snd (snd (snd (snd (snd (snd z))))))) H14).
  pose proof (f_equal (fun z => snd (snd (snd (snd (snd (snd (snd z))))))) H14).
  simpl in *.
  clear H14.
  computes_to_inv; injections; subst; simpl.
  pose proof transform_id_left as H'; simpl in H'; rewrite H'.
  eexists env'; simpl; intuition eauto.
  simpl in *.
  simpl in H8; injections; eauto.
  simpl in H8; repeat find_if_inside; try discriminate.
  eexists _; eexists tt.
  injections; simpl in *; repeat split.
  destruct env; computes_to_econstructor.
  pose proof transform_id_left as H'; simpl in H'; rewrite H'.
  reflexivity.
  unfold GetAttribute, GetAttributeRaw; simpl.
  rewrite H5; eauto.
  intuition.
  simpl in *.
  unfold pow2 in H9; simpl in H9; auto with arith.
  omega.
  unfold GetAttribute, GetAttributeRaw.
  simpl.
  rewrite H5.
  revert payload_OK H0; clear; simpl.
  intros; destruct H0 as [ [? ?] ?].
  unfold pow2 in H1; simpl in H1.
  omega.
  destruct proj as [? [? [? [? [? [? [? ?] ] ] ] ] ] ].
  simpl.
  unfold GetAttribute, GetAttributeRaw; simpl in *.
  repeat f_equal.
  eauto.
  rewrite H5; simpl.

  apply_compose.
  eapply Enum_decode_correct.
  Discharge_NoDupVector.
  solve_data_inv.
  simpl; intros; exact I.
  simpl; intros.
  unfold encode_decode_correct_f; intuition eauto.
  destruct data as [? [? [? [ ] ] ] ];
    unfold GetAttribute, GetAttributeRaw in *;
    simpl in *.
  computes_to_inv; injections; subst; simpl.
  pose proof transform_id_left as H'; simpl in H'; rewrite H'.
  eexists env'; simpl; intuition eauto.
  match goal with
    |- ?f ?a ?b ?c = ?P =>
    let P' := (eval pattern a, b, c in P) in
    let f' := match P' with ?f a b c => f end in
    try unify f f'; try reflexivity
  end.
  simpl in *; injections; eauto.
  simpl in *; repeat find_if_inside; try discriminate.
  eexists _; eexists tt;
    intuition eauto; injections; eauto using idx_ibound_eq;
      try match goal with
            |-  ?data => destruct data;
                           simpl in *; eauto
          end.
  destruct env; computes_to_econstructor.
  pose proof transform_id_left as H'; simpl in H'; rewrite H'.
  reflexivity.
  repeat (instantiate (1 := fun _ => True)).
  unfold cache_inv_Property; intuition.
  Grab Existential Variables.
  exact (@weq _).
  exact (@weq _).
  exact (@weq _).
  exact (@weq _).
  exact Peano_dec.eq_nat_dec.
Defined.
