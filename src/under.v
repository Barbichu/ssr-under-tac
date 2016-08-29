From mathcomp Require Import ssrmatching ssreflect.

(* Without this line, doesn't compile with Coq 8.5... (issue with ssrpattern) *)
Declare ML Module "ssreflect".

Set Implicit Arguments.
Unset Strict Implicit.
Unset Printing Implicit Defensive.

(* Erik Martin-Dorel, 2016 *)

(** * Tactic for rewriting under lambdas in MathComp *)

(** ** Preliminary tactics *)

Ltac clear_all h :=
  try unfold h in * |- *; try clear h.

Ltac clear_all3 h1 h2 h3 :=
  clear_all h1; clear_all h2; clear_all h3.

(** [do_pad_tac lem tac] pads lem with [_]s, as Ltac does not handle implicits *)
Ltac do_pad_tac lem tac :=
  match type of lem with
  | forall x1 : ?A, forall x2 : _, forall p : _, _ =>
    (* idtac A; *)
    let a := fresh "_evar_a_" in
    evar (a : A);
    let lem' := eval unfold a in (lem a) in
    do_pad_tac lem' tac; clear_all a
    | forall x2 : _, forall p : _, _ => tac lem
    | _ => fail 100 "expecting a lemma whose type ends with a function and a side-condition."
               "Cannot proceed with:" lem
    end.

Ltac do_sides_tac equ taclr :=
  match type of equ with
  | forall p : _, ?a = ?b =>
    taclr a b
  | ?a = ?b =>
    taclr a b
  end.

(** [pretty_rename term i] is a convenience tactic that tries to
rename the index of [term] to [i], e.g. if [term] is a bigop expr. *)
Ltac pretty_rename term i :=
  rewrite -?[term]/(_ (fun i => _))
          -?[term]/(_ _ (fun i => _))
          -?[term]/(_ _ _ (fun i => _))
          -?[term]/(_ _ _ _ (fun i => _))
          -?[term]/(_ _ _ _ _ (fun i => _))
          -?[term]/(_ _ _ _ _ _ (fun i => _))
          -?[term]/(_ _ _ _ _ _ _ (fun i => _))
          -?[term]/(_ _ _ _ _ _ _ _ (fun i => _))
          -?[term]/(_ _ _ _ _ _ _ _ _ (fun i => _)).

(** [rew_tac pat x2 equ] uses [equ] to rewrite occurrences of [pat]
and uses [x2] to avoid "evars leaking".
Last argument [i] is used by [pretty_rename]. *)
Ltac rew_tac pat x2 equ i :=
  (ssrpattern pat
   || fail 100 "the specified pattern does not match any subterm of the goal");
  let top := fresh in move=> top;
  do_sides_tac
    equ
    ltac:(fun lhs rhs =>
            let top' := eval unfold top in top in
            let lhs' := eval unfold x2 in lhs in
            let rhs' := eval unfold x2 in rhs in
            unify top' lhs' with typeclass_instances;
            rewrite [top]equ; pretty_rename rhs' i);
  clear_all top.

Ltac do_pat pat tac :=
  match goal with
  | |- context [?x] =>
    unify pat x with typeclass_instances;
    tac x
  end.

(** [rew_tac1] is similar to [rew_tac] but ignores the [pat] variable.
Instead, it uses [equ] to rewrite the first occurrence of [equ]'s lhs.
Last argument [i] is used by [pretty_rename]. *)
Ltac rew_tac1 pat x2 equ i :=
  (* rewrite equ. (* causes some evars leaking *) *)
  (* rewrite -> equ. (* could be possible also *) *)
  do_sides_tac
    equ
    ltac:(fun lhs rhs =>
            let lhs' := eval unfold x2 in lhs in
            let rhs' := eval unfold x2 in rhs in
            do_pat
              lhs'
              ltac:(fun x =>
                let top := fresh in set top := x;
                rewrite [top]equ; pretty_rename rhs' i; clear_all top)).

(** ** The main tactic *)
Ltac under_tac rew pat lem i intro_tac tac :=
  do_pad_tac
    lem
    ltac:(fun l =>
            let I := fresh "_evar_I_" in
            let R := fresh "_evar_R_" in
            let x2 := fresh "_evar_x2_" in
            evar (I : Type);
            evar (R : Type);
            evar (x2 : I -> R);
            let lx2 := constr:(l x2) in
            (rew pat x2 lx2 i
             || fail 100 "the lhs of" lx2 "does not match any subterm of the goal");
            [clear_all3 x2 R I
            |(intro_tac || fail 100 "under lemma" lem "we cannot introduce"
                                   "the identifier(s) you specified."
                                   "Maybe some identifier is already used.");
             (tac || fail 100 "cannot apply tactic under lemma" lem);
             clear_all3 x2 R I; try done]).

(** ** The under tacticals, upto 3 vars to introduce in the context *)

(** *** with no ssr pattern argument *)

(** the tactic will rewrite [lem] (then apply [tac]) at the first term
matching [lem]'s lhs *)

Tactic Notation "under"
       open_constr(lem) simple_intropattern(i) tactic(tac) :=
  under_tac rew_tac1 false lem i ltac:(move=> i) tac.

Tactic Notation "under"
       open_constr(lem) "[" simple_intropattern(i) "]" tactic(tac) :=
  under_tac rew_tac1 false lem i ltac:(move=> i) tac.

Tactic Notation "under"
       open_constr(lem) "[" simple_intropattern(i) simple_intropattern(j) "]" tactic(tac) :=
  under_tac rew_tac1 false lem i ltac:(move=> i j) tac.

Tactic Notation "under"
       open_constr(lem) "[" simple_intropattern(i) simple_intropattern(j) simple_intropattern(k) "]" tactic(tac) :=
  under_tac rew_tac1 false lem i ltac:(move=> i j k) tac.

(* Note: these definitions must come first, before the tacticals
involving a ssrpatternarg *)

(** *** with a ssr pattern argument *)

(** all occurrences matching [pat] will be rewritten using [lem] then [tac] *)

Tactic Notation "under"
       ssrpatternarg(pat) open_constr(lem) simple_intropattern(i) tactic(tac) :=
  under_tac rew_tac pat lem i ltac:(move=> i) tac.

(* Given the tactic grammar, we need to write "["..."]" below, else
the into_pattern would lead to unwanted case analysis. *)
Tactic Notation "under"
       ssrpatternarg(pat) open_constr(lem) "[" simple_intropattern(i) "]" tactic(tac) :=
  under_tac rew_tac pat lem i ltac:(move=> i) tac.

Tactic Notation "under"
       ssrpatternarg(pat) open_constr(lem) "[" simple_intropattern(i) simple_intropattern(j) "]" tactic(tac) :=
  under_tac rew_tac pat lem i ltac:(move=> i j) tac.

Tactic Notation "under"
       ssrpatternarg(pat) open_constr(lem) "[" simple_intropattern(i) simple_intropattern(j) simple_intropattern(k) "]" tactic(tac) :=
  under_tac rew_tac pat lem i ltac:(move=> i j k) tac.

(** * Examples and tests *)

From mathcomp Require Import ssrbool ssrfun eqtype ssrnat seq.
From mathcomp Require Import div choice fintype tuple finfun bigop.
From mathcomp Require Import prime binomial ssralg finset matrix.

(** ** Additional lemma for [matrix] *)

Lemma eq_mx R m n (k : unit) (F1 F2 : 'I_m -> 'I_n -> R) : (F1 =2 F2) ->
  (\matrix[k]_(i, j) F1 i j)%R = (\matrix[k]_(i, j) F2 i j)%R.
Proof. by move=> Heq2; apply/matrixP => i j; rewrite !mxE Heq2. Qed.
Arguments eq_mx [R m n k F1] F2 _.

(** ** Additional lemma for [finset] *)

Lemma eq_set (T : finType) (P1 P2 : pred T) :
  P1 =1 P2 -> [set x | P1 x] = [set x | P2 x].
Proof. by move=> H; apply/setP => x; rewrite !inE H. Qed.

Section Tests.

(* A test with a ssr pattern arg *)
Let test_ssrpat (n : nat) (R : ringType) (f1 f2 g : nat -> R) :
  (\big[+%R/0%R]_(i < n) ((f1 i + f2 i) * g i) +
  \big[+%R/0%R]_(i < n) ((f1 i + f2 i) * g i) =
  \big[+%R/0%R]_(i < n) ((f1 i + f2 i) * g i) +
  \big[+%R/0%R]_(i < n) (f1 i * g i) + \big[+%R/0%R]_(i < n) (f2 i * g i))%R.
Proof.
under eq_bigr x rewrite GRing.mulrDl.
(* 3 occurrences are rewritten; the bigop variable becomes "x" *)

Undo 1.
Local Open Scope ring_scope.

under [X in _ + X = _] eq_bigr x rewrite GRing.mulrDl.

rewrite big_split /=.
by rewrite GRing.addrA.
Qed.

(* A test with a side-condition. *)
Let test_sc (n : nat) (R : fieldType) (f : nat -> R) :
  (forall k : 'I_n, 0%R != f k) ->
  (\big[+%R/0%R]_(k < n) (f k / f k) = n%:R)%R.
Proof.
move=> Hneq0.
do [under eq_bigr ? rewrite GRing.divff]; last first.
by rewrite eq_sym.

rewrite big_const cardT /= size_enum_ord /GRing.natmul.
case: {Hneq0} n =>// n.
by rewrite iteropS iterSr GRing.addr0.
Qed.

(* A test lemma for [under eq_bigr in] *)
Let test_rin (n : nat) (R : fieldType) (f : nat -> R) :
  (forall k : 'I_n, f k != 0%R) ->
  (\big[+%R/0%R]_(k < n) (f k / f k) = n%:R)%R -> True.
Proof.
move=> Hneq0 H.
do [under eq_bigr ? rewrite GRing.divff] in H.
done.
Qed.

(* A test lemma for [under eq_bigr under eq_bigl] *)
Let test_rl (A : finType) (n : nat) (F : A -> nat) :
  \big[addn/O]_(0 <= k < n)
  \big[addn/O]_(J in {set A} | #|J :&: [set: A]| == k)
  \big[addn/O]_(j in J) F j >= 0.
Proof.
under eq_bigr k under eq_bigl J rewrite setIT. (* the bigop variables are kept *)
done.
Qed.

(* A test lemma for [under eq_bigl in] *)
Let test_lin (A : finType) (n : nat) (F : A -> nat) :
  \big[addn/O]_(J in {set A} | #|J :&: [set: A]| == 1%N)
  \big[addn/O]_(j in J) F j = \big[addn/O]_(j in A) F j -> True.
Proof.
move=> H.
do [under eq_bigl J rewrite setIT] in H. (* the bigop variable "J" is kept *)
done.
Qed.

(* A test lemma for matrices *)
Let test_addmxC (T : zmodType) (m n : nat) (A B : 'M[T]_(m, n)) :
  (A + B = B + A)%R.
Proof. by under eq_mx [? ?] rewrite GRing.addrC. Qed.

(* A test lemma for sets *)
Let test_setIC (T : finType) (A B : {set T}) : A :&: B = B :&: A.
Proof. by under eq_set ? rewrite andbC. Qed.

(* A test with several side-conditions *)
Let test_sc2 (n : nat) :
  \big[addn/O]_(i < n.+1) (n - i)%N = \big[addn/O]_(j < n.+1) j.
Proof.
rewrite (reindex (fun i : 'I_n.+1 => inord (n - i))); last first.
  apply/onW_bij/inv_bij=> -[i Hi]; rewrite inordK ?ltnS ?leq_subr // subKn //.
  by rewrite inord_val.
by under eq_bigr i rewrite inordK ?ltnS ?leq_subr // subKn; case: i.
Qed.

End Tests.
