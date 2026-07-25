Launch Generation — "Association Run / Tâches" page (Tableau de Bord, étape 3)
This document explains everything that happens when a user clicks the "Générer" (Launch Generation) button on the Association Run Tâches page, and where every piece of data comes from and where it is used — including the "events by suivi / by gabarit" data.

There are two parts to read:

Part A — The simple flow → an easy, plain‑language walkthrough. Start here.
Part B — The detailed data flow → every method, every stored procedure, every table (read/written). Use this as a reference.
The one thing to understand first: there are TWO phases
The button does not generate the document directly. It works in two separate phases that run in two different processes:

Phase	Where it runs	What it does	Synchronous?
Phase 1 — Prepare	Web server + Oracle (QXP_PK_SUIVI package)	Creates the suivis and runs in the database and marks them "to generate".	Yes — happens while the user waits, inside OnValider.
Phase 2 — Generate	Batch service → a separate QXP.Engine.exe process → Quark Server	Actually builds the PDF / QXP / Word document and saves it.	No — fire‑and‑forget; the web page returns immediately.
The bridge between them is a single WCF call: ExecuteRuns(idRuns).

ExecuteRuns idRuns
WCF

User clicks
Générer

Phase 1
Web + Oracle
create suivis & runs

Phase 2
Batch service
queue + spawn

QXP.Engine.exe
one process per run

Quark Server
build document

Save PDF / QXP
to DB + file pool





Part A — The simple flow
Entry point
AssociationRunTaches.OnValider() — QXP.WebSite/Generation/TableauDeBord/AssociationRunTaches.cs:487 (this is the click handler of the "Générer" button).

Phase 1 — what the click does, step by step
Check nothing is already running. It asks Oracle "are any of these funds already being generated?" If yes, it shows an error and stops. (No runs are created.)

Collect the selected tasks. It reads the checkboxes from the 5 task lists on the page — SQL, Documents, QXP blocks, Dynamiques, and Compartiments — into one list of task IDs. If none are selected, it stops with an error.

Read the user's choices (source of confection, "integrate N‑1 data" yes/no, compartment generation mode, immediate vs scheduled, planning date, creator = current user).

Create the runs for the "head" suivis (the funds shown/selected on the dashboard). For each selected suivi it creates one run and attaches the selected tasks to it. Each new run is marked "À générer" (status 1).

If any Compartiment task was selected, do the extra compartment work:

Get the list of compartments for each head suivi + compartment task. This list contains compartments that already exist and compartments that should exist but don't yet ("théoriques").
If the mode is "Générer" (or "Générer + Intégrer"):
Create the missing compartment suivis (the théoriques). For each one it also copies the default events of the template (gabarit) onto the new suivi.
Create the compartment runs and attach their tasks. These are scheduled at DateMax on purpose, so they are launched by the head run rather than on their own.
Launch immediately (if "Immédiat" was chosen). It calls the batch service (ExecuteRuns) with the list of head run IDs. This starts Phase 2.

Write an audit trail and redirect back to the dashboard.

yes

no

no

yes

no

yes

no

yes

yes

no

OnValider — button click

Any run
already in progress?

Show error, STOP

Collect checked task IDs
from the 5 tree-views

Any task
selected?

Show error, STOP

InsertRuns:
1 run per head suivi
+ attach tasks
status = À générer

Compartiment
task checked?

Mode = Immédiat?

GetListeSuivisComparts
existing + théoriques

Mode = Générer?

Create missing compart suivis
+ copy template default events

Create compart runs
+ attach their tasks

LaunchImmediateRuns → ExecuteRuns WCF

Leave runs scheduled

Audit + redirect





Phase 2 — what generation does, step by step
The batch service receives ExecuteRuns. It does not generate anything itself. It:

marks the runs as "taken over by the batch",
puts each run ID into an in‑memory queue,
wakes up worker threads. Then it returns.
A worker thread picks a run off the queue and starts a brand‑new process: QXP.Engine.exe <runId>. It waits for that process to finish.

