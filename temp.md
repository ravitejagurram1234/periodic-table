# EOS Quark — QXPSM SOAP Fix (Wrong WSDL + Endpoint Env Mismatch)

**Date:** 2026-06-26
**Supersedes:** `EOS_Quark_QxpsmSoap_MultiRef_Fix.md` (the multi-ref hypothesis is now disproven — see below).
**Blocker fixed:** `AxisFault: namespace mismatch require http://com.quark.qxpsm found http://webservice.manager.quark.com`

---

## 1. Root cause (decisive — from the live WSDL)

We fetched the **live** server WSDL:

```
http://srvcldqxpu001.dns43.socgen:8090/qxpsm/services/RequestService?wsdl
```

and compared it to the WSDL our stub is generated from
(`src/main/resources/wsdl/qxpsmsdk.wsdl`):

| Aspect | Repo `qxpsmsdk.wsdl` (current) | **Live deployed server** |
|---|---|---|
| SOAP stack | Apache **Axis 1.x** | Apache **Axis 2** |
| Style / use | **RPC / encoded** | **document / literal** |
| Target namespace | `http://webservice.manager.quark.com` | **`http://com.quark.qxpsm`** |
| Types namespace | `http://ro.clientsdk.manager.quark.com` | `http://com.quark.qxpsm` |
| Service name | `QManagerSDKSvcService` | `RequestService` |
| Port name | `qxpsmsdk` | `RequestServiceHttpSoap11Endpoint` (+ Soap12, Http) |
| PortType | `QManagerSDKSvc` | `RequestServicePortType` |
| Binding | `qxpsmsdkSoapBinding` | `RequestServiceSoap11Binding` |

**Conclusion:** our generated stub talks the wrong dialect on *every* axis — wrong
operation namespace **and** wrong encoding style. The Axis2 server's
`RPCUtil.invokeServiceClass` reads our operation wrapper
`<processRequest xmlns="http://webservice.manager.quark.com">` and rejects it because
the deployed service namespace is `http://com.quark.qxpsm`.

> **The multi-ref disable (Step 2) is irrelevant.** SOAP multi-reference (`href`/`id`)
> only exists in **RPC/encoded**. The live server is **document/literal**, which never
> uses multi-ref. That earlier change should be **removed**, not kept.

**Why .NET still works:** the deployed .NET runs co-located and points at its own
QXPSM instance with the old namespace. The endpoint our Java targets is a newer Axis2
QXPSM. The repo WSDL matches the *old* server, not the one we call.

The good news: the **data model is unchanged**. The live WSDL contains the same types
we already use — `QRequestContext`, `RequestParameters`, `NameValueParam`,
`ModifierRequest`, `SaveAsRequest`, `QuarkXPressRenderRequest`, `Project`,
`QContentData` — with the same fields. So once we regenerate, `QxpsmSoapClient`'s
request-chain logic stays the same; only the **locator / port / stub class names**
change.

---

## 2. Second problem — endpoint environment mismatch (must also fix)

Hostnames (confirmed by you): `srvcldqxpu001` = **UAT**, `srvcldvapd001` = **DEV**.

Current `application.yaml`:

| Property | Host | Env |
|---|---|---|
| `qxps.server.url` | `http://srvcldvapd001.dns43.socgen:8080` | **DEV** |
| `qxpsm.soap.endpoint` | `http://srvcldqxpu001.dns43.socgen:8090/...` | **UAT** |

QXPS (HTTP) **adds the gabarit to DEV's document pool**, then QXPSM (SOAP) tries to
**modify it on UAT** — where the file does not exist. The two services for a single run
must live on the **same Quark host**. QXPS Server (`:8080`) and QXPSM Manager (`:8090`)
are two ports of the **same** Quark deployment.

**Fix:** point `qxpsm.soap.endpoint` at the **same host** as `qxps.server.url`
(DEV `srvcldvapd001:8090`). Then **regenerate the stub from that host's WSDL**
(`http://srvcldvapd001.dns43.socgen:8090/qxpsm/services/RequestService?wsdl`) and
confirm it is the same `document/literal` + `com.quark.qxpsm` shape (it should be —
same Quark version across envs).

