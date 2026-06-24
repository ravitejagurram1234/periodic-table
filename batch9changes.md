# EOS Quark Engine — Batch 9 Changes
**Theme: document-task geometry + mode-degrade guards (QXP-only, template-size, null-data)**

_Snippets for large files; whole-file for `LoadTemplatesBusiness`. One HIGH finding (#10) is **deliberately deferred** — see the flag._

## Findings fixed (5) + 1 deferred
| # | Sev | Fix |
|---|---|---|
| 93/30/55 | LOW/MED | New `DocumentDomain.evaluateModeDegrade(limit)` = `QXP && data!=null && len>0 && len>limit` (mirrors .NET `Document.Evaluate_Mode_Degrade`); `Run.prepareGabarit` uses it → adds the missing QXP-type guard **and** removes the null-data NPE. |
| 29 | MEDIUM | `LoadTemplatesBusiness` now degrades the run when the **gabarit_template** is too big (not just the gabarit) — matches `Run_Base.Mode_Degrade` which checks BOTH documents. |
| 56 | MEDIUM | `LoadTemplatesBusiness` now loads templates **only when a TODO dynamic task exists**, and raises a **Bloquante** run error when such a run is missing `id_gabarit_template` (was silently skipped). |
| 17 | HIGH | Removed Java-only per-task `markModeDegradeIfTooBig` — shipped .NET never degrades a task for its reference-doc size (`Task_Base.Mode_Degrade` returns false, never overridden). |
| 15 | HIGH | `DocumentTaskProcessStrategy` builds `TaskImagePosition` **unconditionally** (ctor maps null→DEFAULT), so multi-page PDF pages 2..N get a position even when `POSITION_IMAGE` is NULL. |

## Mode-degrade — the verified .NET truth (this batch hinges on it)
- `Document.Evaluate_Mode_Degrade` = `Type==QXP && IsSet(Data) && Data.Length > limit`.
- `Run_Base.Mode_Degrade` = `(Gabarit != null && Gabarit.Mode_Degrade) || (Gabarit_Template != null && Gabarit_Template.Mode_Degrade)` → the **template** can degrade the run too (#29).
- `Task_Base.Mode_Degrade` returns **false** and is **never** overridden by `Task_Document`/`Task_QXP_Previous` (grep-confirmed) — the code comment claims it should be, but the override was never implemented. So per-task degrade does **not** exist in shipped .NET → Java's `markModeDegradeIfTooBig` was a deviation and is removed (#17).
> Note on #17: `TaskDocument`/`TaskQxpPrevious.isModeDegrade()` still read `document.isModeDegrade()`, which now stays false (nothing sets it) — functionally identical to shipped .NET. If you ever want the .NET *comment's intent* (degrade a task on an oversized **QXP** reference doc), that's a deliberate add-on you can request; it is intentionally NOT done here, to match shipped behavior.

## ⚠️ #10 — DEFERRED (HIGH, narrow scope) — not blind-ported
**What:** the double-page (vis-à-vis) "prepare step" branch in `RunTaskStep.updateBlocPagination`. The Java has a **deliberately simplified stub** (its own comment: *"prepareStep is set during complex double-page handling (simplified here)"*). The .NET (`Run_Task_Step.cs` ~340-470) builds a **prepare sub-step** that inserts a PA (page-add, `createNextDummyPage`) + PR (page-remove) pair with `prepare_offsetTotal` parity arithmetic, to add first pages on the **right** of a spread **without deleting any**.
**Why deferred:** it's ~80 lines of delicate page-offset math (off-by-one risks mis-paginate documents), it spans more of the method than I can fully see at once, and it can't be validated without real double-page documents. Per your "no mistakes" instruction I will **not** guess it.
**Scope/impact:** only triggers for **PAGINATION_DOUBLE** runs (facing-page spreads) that **create pages without deleting any** — i.e. heavy Dynamique/Compartiment double-page reports. A simple/single-page Plaquette is unaffected. Recommend a dedicated session: read the full .NET branch + add unit tests over page-id sequences before porting.

---

## `business/LoadTemplatesBusiness.java` — CHANGED (whole file)
```java
package com.socgen.sgs.api.quark.engine.business;

import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.RunError;
import com.socgen.sgs.api.quark.engine.domain.dynamic.template.Template;
import com.socgen.sgs.api.quark.engine.domain.task.TaskDynamique;
import com.socgen.sgs.api.quark.engine.infra.dao.GetGabaritTemplateDao;
import com.socgen.sgs.api.quark.engine.mapper.TemplateMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Map;

/**
 * Business component for loading templates from the database into a Run.
 *
 * Cross-reference: .NET Proxy_Template.Load_Templates(Run)
 */
@Component
@RequiredArgsConstructor
@Slf4j
public class LoadTemplatesBusiness {

    private final GetGabaritTemplateDao getGabaritTemplateDao;
    private final TemplateMapper templateMapper;

    /**
     * Load all templates for the run's gabarit template into run.getTemplates().
     *
     * @param run the run to populate with templates
     */
    public void execute(Run run) {
        // .NET Run.cs:132-165 only loads the template + templates when at least one dynamic task is
        // TODO (GetEnumerable<Task_Dynamique>(true)); otherwise it does nothing. Finding #56.
        boolean hasDynamicTodo = run.getTasks().values().stream()
                .anyMatch(t -> t instanceof TaskDynamique && t.isTodo());
        if (!hasDynamicTodo) {
            log.info("No TODO dynamic task for run [{}], skipping template loading", run.getId());
            return;
        }

        int idGabaritTemplate = run.getRunProperties().getIdGabaritTemplate();
        if (idGabaritTemplate == Integer.MIN_VALUE) {
            // .NET raises Exception_Run(MSG_Missing_ID_Gabarit_Template, Gabarit.ID) → Bloquante:
            // a dynamic run with no template id is a hard configuration error, not a silent skip.
            // Finding #56.
            Object gabId = run.getGabarit() != null ? run.getGabarit().getId() : run.getId();
            run.getErrors().add(new RunError(RunError.BLOQUANTE, String.format(
                    "Manque l'identifiant du gabarit template pour le gabarit %s", gabId)));
            log.error("Missing id_gabarit_template for run [{}] which has TODO dynamic tasks", run.getId());
            return;
        }

        log.info("Loading templates for idGabaritTemplate={} in run [{}]",
                idGabaritTemplate, run.getId());

        // Load the gabarit TEMPLATE document itself FIRST (parity: .NET Run.cs:152
        // this.Gabarit_Template = Get_Gabarit_Template(this); then :157 Load_Templates(this)).
        // Dynamic tasks clone their blocs from this document — without it TaskDynamique.prepare
        // would upload the wrong document. Finding #6/#22.
        DocumentDomain gabaritTemplate = getGabaritTemplateDao.getGabaritTemplate(idGabaritTemplate);
        // The DAO builder sets fileName but not filePoolPath; populate it the same way the source
        // gabarit is set up (GetGabaritBusiness.preparePaths → getPoolPath), so the upload key and
        // every later pool lookup resolve to the same R_<runId>/<fileName> string. .NET sets it in
        // the Document ctor via GetPoolPath (Document.cs:118).
        gabaritTemplate.setFilePoolPath(run.getRunProperties().getPoolPath(gabaritTemplate.getFileName()));
        run.setGabaritTemplate(gabaritTemplate);

        // .NET Run_Base.Mode_Degrade degrades the run when EITHER the gabarit OR the gabarit_template
        // is too big — re-evaluate against the just-loaded template so an oversized template degrades
        // the run (the outer Step 3-6 gate in runProcessor then skips them). Finding #29.
        if (gabaritTemplate.evaluateModeDegrade(run.getSizeLimitBeforeFailSoft())) {
            log.warn("Gabarit template {} bytes exceeds limit {} → setting Mode_Degrade for run [{}]",
                    gabaritTemplate.getData().length, run.getSizeLimitBeforeFailSoft(), run.getId());
            run.getRunProperties().setModeDegrade(true);
        }

        List<Map<String, Object>> rows = getGabaritTemplateDao.getTemplates(idGabaritTemplate);

        run.getTemplates().clear();

        for (Map<String, Object> row : rows) {
            Template template = templateMapper.mapToTemplate(row);
            if (template != null) {
                run.getTemplates().put(template.getName(), template);
            }
        }

        log.info("Loaded {} templates for run [{}]", run.getTemplates().size(), run.getId());
    }
}
```

---

## `domain/DocumentDomain.java` — add method (after `getRatioSizeBox`)
```java
    public boolean evaluateModeDegrade(long sizeLimitBeforeFailSoft) {
        return "QXP".equalsIgnoreCase(format)
                && data != null && data.length > 0
                && data.length > sizeLimitBeforeFailSoft;
    }
```

## `domain/Run.java` — `prepareGabarit` degrade check
```java
        if (this.gabarit.evaluateModeDegrade(sizeLimitBeforeFailSoft)) {
            log.warn("Gabarit size {} bytes exceeds limit {} bytes, setting Mode_Degrade for runId: {}",
                    this.gabarit.getData().length, sizeLimitBeforeFailSoft, this.id);
            this.runProperties.setModeDegrade(true);
            return;
        }
```

## `business/LoadTaskDocumentsBusiness.java` — remove BOTH `markModeDegradeIfTooBig(doc, run);` call lines, and delete the method (replaced by the explanatory comment block). #17

## `service/task/impl/DocumentTaskProcessStrategy.java` — unconditional position helper + drop guard
```java
    // build position helper UNCONDITIONALLY (ctor maps null/invalid → DEFAULT)
    TaskImagePosition imagePosition = task.getImagePosition();
    if (imagePosition == null) {
        imagePosition = new TaskImagePosition(task.getPositionValues());
        task.setImagePosition(imagePosition);
    }
    // ... and in the page loop, the guard drops `imagePosition != null`:
    if (i > 0 && srcBox != null
            && srcBox.getGeometry() != null && srcBox.getGeometry().getPosition() != null) {
```

## Apply checklist
- [ ] DocumentDomain (add method) · Run (degrade line) · LoadTemplatesBusiness (whole) · LoadTaskDocumentsBusiness (remove 2 calls + method) · DocumentTaskProcessStrategy (2 snippets)
- [ ] `mvn compile` + `mvn test`
- [ ] (deferred) schedule the #10 double-page pagination port
