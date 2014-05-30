Require Export Common Computation ADTNotation.ilist.

(** Type of a constructor. *)
Definition constructorType (rep dom : Type)
  :=  dom (* Initialization arguments *)
     -> Comp rep (* Freshly constructed model *).

(** Type of a method. *)
Definition methodType (rep dom cod : Type)
  := rep    (* Initial model *)
     -> dom (* Method arguments *)
     -> Comp (rep * cod) (* Final model and return value. *).

(* Signatures of ADT operations *)
Record ADTSig :=
  {
     (** The index set of constructors *)
    ConstructorIndex : Type;

    (** The index set of methods *)
    MethodIndex : Type;

    ConstructorDom : ConstructorIndex -> Type;
    (** The representation-independent domain of constructors. **)

    MethodDomCod : MethodIndex -> (Type * Type)
     (** The representation-independent domain and codomain of methods. **)

  }.