> Pick **one** environment end-to-end. Simplest for your current run (509636, already
> pooling on DEV): make **both** DEV.

---

## 3. Fix — step by step

### Step 1 — Add the live WSDL to the repo (byte-exact)

Do **not** hand-copy the WSDL — `wsdl2java` needs the exact bytes. Fetch it raw from the
environment you will actually target (DEV, to match QXPS):

```bash
curl -s "http://srvcldvapd001.dns43.socgen:8090/qxpsm/services/RequestService?wsdl" \
  -o src/main/resources/wsdl/RequestService.wsdl
```

(If DEV's QXPSM is unreachable, use the UAT URL you already opened — but then also point
the endpoint in Step 4 at UAT so both match.)

Quick sanity check on the saved file:

```bash
grep -m1 'targetNamespace' src/main/resources/wsdl/RequestService.wsdl   # → http://com.quark.qxpsm
grep -m1 'soap:binding'    src/main/resources/wsdl/RequestService.wsdl   # → style="document"
```

### Step 2 — Point the build at the new WSDL

In `pom.xml`, the `axistools-maven-plugin` config:

```xml
<sourceDirectory>${project.basedir}/src/main/resources/wsdl</sourceDirectory>
<wsdlFiles>
    <wsdlFile>RequestService.wsdl</wsdlFile>   <!-- was: qxpsmsdk.wsdl -->
</wsdlFiles>
```

Also update the stale comment above the plugin:
`Generate Java classes from the QXPSM WSDL (document/literal, Axis2 server)` —
(was "RPC/encoded style").

> The `<dependencies>` on `org.apache.axis:axis*` (1.x) stay. Axis 1.x can consume a
> wrapped document/literal WSDL and will generate a synchronous client stub. It ignores
> the `soap12` binding and the `wsaw:Action` (WS-Addressing) attributes.

### Step 3 — Delete the old generated stub so it regenerates clean

The plugin writes **into `src/main/java`** (the generated classes are committed). The old
classes use the wrong namespace and old service names; they must be removed or they'll
linger as stale/dead source:

```bash
rm -rf src/main/java/com/socgen/sgs/api/quark/engine/integration/soap/generated/
```

Then a clean build regenerates the full set from `RequestService.wsdl`:

```bash
mvn clean install
```

> If `wsdl2java` errors on the `soap12` binding or the three-port service, trim the saved
> WSDL to just the SOAP 1.1 parts: keep `RequestServiceSoap11Binding` and the
> `RequestServiceHttpSoap11Endpoint` port; delete the `<wsdl:binding ...Soap12Binding>`,
> `<wsdl:binding ...HttpBinding>` blocks and their two `<wsdl:port>` entries in
> `<wsdl:service>`. The `<wsdl:types>` and `RequestServicePortType` stay untouched.

### Step 4 — Fix the endpoint env mismatch (`application.yaml`)

```yaml
qxpsm:
  soap:
    # Same Quark host as qxps.server.url (DEV). QXPS Server :8080 and QXPSM Manager :8090
    # are the same deployment — they MUST point at the same host so the pooled document
    # is visible to the SOAP modify call.
    endpoint: http://srvcldvapd001.dns43.socgen:8090/qxpsm/services/RequestService
    timeout: 7200000
    max-retries: 0
```

(If you instead standardise on UAT, set **both** `qxps.server.url` → `srvcldqxpu001:8080`
**and** `qxpsm.soap.endpoint` → `srvcldqxpu001:8090`, and regenerate from the UAT WSDL.)

### Step 5 — Update `QxpsmSoapClient` to the new generated names

The class names change with the new WSDL. Replace the locator/stub lookups and **remove
the multi-ref line**. Predicted Axis 1.x names (verify against the freshly generated
`integration/soap/generated/` after Step 3 — adjust if they differ):