The engine loads the run and runs a fixed pipeline: Start → Load → Prepare → Process → Process Steps → Check → Render → End.

Load reads the run's properties, the template (gabarit), the previous document, the InParams (keyed by the suivi id), and the run's tasks.
The engine executes each task by type (SQL, Document EOS, QXP block, Dynamique, Compartiment). SQL/Dynamique tasks run their SQL against Oracle using the run's InParams.

The engine talks to Quark Server to actually build the document and render PDF / QXP / JPG.

The engine saves the result: the files go to the Quark file pool, and the document records (QXP, PDF, DOC) are written to the database; the run is closed (End_Run) in a single Oracle transaction.

ExecuteRuns idRuns

ServiceCommand:
mark taken by batch
+ enqueue + wake threads

Worker thread:
dequeue run

Process.Start
QXP.Engine.exe runId

Run.Launch pipeline

Load: properties, gabarit,
previous doc, InParams by suivi id, tasks

Process each task
by Task_Type

QXPS_Caller → Quark Server SDK

Render PDF / QXP / JPG

Save files + Insert_Document
+ End_Run in DB





Note on events: the engine does not read "events" directly. Events live in the web/DB tier only. They influence generation indirectly — the suivi id flows into the run's InParams, and task SQL queries Oracle (which can join the event tables) to pull event‑driven data. See the events section.

Part B — The detailed data flow
All C# references are in the codebase root QXP.../ and all Oracle references are line numbers in ora.txt (package QXP_PK_SUIVI).

B.1 — Full call chain (Phase 1, inside OnValider)
#	C# call (ProxySuivi unless noted)	Oracle routine	Reads FROM	Writes TO
1	CheckIfRunsEnCours — ProxySuivi.cs:817	CheckIfRunsEnCours (+ _Internal pipelined) — ora.txt:12373 / 12413	QXP_SUIVI, QXP_RUN, QXP_GABARIT	—
2	InsertRuns → InsertRun — ProxySuivi.cs:1517 / 1611	InsertRun — ora.txt:11912	QXP_SUIVI (id_run_suivant)	QXP_RUN (seq QXP_SQ_RUN, id_statut_generation=1), QXP_SUIVI (id_run_suivant, id_statut_generation=1)
3	InsertRuns → InsertRunTaches — ProxySuivi.cs:1708	InsertRunTaches — ora.txt:11978	—	QXP_ASSO_RUN_TACHES (DELETE by run, then INSERT per task)
4	GetListeSuivisCompartBySuivi — ProxySuivi.cs:1137	GetListeSuivisCompartBySuivi — ora.txt:13981	see B.3	—
5	GetListeSuiviEventsBySuivi — ProxySuivi.cs:931	GetListeSuiviEventsBySuivi — ora.txt:12878	QXP_SUIVI_EVENT	—
6	InsertSuivisManquants → InsertSuivi — ProxySuivi.cs:1439	InsertSuivi — ora.txt:11140	QXP_ASSO_FOND_GABARIT, OWB_DWH.REF_FUND, QXP_GABARIT	QXP_SUIVI (seq QXP_SQ_SUIVI, status 0/0), QXP_ASSO_SUIVI_PARAMETRES, QXP_AUDIT_WORKFLOW_SUIVI, (opt.) QXP_ASSO_FOND_GABARIT + QXP_AUDIT
7	GetListeSuiviEventsByGabarit — ProxySuivi.cs:983	GetListeEventsByGabarit — ora.txt:14084	QXP_REF_EVENT, QXP_ASSO_GABARIT_EVENT	—
8	InsertSuiviEvent — ProxySuivi.cs:1745	InsertSuiviEvent — ora.txt:12908	—	QXP_SUIVI_EVENT (id_event_step=1), QXP_AUDIT_SUIVI_EVENT (seq QXP_SQ_AUDIT_SUIVI_EVENT)
9	InsertRunsComparts → InsertRunCompart — ProxySuivi.cs:1555 / 1664	InsertRun — ora.txt:11912	QXP_SUIVI	QXP_RUN, QXP_SUIVI
10	InsertRunsComparts → GetListeTachesByGabarit — ProxySuivi.cs:1579	GetListeTachesByGabarit — ora.txt:11873	QXP_ASSO_GABARIT_TACHES, QXP_TACHE	—
11	InsertRunsComparts → InsertRunTaches — ProxySuivi.cs:1586	InsertRunTaches — ora.txt:11978	—	QXP_ASSO_RUN_TACHES
12	LaunchRun.LaunchImmediateRuns — LaunchRun.cs:76	(WCF, not Oracle) → Phase 2	—	—
The page task lists themselves are loaded earlier (on page load, ComponentDataBind, AssociationRunTaches.cs:205) via GetListeTachesByGabAndType — ProxySuivi.cs:587 → GetListeTachesByGabAndType ora.txt:11836 (reads QXP_ASSO_GABARIT_TACHES + QXP_TACHE, active tasks only, is_actif=1).

