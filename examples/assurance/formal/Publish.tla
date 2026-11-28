------------------------------ MODULE Publish ------------------------------
(* A fictional approval/publication state machine (docs/assurance/formal-methods.md).
   Each action is one atomic step of a shared store; steps of different actors
   interleave. Publishers check an artifact first and publish it in a later step,
   so an approver can revoke the approval in between.
   RecheckOnPublish = FALSE is the defective version: the publish step trusts the
   earlier check. RecheckOnPublish = TRUE re-reads the state in the publish step. *)
EXTENDS TLC

CONSTANTS Artifacts,        \* finite set of artifact ids, e.g. {"a1", "a2"}
          Publishers,       \* finite set of publisher ids, e.g. {"p1", "p2"}
          RecheckOnPublish  \* BOOLEAN

None == "none"

VARIABLES verified,   \* verified[a]: the current content of a passed verification
          approved,   \* approved[a]: an approval of the current content is in force
          published,  \* published[a]: the current content is publicly available
          pending     \* pending[p]: artifact p checked and will publish next, or None

vars == <<verified, approved, published, pending>>

TypeOK ==
    /\ verified \in [Artifacts -> BOOLEAN]
    /\ approved \in [Artifacts -> BOOLEAN]
    /\ published \in [Artifacts -> BOOLEAN]
    /\ pending \in [Publishers -> Artifacts \cup {None}]

Init ==
    /\ verified = [a \in Artifacts |-> FALSE]
    /\ approved = [a \in Artifacts |-> FALSE]
    /\ published = [a \in Artifacts |-> FALSE]
    /\ pending = [p \in Publishers |-> None]

Verify(a) ==
    /\ ~verified[a]
    /\ verified' = [verified EXCEPT ![a] = TRUE]
    /\ UNCHANGED <<approved, published, pending>>

Approve(a) ==
    /\ verified[a] /\ ~approved[a]
    /\ approved' = [approved EXCEPT ![a] = TRUE]
    /\ UNCHANGED <<verified, published, pending>>

\* Revoking an approval also withdraws the publication in the same step.
Revoke(a) ==
    /\ approved[a]
    /\ approved' = [approved EXCEPT ![a] = FALSE]
    /\ published' = [published EXCEPT ![a] = FALSE]
    /\ UNCHANGED <<verified, pending>>

\* New content invalidates verification and approval, and withdraws the old content.
Modify(a) ==
    /\ verified' = [verified EXCEPT ![a] = FALSE]
    /\ approved' = [approved EXCEPT ![a] = FALSE]
    /\ published' = [published EXCEPT ![a] = FALSE]
    /\ UNCHANGED pending

Check(p, a) ==
    /\ pending[p] = None
    /\ verified[a] /\ approved[a] /\ ~published[a]
    /\ pending' = [pending EXCEPT ![p] = a]
    /\ UNCHANGED <<verified, approved, published>>

Publish(p) ==
    LET a == pending[p] IN
    /\ a # None
    /\ IF RecheckOnPublish /\ ~(verified[a] /\ approved[a])
           THEN UNCHANGED published               \* refuse: state changed since Check
           ELSE published' = [published EXCEPT ![a] = TRUE]
    /\ pending' = [pending EXCEPT ![p] = None]
    /\ UNCHANGED <<verified, approved>>

\* Fault model: a publisher crashes between Check and Publish and restarts
\* without its in-memory pending artifact. The store itself does not fail.
Crash(p) ==
    /\ pending[p] # None
    /\ pending' = [pending EXCEPT ![p] = None]
    /\ UNCHANGED <<verified, approved, published>>

Next ==
    \/ \E a \in Artifacts : Verify(a) \/ Approve(a) \/ Revoke(a) \/ Modify(a)
    \/ \E p \in Publishers : Publish(p) \/ Crash(p)
    \/ \E p \in Publishers, a \in Artifacts : Check(p, a)

Spec == Init /\ [][Next]_vars

\* The property: only verified artifacts whose approval is in force are published.
SafePublish == \A a \in Artifacts : published[a] => (verified[a] /\ approved[a])

=============================================================================