| Old (rpc/encoded) | New (doc/literal) |
|---|---|
| `QManagerSDKSvcServiceLocator` | `RequestServiceLocator` |
| `QManagerSDKSvc` | `RequestServicePortType` |
| `locator.getqxpsmsdk(url)` | `locator.getRequestServiceHttpSoap11Endpoint(url)` |

**`executeStep(...)`** — replace lines 52–61:

```java
            // Get the Axis-generated stub (regenerated from the live document/literal WSDL).
            RequestServiceLocator locator = new RequestServiceLocator();
            RequestServicePortType stub =
                    locator.getRequestServiceHttpSoap11Endpoint(new URL(qxpsmProperties.getEndpoint()));

            // NOTE: the deployed QXPSM is document/literal (Axis2). It does NOT use SOAP
            // multi-reference encoding, so no PROP_DOMULTIREFS handling is needed here.
```

**`getProject(...)`** — replace lines 140–142:

```java
            RequestServiceLocator locator = new RequestServiceLocator();
            RequestServicePortType stub =
                    locator.getRequestServiceHttpSoap11Endpoint(new URL(qxpsmProperties.getEndpoint()));
            return stub.getXPressDOM(documentName);
```

Everything in between (the `RequestParameters → ModifierRequest → SaveAsRequest →
QuarkXPressRenderRequest` chain and the `QRequestContext` field setters) is **unchanged**
— those types exist with identical fields in the new WSDL.

> **Method signatures to confirm post-regen:** for wrapped doc/literal, Axis 1.x usually
> generates `QContentData processRequest(QRequestContext param0)` and
> `Project getXPressDOM(String param0)` — matching today's calls. If the generated port
> exposes a request/response *wrapper* type instead, tell me the exact signatures and
> I'll adjust the chain code.

---

## 4. Build & verify

```bash
mvn clean install
```

Then re-run **runId 509636** (Plaquette, DOCUMENT_COURANT). Expected progression past the
previous blocker:

1. QXPS `addfile` → pool `R_509636/` on **DEV** ✅ (already works)
2. QXPS `/xml` fetch ✅ (already works — buffer fix in place)
3. **QXPSM `processRequest`** → now accepted (correct namespace + same host as the pool)
4. SaveAs in pool → render

Keep the temporary `TEMP-DEBUG-RT` logging until the SOAP round-trip succeeds end-to-end;
remove it afterward.

---

## 5. Files changed (for the air-gapped repo)

| File | Change |
|---|---|
| `src/main/resources/wsdl/RequestService.wsdl` | **NEW** — raw live WSDL (curl, Step 1) |
| `src/main/resources/wsdl/qxpsmsdk.wsdl` | delete (or leave unused) |
| `src/main/java/.../integration/soap/generated/` | **deleted then regenerated** by the build |
| `pom.xml` | `wsdlFile` → `RequestService.wsdl`; comment updated |
| `application.yaml` | `qxpsm.soap.endpoint` → DEV host (`srvcldvapd001:8090`) |
| `.../infra/interop/qxpsm/QxpsmSoapClient.java` | new locator/port/stub names; multi-ref line removed |

---

## 6. Open items / risks

- **Axis 1.x ↔ Axis2 doc/literal:** generation is expected to work, but if `wsdl2java`
  stumbles on the multi-binding service, trim the WSDL to the SOAP 1.1 port (Step 3 note).
- **Generated names:** the table in Step 5 is predicted; confirm against the regenerated
  sources and adjust `QxpsmSoapClient` if needed.
- **DEV QXPSM availability:** confirm `srvcldvapd001:8090` answers `?wsdl`. If only UAT is
  reachable, standardise both QXPS + QXPSM on UAT instead (Step 4 alternative).
- **Long-term option:** the deployed service is plain SOAP 1.1 document/literal — a natural
  fit for **JAX-WS / Apache CXF** (`wsimport`/`cxf-codegen`). That's cleaner than Axis 1.x
  but a larger change; Axis-regen above is the minimal path that reuses existing code.
```
