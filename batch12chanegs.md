# EOS Quark Engine — Batch 12 Changes
**Theme: QXP XML parsing / box-counting parity (`domain/xml/QxpXml.java`)**

_Single file, snippets. These feed box counts (overflow / Nb_Box_Max) and page resolution, so each mirrors the exact .NET semantics._

## Findings fixed (6)
| # | Sev | Fix |
|---|---|---|
| 45 | MEDIUM | Table-cell boxes were never counted: `pageAttr` is an ATTRIBUTE node, so `getParentNode()` is always null → now uses `((Attr)pageAttr).getOwnerElement()` to reach GEOMETRY→TABLE. |
| 46 | MEDIUM | `getPageNum` returns `Integer.MIN_VALUE` (not 0) for a not-found/unparseable bloc — matches .NET `int.MinValue`. |
| 78 | LOW | Page parsing is now lenient (strips trailing `*`, spaces, normalizes `,`→`.`, BigDecimal parse) — matches .NET `ConversionInvariante.ToInt(NumberStyles.Any)`. |
| 77 | LOW | Page-0 / pastboard boxes are now counted in `pageBoxes` (guard `!= MIN_VALUE` instead of `> 0`) — matches .NET `IsSet`; `parseIntSafe` now returns MIN_VALUE on failure (distinct from a real page 0). |
| 79 | LOW | `getBlocInfo` reads ALL POSITION descendants (`.//*`), not just direct children — matches .NET `SelectDescendants`. |
| 80 | LOW | `evaluateNodeListAsStrings` keeps blank/whitespace names — .NET never blank-filters, so box-name list counts now match. |

---

## `parseIntSafe` — lenient + MIN_VALUE sentinel (#46/#77/#78)
```java
private int parseIntSafe(String value) {
    if (value == null) return Integer.MIN_VALUE;
    String s = value.replaceAll("\\*+$", "").replace(" ", "").replace(',', '.');
    if (s.isEmpty()) return Integer.MIN_VALUE;
    try { return new java.math.BigDecimal(s).toBigInteger().intValue(); }
    catch (NumberFormatException e) { log.warn("Cannot parse int from [{}]", value); return Integer.MIN_VALUE; }
}
```

---

## `getPageNum` — delegate to the lenient parser (#46/#78)
```java
public int getPageNum(String blocName) {
    return parseIntSafe(getPageID(blocName));   // MIN_VALUE if not found / unparseable
}
```

---

## box & table loops in getProjectInfo (#77)
```java
// BOTH the spread-box loop and the table-cell loop:
if (currentPage != Integer.MIN_VALUE) {   // was `> 0` — page 0 / pastboard now counted
    ...
}
```

---

## table-cell parent via getOwnerElement (#45)
```java
Node tableGeomNode = (pageAttr instanceof org.w3c.dom.Attr)
        ? ((org.w3c.dom.Attr) pageAttr).getOwnerElement()   // GEOMETRY (attr.getParentNode() is null!)
        : pageAttr.getParentNode();
```

---

## getBlocInfo descendant traversal (#79)
```java
Node positionNode = positionNodes.item(0);
NodeList children = (NodeList) xpath.evaluate(".//*", positionNode, XPathConstants.NODESET);
for (int i = 0; i < children.getLength(); i++) {
    Node child = children.item(i);
    String nodeName = child.getNodeName();
    ... // same LEFT/TOP/RIGHT/BOTTOM switch
}
```

---

## evaluateNodeListAsStrings keep blank (#80)
```java
if (value != null) {   // was `value != null && !value.isBlank()`
    result.add(value);
}
```

## Safety
No test asserts QxpXml counts (`TaskPropertiesTest` tests the domain field, not this class). `parseIntSafe` has exactly 3 call sites (getPageNum + 2 box loops), all updated consistently. Box *totals* are unchanged by #77 (only page-0 boxes move into `pageBoxes`); #45 genuinely *adds* previously-missing table-cell counts.

## Apply checklist
- [ ] Replace the 6 snippets in `domain/xml/QxpXml.java`
- [ ] `mvn compile` + `mvn test`