B.2 — Where the "head suivi" data itself came from (page 2)
The suivis being launched (SuiviTDBWeb.SelectedSuivis) were loaded on the dashboard page (étape 2), before this page, by:

GetListeSuivisTDBByFondsPart / GetListeSuivisTDBByStructures — ProxySuivi.cs:389 / 523
and for each returned suivi, its events were loaded via GetListeSuiviEventsBySuivi — ProxySuivi.cs:481 / 576.
Notable columns mapped there (ProxySuivi.cs:415‑476): ID_SUIVI, ID_STATUT_SUIVI, ID_STATUT_GENERATION, ID_FND_CODE, DATE_LAST_ECHEANCE→EcheanceLast, DATE_ECHEANCE→EcheanceNext, gabarit info, maquettiste, ID_RUN_PRECEDENT/ID_RUN_SUIVANT, CAC validation, KIID validation. This is the data carried in session into OnValider.

B.3 — GetListeSuivisCompartBySuivi — the compartment list
Oracle: ora.txt:13981. Returns one row per sub‑fund/part for a compartment (tête) suivi + compartment task — both existing child suivis and théoriques (not yet created).

Reads FROM: QXP_SUIVI (suivi_tete, left‑joined suivi, inline parts subquery), QXP_ASSO_STRUCT_GABARIT_COMP, OWB_DWH.REF_FUND, OWB_DWH.REF_UNIT, QXP_ASSO_GABARIT_TACHES, QXP_TACHE, QXP_GABARIT, QXP_ASSO_SUIVI_PARAMETRES (sv_prm_tete + sv_prm, id_parametre=2), OWB_DWH.REF_INSTRUMENT, OWB_DWH.REF_CODIFICATION, QXP_UTILISATEUR, QXP_REF_TYPE_FOND, QXP_REF_CLASSIF_FOND, EOS.EOS_CAC_VALIDATION.

Key columns → C# mapping (ProxySuivi.cs:1162‑1209): ID_SUIVI→IdSuivi (null = théorique / not yet created), DATE_ECHEANCE_EXACTE→**EcheanceNext, DATE_ECHEANCE→EcheanceLast**, plus fund/gabarit/statut columns.

Fallback rule (important): when the child suivi.id_suivi is NULL, several columns fall back to the tête suivi's values via DECODE, e.g. ora.txt:14005:

DECODE(suivi.id_suivi, NULL, sv_prm_tete.valeur, sv_prm.valeur) AS date_echeance_exacte
So a not‑yet‑created compartment already carries the head suivi's exact due date — it is not null. That inherited value is exactly what gets passed straight back into InsertSuivi in the next step (see below).

B.4 — Creating a missing compartment suivi (the date_echeance_exacte link)
In InsertSuivisManquants (ProxySuivi.cs:1457‑1497), for each compartment whose IdSuivi is not set, InsertSuivi is called with:

Oracle param	C# value	Meaning
p_id_type_rapport	4	compartment report type
p_date_echeance	__suivi.EcheanceLast	= DATE_ECHEANCE from B.3 (inherited from tête when théorique)
p_date_echeance_exacte	__suivi.EcheanceNext	= DATE_ECHEANCE_EXACTE from B.3 (inherited from tête when théorique)
p_id_gabarit	child gabarit id	
p_id_createur	0 (System)	automatic creation
Inside InsertSuivi (ora.txt:11216‑11220) p_date_echeance_exacte is stored unconditionally as QXP_ASSO_SUIVI_PARAMETRES parameter 2 — the same slot B.3's sv_prm/sv_prm_tete read from. This is why the value round‑trips cleanly and never becomes null.

B.5 — Phase 2 execution chain (after ExecuteRuns)
#	Component	File:line	What it does
1	IServiceCommand.ExecuteRuns (WCF contract)	QXP.Batch.Interop/BusinessObject/IServiceCommand.cs:24	endpoint WSHttpBinding_IServiceCommand
2	ServiceCommand.ExecuteRuns	QXP.Batch.Core/BusinessObject/Interop/ServiceCommand.cs:49	UpdateRunsStatus (mark taken by batch), enqueue Run_Queue, wake worker threads — returns immediately
3	Worker_Thread.Start / LaunchRun	QXP.Batch.Core/BusinessObject/Watcher/Worker_Thread.cs:19 / 60	dequeue → Process.Start(QXP.Engine.exe <runId>) → WaitForExit
4	QXP.Engine.Program.Main	QXP.Engine/Program.cs:13	new Run(id).Launch()
5	Run_Base.Launch	QXP.Engine.Core/BusinessObject/Run/Run_Base.cs:97	pipeline: Start → Load → Prepare → Process → Process_Steps → Check → Render → End
6	Run.LoadInParams → Proxy_Param.Load_In_Params	QXP.Engine.Core/.../Run.cs:106, Proxy_Param.cs:79	loads InParams via QXP_PK_RUN.Get_In_Params keyed on p_id_suivi
7	Proxy_Task.Get_Task	QXP.Engine.Core/Proxy/Proxy_Task.cs:218	switch on ID_TYPE_TACHE → Task_Type (SQL=1, DOC_EOS=2, DOC_QXP=3, SQL_DYNAMIQUE=4, COMPARTIMENTS=5)
8	Task_*.Process → Business.Process_*	QXP.Engine.Core/Business/Task/Process_*.cs	SQL runs task SQL with cloned InParams; others insert doc/QXP/dynamic/compartment fragments
9	QXPS_Caller.Process / .Render	QXP.Engine.Core/BusinessObject/QXPS/QXPS_Caller.cs:61 / 229	Quark Server SDK calls → PDF / QXP / JPG
10	Run_Base.Render + Save_Result	Run_Base.cs:504 / 550	wrap outputs as Document, save files to Quark pool
11	Proxy_Run.End_Run → Proxy_Document.Insert_Document + QXP_PK_RUN.End_Run	Proxy_Run.cs:263 / 310‑312, Proxy_Document.cs:234	persists QXP/PDF/DOC document ids + closes run, one Oracle transaction
Task types (engine side)
Web list (page 3)	Engine Task_Type	Engine class	Process class
SQL	SQL = 1	Task_SQL.cs	Process_SQL — runs SQL with InParams, builds update blocks
Documents	DOC_EOS = 2	Task_Document.cs	Process_Document — inserts EOS doc/image fragment
Blocs QXP	DOC_QXP = 3	Task_QXP_Previous.cs	Process_QXP_Previous — pulls fragment from a previous QXP
Dynamiques	SQL_DYNAMIQUE = 4	Task_Dynamique.cs	Process_Dynamique — SQL that creates/fills new blocs with overflow/page rules
Compartiments	COMPARTIMENTS = 5	Task_Compartiment.cs	Process_Compartiment — incorporates child runs from child gabarit
(auto‑added)	—	Task_DID.cs	Document Identity, post‑processing pass
Events (the part you asked about): "by suivi" vs "by gabarit"
There are two different event concepts, from two different tables, used at two different moments:

Events by suivi	Events by gabarit
What it is	The actual events recorded for one specific suivi	The catalogue of events that a template (gabarit) declares
Table	QXP_SUIVI_EVENT	QXP_ASSO_GABARIT_EVENT (link) + QXP_REF_EVENT (reference)
Fetched by (C#)	GetListeSuiviEventsBySuivi — ProxySuivi.cs:931	GetListeSuiviEventsByGabarit — ProxySuivi.cs:983
Fetched by (Oracle)	GetListeSuiviEventsBySuivi — ora.txt:12878	GetListeEventsByGabarit — ora.txt:14084
Output columns	id_event, id_event_step, event_data_type, event_date_echeance	id_event only
Where used	(a) Dashboard display on page 2 (loaded per suivi, ProxySuivi.cs:481/576); (b) during compartment creation, to load existing events onto the suivi object (AssociationRunTaches.cs:409)	When a new compartment suivi is created, these are the default events copied onto it (InsertSuivisManquants, ProxySuivi.cs:1488)
How events get written when a compartment suivi is created
InsertSuivisManquants (ProxySuivi.cs:1487‑1496):

GetListeSuiviEventsByGabarit(gabarit) → reads the template's default events (QXP_ASSO_GABARIT_EVENT + QXP_REF_EVENT).
For each default event → InsertSuiviEvent(..., idUser=0) → InsertSuiviEvent (ora.txt:12908) writes a row into QXP_SUIVI_EVENT at step 1 ("non reçue") plus an audit row in QXP_AUDIT_SUIVI_EVENT.
GetListeSuiviEventsByGabarit

InsertSuiviEvent per event
step = 1

audit

later, GetListeSuiviEventsBySuivi

QXP_ASSO_GABARIT_EVENT
+ QXP_REF_EVENT
template default events

InsertSuivisManquants

QXP_SUIVI_EVENT
events of the new suivi

QXP_AUDIT_SUIVI_EVENT

Dashboard display /
suivi object





The key subtlety: the engine never reads events directly
During Phase 2, generation does not consume Event objects. The link is indirect:

suivi id  →  Run InParams (QXP_PK_RUN.Get_In_Params, Proxy_Param.cs:79)
          →  cloned into each SQL/Dynamique task (Process_SQL.cs:48)
          →  task SQL queries Oracle (may join QXP_SUIVI_EVENT)
          →  event-driven data lands in the document
So "events" affect the output only through task SQL that reads the event tables, keyed by the suivi id — not through any event object passed to the engine. The event‑management logic itself lives entirely in the web/DB tier (ProxySuivi.cs + package QXP_PK_SUIVI).

Appendix — table glossary (most‑touched)
Table	Role in this flow
QXP_SUIVI	The "suivi" (tracking record) per fund/part/échéance. Created/updated by InsertSuivi; id_run_suivant + id_statut_generation updated by InsertRun.
QXP_RUN	A generation run. Created/updated by InsertRun (seq QXP_SQ_RUN), id_statut_generation=1 = "À générer".
QXP_ASSO_RUN_TACHES	Link run ↔ tasks. Rewritten by InsertRunTaches.
QXP_ASSO_SUIVI_PARAMETRES	Per‑suivi InParams. Param 1 = fund, Param 2 = date_echeance_exacte, Param 3 = gabarit, Param 4 = unit code.
QXP_SUIVI_EVENT	Events recorded on a suivi (step, data type, échéance).
QXP_ASSO_GABARIT_EVENT / QXP_REF_EVENT	Template's declared events / event reference catalogue.
QXP_ASSO_GABARIT_TACHES / QXP_TACHE	Tasks declared on a gabarit / task definitions.
QXP_GABARIT	Templates (type: structure / fonds‑parts, etc.).
QXP_ASSO_STRUCT_GABARIT_COMP	Links a structure gabarit to its compartment sub‑funds.
OWB_DWH.REF_FUND / REF_UNIT / REF_INSTRUMENT / REF_CODIFICATION	External data‑warehouse fund/part/instrument reference data.
QXP_AUDIT*	Audit trails (workflow, events, generic).
