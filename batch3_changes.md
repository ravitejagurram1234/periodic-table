# EOS Quark Engine — Batch 3 Changes
**Theme: Compartiment & anchor resolution**

_Generated directly from the working-copy file. Whole-file copy-paste._

## Findings fixed in this batch
| # | Sev | Issue | .NET reference |
|---|---|---|---|
| 2 | CRITICAL | `TaskAnchor.getBlocInfo` was a stub returning an empty `DBlocInfo` → every INCORPORATE / GENERATE_AND_INCORPORATE render (and dynamic-report anchor lookup) threw "Anchor not found" | Task_Base.cs:177 `Run.Gabarit.XML.GetBlocInfo(boxName)`; Task_Anchor.cs:95-98 (throw only on missing UID) |

## What changed
`TaskAnchor.getBlocInfo(blocName)` no longer returns `new DBlocInfo()` (uid=""). It now delegates to the parent run's gabarit XML — `getRun().getGabarit().getQxpXml().getBlocInfo(blocName)` — exactly as .NET `Task_Base.Get_Bloc_Info` does. A defensive null-guard throws a diagnosable `IllegalStateException` (naming the box + task) if the gabarit was never loaded, instead of a bare NPE.

## Why this is now correct (depends on Batch 1)
This fix is only meaningful because **Batch 1** made `Run.prepareGabarit` load the full gabarit XML before Process. With that in place, `getQxpXml().getBlocInfo(...)` returns a real UID, so `getAnchorInfo`'s existing `isBlank()` check throws **only** when the box genuinely doesn't exist — faithfully reproducing .NET's `MSG_Ancre_Introuvable`.

## Safety notes
- **No subclass override needed** — the delegation is generic; `TaskCompartiment` and `TaskDynamique` inherit it. (Verified: no class overrides `getBlocInfo`.)
- **Identical chain already in use** at `DidTaskPostProcessStrategy.java:68` and `TaskBase.java:57-58,73`, so this is a proven pattern, not a new one.
- `DocumentDomain.getQxpXml()` returns `QxpXml.EMPTY` (never null) when XML is unset, so an unloaded gabarit yields a blank-UID lookup → "Anchor not found", matching .NET (empty XML → no UID → throw). The null-guard only fires for a genuinely absent run/gabarit object.
- **No callers changed** — `getAnchorInfo`, `getStartAnchor`/`getEndAnchor`, `getNbAnciennePage`, and the Compartiment/Dynamique strategies are untouched. No test references the old stub.

## Note on the original plan
The original Batch 3 also included **C4** ("addRunBlocs reads the template instead of the generated QXP"). Phase 0 **withdrew** C4 as a false positive (the child run's gabarit `DocumentDomain` is mutated in place to the post-step SaveAs output that render reads back), so `CompartimentTaskProcessStrategy` is **not** changed. Batch 3 is therefore this single fix.

---

## `domain/task/TaskAnchor.java` — CHANGED
```java
package com.socgen.sgs.api.quark.engine.domain.task;

import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DBlocInfo;
import com.socgen.sgs.api.quark.engine.enums.SubTaskTypeEnum;
import lombok.Setter;

/** Abstract base for tasks that manipulate start/end anchors in the document. */
@Setter
public abstract class TaskAnchor extends TaskBase {

    private static final String START_ANCHOR_PATTERN = "%s_START";
    private static final String END_ANCHOR_PATTERN   = "%s_END";

    private DBlocInfo startAnchor;
    private DBlocInfo endAnchor;

    protected TaskAnchor(int id, Run run) {
        super(id, run);
        this.setSubTaskType(SubTaskTypeEnum.FILE_QXP_DATA);
    }

    /** Returns the anchor bloc name (start or end) derived from the destinationBlocName. */
    public String getAnchorName(boolean start) {
        String pattern = start ? START_ANCHOR_PATTERN : END_ANCHOR_PATTERN;
        return String.format(pattern, this.getDestinationBlocName());
    }

    /**
     * Fetches anchor info for the given anchor name via getBlocInfo.
     * Throws IllegalStateException if the anchor UID is not found in the document.
     */
    public DBlocInfo getAnchorInfo(boolean start) {
        String anchorName  = this.getAnchorName(start);
        DBlocInfo dblocInfo = this.getBlocInfo(anchorName);

        if (dblocInfo == null || dblocInfo.getUid() == null || dblocInfo.getUid().isBlank()) {
            throw new IllegalStateException("Anchor not found in document: " + anchorName);
        }
        return dblocInfo;
    }

    /**
     * Resolves bloc info for the given box name from the parent run's gabarit XML.
     * Parity: .NET Task_Base.Get_Bloc_Info → {@code this.Run.Gabarit.XML.GetBlocInfo(boxName)}
     * (Task_Base.cs:177). The gabarit XML is populated during Run.prepareGabarit (see Batch 1),
     * so a real UID is returned here; {@link #getAnchorInfo(boolean)} then throws only when the
     * lookup yields no UID — matching .NET's "Ancre Introuvable" behaviour (Task_Anchor.cs:95-98).
     */
    protected DBlocInfo getBlocInfo(String blocName) {
        if (this.getRun() == null || this.getRun().getGabarit() == null
                || this.getRun().getGabarit().getQxpXml() == null) {
            throw new IllegalStateException(
                    "Gabarit XML is not loaded; cannot resolve bloc '" + blocName
                            + "' for task " + this.getId()
                            + " — Run.prepareGabarit must run before anchor resolution");
        }
        return this.getRun().getGabarit().getQxpXml().getBlocInfo(blocName);
    }

    /** Evaluates pageNum and layoutName from the start anchor — resolved via gabarit XML in the business layer. */
    @Override
    public void evaluateInfo() {
        // pageNum and layoutName are set by the business layer using getAnchorName(true)
    }

    @Override
    public void resetProcess() {
        super.resetProcess();
        this.startAnchor = null;
        this.endAnchor   = null;
    }

    /** Lazily loads and returns the start anchor info. */
    public DBlocInfo getStartAnchor() {
        if (this.startAnchor == null) {
            this.startAnchor = this.getAnchorInfo(true);
        }
        return this.startAnchor;
    }

    /** Lazily loads and returns the end anchor info. */
    public DBlocInfo getEndAnchor() {
        if (this.endAnchor == null) {
            this.endAnchor = this.getAnchorInfo(false);
        }
        return this.endAnchor;
    }

    /** Returns the number of existing pages between the two anchors. */
    public int getNbAnciennePage() {
        return this.getEndAnchor().getPage() - this.getStartAnchor().getPage() + 1;
    }
}
```

---

## Apply checklist
- [ ] Replace `domain/task/TaskAnchor.java`
- [ ] `mvn compile`
- [ ] `mvn test` (no test references the old stub; run the suite to confirm no regression in Compartiment/Dynamique tests)
