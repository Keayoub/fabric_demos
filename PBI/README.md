# Power BI Diagnostic Toolkit

This guide explains how to investigate model structure, relationships, best-practice findings, and storage statistics using the three notebooks in this folder. It also explains when to move from model analysis to Power BI report diagnostics.

The notebooks are locally authored wrappers around Microsoft Semantic Link and Semantic Link Labs APIs. They do not automatically repair relationships, change DAX, refresh models, or prove that business calculations are correct.

## 1. Choose the right diagnostic

| Notebook | Main purpose | Important limitation |
|---|---|---|
| [Fabric Read-Only Semantic Model Diagnostics.ipynb](<Fabric Read-Only Semantic Model Diagnostics.ipynb>) | Inventory tables, columns, relationships, and measures; optionally calculate relationship missing-row statistics | Relationship properties require interpretation. Missing-row statistics are not a complete relationship-validity test. |
| [Fabric Semantic Model Best Practice Analyzer.ipynb](<Fabric Semantic Model Best Practice Analyzer.ipynb>) | Run Microsoft's Model Best Practice Analyzer (BPA), with optional extended analysis | A BPA warning is not automatically a defect, and a clean scan does not prove correct totals or business logic. |
| [Fabric Semantic Model Memory Analysis.ipynb](<Fabric Semantic Model Memory Analysis.ipynb>) | Inspect available VertiPaq model, table, and column statistics | These are not report visual timings, peak query memory, or total Fabric capacity memory. |

**Recommended order:** inventory and relationships, then BPA, then memory analysis when size or performance is a concern. For slow visuals, also use Power BI Performance Analyzer.

### Safety and scope

The three notebooks request no persistent model edits, refreshes, or lakehouse exports. Basic inventory uses metadata calls. Optional relationship checks query model data; BPA and memory analysis also consume compute, and some modes collect additional statistics.

Read-only behavior does not mean zero capacity impact or that a Viewer account can use every API. Model loading, queries, and statistics collection can affect cache/residency. Use an authorized test model where possible, and obtain approval before running expensive checks on production.

Notebook output can contain model names, column names, relationship details, DAX, and statistics. Keep it within approved locations.

## 2. Prepare Fabric and identify the target

You need:

- A Microsoft Fabric workspace where you can import and run notebooks, backed by an available supported capacity.
- A published Power BI semantic model accessible to your execution identity. These notebooks do not connect directly to an unopened local `.pbix` file.
- The exact workspace and semantic model names, plus permission to analyze the model.
- Working model connectivity, including XMLA availability and applicable tenant/capacity settings for TOM-dependent calls.
- Semantic Link (`sempy`) for the inventory notebook, and Semantic Link Labs (`sempy_labs`) for BPA and memory analysis.

In the Power BI or Fabric workspace, locate the **semantic model item**, not just the report. Report and model names can differ. For a report using a shared model, use lineage or the report's model connection to identify the actual model and its workspace.

Some current SemPy metadata APIs, including `list_relationships`, document a **ReadWrite** model permission requirement because they use the Tabular Object Model (TOM). A successful report-viewing experience or Build permission alone does not establish that all notebook calls will work. Have an administrator verify the exact requirement before granting additional access.

The notebook workspace and target model workspace can differ when your identity is authorized. All three notebooks explicitly pass the configured target workspace.

**No default lakehouse is required by these three notebooks' no-export workflow.** Attaching a lakehouse does not select the target semantic model; the configuration below does.

## 3. Import and install dependencies

1. Download the three `.ipynb` files from this repository's `PBI` folder.
2. In your Fabric workspace, use **Import notebook** to upload each file. Depending on the Fabric interface, this is available from the New item or notebook creation options.
3. Open each imported notebook and confirm that it is using your intended Fabric runtime/environment.

If `sempy_labs` is unavailable, add a separate code cell at the beginning of each BPA/memory notebook and run:

```python
%pip install semantic-link-labs
```

Alternatively, attach an approved Fabric Environment with the package already installed. Use your organization's approved package version rather than upgrading an existing shared environment without review.

If the runtime requests a Python/session restart after installation, restart it and then rerun the configuration and subsequent cells. A restart clears Python variables. Do not mix incompatible versions of Semantic Link and Semantic Link Labs to work around an API error.

The `%pip` command belongs in a **Fabric notebook code cell**, not in Power BI Desktop or a local PowerShell window.

## 4. Set the configuration separately in every notebook

Replace the empty strings with your actual workspace and semantic model names:

```python
WORKSPACE_NAME = "Sales Analytics - Test"
MODEL_NAME = "Sales Semantic Model"
```

These are illustrative names, not an existing connection. Keep the values in quotation marks. Every notebook has its own configuration; changing one does not configure the others.

The empty-name guard deliberately raises an error until both values are filled in.

Start with these settings:

| Notebook | Initial settings |
|---|---|
| Inventory and relationships | `RUN_RELATIONSHIP_VIOLATIONS = False` |
| BPA | `RUN_EXTENDED_BPA = False` |
| Memory | `RUN_MEMORY_ANALYSIS = False` and `READ_STATS_FROM_DATA = False` |

Run cells from top to bottom. After changing a configuration value, rerun its configuration cell and the analysis cells that use it. Changing text without executing the cell does not change the active Python value.

For your investigation, record the target model, storage mode, time, known incorrect KPI or slow visual, expected result, filters, and affected user role. Keep this record in an approved location, not automatically in Git.

## 5. Notebook 1: inventory and relationship diagnostics

Open **Fabric Read-Only Semantic Model Diagnostics.ipynb**.

### First pass: metadata only

1. Set `WORKSPACE_NAME` and `MODEL_NAME`; leave the optional switch `False`.
2. Run the configuration, inventory, and relationship-review cells in order.
3. Confirm that the returned table and measure names identify the model you intended to inspect.

The inventory retains complete results in these Python variables:

| Variable | Contents |
|---|---|
| `tables` | Semantic model table metadata |
| `columns` | Column metadata |
| `relationships` | Relationship metadata, including endpoints and available relationship properties |
| `measures` | DAX measure inventory; not a correctness test |

Inventory previews show at most **30 rows**. The relationship-review cell shows at most **100 rows**. A preview is not the full inventory: an object outside the displayed rows is not necessarily missing.

To inspect more rows or the available properties, add a temporary code cell:

```python
display(relationships)
print(relationships.columns.tolist())
display(measures.head(100))
```

Large results may still be truncated by the notebook display. Use the complete DataFrame to select relevant rows and columns. Property names and available metadata can vary by API version; inspect the returned columns before writing a filter.

### Review each relationship in context

| Property or finding | Questions to ask |
|---|---|
| From/to tables and columns | Are these the intended keys? Do the tables have compatible business grain? |
| Cardinality/multiplicity | Is the intended dimension key unique? Is a many-to-many relationship justified? |
| Active/inactive status | Is the active path the one the affected measure needs? Is an inactive date relationship intentional? |
| Filter direction | Should the dimension filter the fact? Is bidirectional filtering introducing an unintended path? |
| Multiple possible paths | Can filters reach the same table through more than one route? Does the model rely on that behavior? |
| Key values and types | Are data types, blanks, normalization, and business-key definitions consistent? |

The notebook **displays metadata; it does not automatically classify these relationships as defects**. Inactive relationships can support role-playing dates, many-to-many can be intentional, and bidirectional filtering can be required by a specific design.

### Optional second pass: missing-row statistics

After approving data-query/capacity usage, set:

```python
RUN_RELATIONSHIP_VIOLATIONS = True
```

Rerun the configuration and optional check cell. The implementation uses:

```python
fabric.list_relationships(
    MODEL_NAME,
    workspace=WORKSPACE_NAME,
    extended=True,
    calculate_missing_rows=True,
)
```

The complete result is retained in `relationship_validation`. The displayed table contains **all returned relationships**, not only failures. Inspect the returned missing-row statistic columns and their meaning.

Nonzero missing-row statistics are a reason to investigate unmatched keys, refresh timing, blanks, and source-data quality. Confirm which side is missing matches; do not assume every relationship's direction or shape is the same.

Zero missing rows does **not** prove key uniqueness, correct business grain, correct filter direction, absence of ambiguous paths, or correct DAX. This notebook does not independently perform an exhaustive duplicate-key or source-data validation.

The `sempy.fabric.list_relationship_violations` API is not a drop-in replacement for this call: it accepts loaded FabricDataFrames rather than a model name and `workspace` argument.

## 6. Notebook 2: Model Best Practice Analyzer

Open **Fabric Semantic Model Best Practice Analyzer.ipynb**.

1. Ensure Semantic Link Labs is available and set the target workspace/model.
2. Keep `RUN_EXTENDED_BPA = False` for the first pass.
3. Run the configuration and BPA cells in order.

The notebook calls `labs.run_model_bpa(...)` and renders BPA results. It explicitly uses `export=False`; it does not create a BPA lakehouse table or a Power BI report. This version displays the results rather than retaining them in a dedicated results DataFrame.

For each finding, inspect the rule description, severity, and affected objects. Prioritize findings related to the reported symptom rather than changing every object that triggers a rule.

| Finding area | How to investigate |
|---|---|
| Relationship/model design | Cross-reference the endpoints, status, cardinality, and filter direction from notebook 1. |
| DAX or measure design | Inspect the referenced expression and reproduce the affected calculation under known filters. |
| Potentially unnecessary objects | Check report, measure, relationship, and downstream dependencies before removing anything. |
| Performance recommendations | Establish a baseline query or visual timing; a recommendation alone does not prove the bottleneck. |

A clean scan means no violations of the evaluated rules were found. It does not certify report totals, RLS behavior, source freshness, or all possible relationship problems.

### Optional extended scan

After reviewing the initial results and approving the additional workload:

```python
RUN_EXTENDED_BPA = True
```

Rerun the configuration and BPA cells. Extended analysis fetches VertiPaq statistics to evaluate advanced rules, so it can take longer and consume more capacity. Available statistics and relevant rules depend on the model.

Do not treat skipped, failed, or incomplete analysis as a clean scan. SDK errors intentionally propagate rather than being replaced with an empty result.

## 7. Notebook 3: memory and storage analysis

Open **Fabric Semantic Model Memory Analysis.ipynb**.

After setting the workspace/model and approving the workload:

```python
RUN_MEMORY_ANALYSIS = True
READ_STATS_FROM_DATA = False
```

Run the configuration and analysis cells. The notebook calls `labs.vertipaq_analyzer(...)` with `export=None`. It retains the returned dictionary of DataFrames in `memory_stats` and previews up to **50 rows per section**.

After a successful run, use:

```python
print(list(memory_stats.keys()))
```

Then inspect a complete section using its returned name:

```python
section_name = next(iter(memory_stats))  # Inspect the first available section.
display(memory_stats[section_name])
```

Use the returned section names and column labels rather than assuming a fixed schema. Inspect units and sort the relevant full DataFrame by its size/cardinality column before deciding which objects dominate; the first 50 preview rows are not guaranteed to be the largest.

Look for unusually large columns, large dictionaries, high-cardinality text/identifiers, or tables that store more detail/history than the reporting requirements need. Verify dependencies and business requirements before considering removal, aggregation, data-type changes, or a different design.

### Interpret statistics by storage mode

| Storage mode | Interpretation |
|---|---|
| Import | VertiPaq statistics help explain the model's compressed storage footprint. |
| Direct Lake | Residency and the available statistics matter; do not assume the displayed values represent every possible loaded state. |
| DirectQuery | The source database's storage and execution costs are not measured as VertiPaq model memory. |
| Composite | Interpret each table according to its own storage mode, not just a single model-wide label. |

Unavailable statistics are not zero usage. These results are not a complete capacity-memory measurement or the peak memory of a slow DAX query.

### Optional data-derived statistics

Only if the additional statistics are needed and the workload is approved:

```python
READ_STATS_FROM_DATA = True
```

Keep `RUN_MEMORY_ANALYSIS = True`, then rerun the configuration and analysis cells. This can query data, increase compute cost, and affect cache/residency. It does not guarantee complete memory accounting for every model type.

If the memory switch remains `False`, the notebook prints a skip message and leaves `memory_stats = None`; that is not a successful memory scan with zero results.

## 8. Diagnose the Power BI report, not only its model

The notebooks analyze the semantic model; they do not execute every report visual or reproduce the report user's complete context.

For a reproducible report issue, capture the page/visual, slicers, report/page/visual filters, bookmarks, visual interactions, field parameters, relevant date relationships, and effective RLS identity. Match source/model refresh timestamps as well.

### Incorrect totals, blanks, or slicers

1. Reproduce the smallest affected visual with a known filter selection and expected answer.
2. Use notebook 1 to inspect the relationship path from the filtering dimension to the relevant fact.
3. If appropriate, run missing-row statistics and separately validate key uniqueness/types and source grain.
4. Review relevant BPA findings and the actual DAX expression.
5. Compare a source aggregation with the model result at the **same grain, filters, date definition, and security context**.

Do not assume the notebook execution identity reproduces a report viewer's RLS behavior. Use approved role/user testing in Power BI. A privileged diagnostic identity may see a different scope.

### Slow visuals: Performance Analyzer

In Power BI Desktop:

1. Open the report and select **View > Performance analyzer**.
2. Select **Start recording**, then **Refresh visuals**, or reproduce the slow interaction.
3. Expand the affected visual and inspect DAX query, visual display, and other durations.
4. Use **Copy query** for focused DAX investigation. Export the recording only to an approved location if evidence is needed.

Long DAX-query time points toward model/query/source investigation, but does not identify a cause by itself. Long visual-display time points toward rendering and visual complexity. The "Other" category can include waiting and preparation; it should not automatically be blamed on a relationship.

Repeat comparable interactions with consistent filters and note cache effects and concurrent capacity activity. Do not clear production caches simply to produce a benchmark. For DirectQuery, also investigate the source; for capacity pressure, use Fabric capacity monitoring.

## 9. Symptom-to-next-step reference

| Symptom | Start with | Follow-up |
|---|---|---|
| Slicer does not filter a visual | Relationship inventory | Check active path, direction, disconnected tables, measure logic, and visual interactions. |
| Unexpected blank/unknown dimension member | Optional missing-row check | Investigate unmatched keys, blanks, source quality, and refresh timing. |
| Duplicated or inflated totals | Relationship/cardinality review | Validate dimension uniqueness, fact grain, many-to-many intent, and DAX filter context. |
| Date totals do not match expectations | Active/inactive relationships | Check date roles, the measure's relationship choice, and date-filter definitions. |
| Slow visual | Performance Analyzer | Correlate slow DAX with BPA/model statistics or investigate visual/source/capacity causes. |
| Large model or memory pressure | Memory notebook | Inspect full statistics and storage mode; use capacity monitoring for capacity-level impact. |
| Different results for different users | Power BI security-context testing | Compare roles, identity, permissions, filters, and data freshness. |

## 10. Troubleshooting notebook execution

| Message or behavior | What to check |
|---|---|
| `Set WORKSPACE_NAME and MODEL_NAME...` | Fill in both strings and execute the configuration cell. |
| `ModuleNotFoundError: sempy_labs` | Install the approved package in that Fabric session/environment before importing it. |
| `ModuleNotFoundError: sempy` | Confirm a compatible Fabric runtime/Environment with Semantic Link; do not assume a generic local Python kernel has it. |
| Workspace/model not found | Confirm the semantic model's actual workspace, spelling, and identity access. |
| Permission denied, 401, or 403 | Have an administrator verify identity, model/workspace permissions, and relevant tenant/XMLA settings. Read-only calls can still require elevated permission. |
| Capacity/XMLA connection error | Verify capacity assignment/state and model connectivity with the administrator. |
| Unexpected keyword or missing SDK function | Check the installed package versions against the API documentation and notebook calls. Do not silently remove safety arguments to bypass the error. |
| Optional check says skipped | Execute the configuration cell with the corresponding switch enabled, then rerun its analysis cell. |
| Memory or extended analysis is slow | Review capacity impact and model size; stop/cancel the cell if necessary rather than starting duplicate runs. |
| Empty relationship inventory | The call returned no relationships. Verify the selected model and whether that design is expected; it is not proof of an execution failure or a healthy model. |
| A table/measure appears missing | Inspect the full inventory, not just the first 30 displayed rows, and verify model identity and visibility. |

If a run fails, resolve the error and rerun from configuration in a fresh session when appropriate. Old variables can remain after a failed cell; do not present earlier output as the latest run. None of these notebooks interprets an SDK exception as "no issues found."

## 11. Apply and verify a fix

The notebooks do not implement fixes. Use this sequence for a controlled change:

1. Record the failing example, expected answer, relevant diagnostic evidence, model version, and baseline timing.
2. Propose the smallest change in a development copy: source-key cleanup, relationship adjustment, DAX correction, or another evidence-based change.
3. Review dependencies, security effects, and downstream reports before applying it.
4. Reproduce the original case under the same filters and identity; also check a few unaffected totals and interactions.
5. Rerun the relevant notebook checks and timing comparison. Confirm both correctness and the intended performance effect.
6. Publish through your normal review/deployment process with an appropriate rollback plan.

Do not change cardinality, activate another path, enable bidirectional filtering, remove a column, or disable security solely to make a warning disappear.

## 12. Save evidence without publishing sensitive output

Record which checks actually ran, their configuration, model/run time, package versions, findings, and any unresolved errors. Store results only in approved locations.

Before sharing or committing executed notebooks, clear saved outputs and execution history and review any configuration values you entered. Do not include credentials, tokens, connection secrets, user-level data, or sensitive DAX/model metadata. A private GitHub repository is not a secrets store.

Use screenshots or excerpts only when authorized, and distinguish a successful scan with no findings from a skipped or failed scan.

## 13. Optional: a persistent BPA reporting solution

The separate `notebooks\nb_model_bpa_report.ipynb` is **not one of these three non-modifying analyzers**.

It adapts Microsoft's BPA reporting workflow: bulk scanning explicitly selected workspaces, appending results to a lakehouse, and creating or replacing the `ModelBPA` semantic model/report. Its write operations are disabled by default and guarded by destination checks and replacement confirmation.

Use it only when you want persistent BPA history/reporting and have approved the lakehouse writes, item replacement, access controls, and capacity usage. It is not necessary to diagnose one model with the three notebooks above.

## References

- [Microsoft Semantic Link Labs code examples: Model Best Practice Analyzer](https://github.com/microsoft/semantic-link-labs/wiki/Code-Examples#model-best-practice-analyzer)
- [Semantic Link Labs API reference](https://semantic-link-labs.readthedocs.io/en/stable/sempy_labs.html)
- [SemPy Fabric API: metadata and relationship APIs](https://learn.microsoft.com/en-us/python/api/semantic-link-sempy/sempy.fabric?view=semantic-link-python)
- [Explore and validate relationships](https://learn.microsoft.com/en-us/fabric/data-science/semantic-link-validate-relationship)
- [Power BI Performance Analyzer](https://learn.microsoft.com/en-us/power-bi/create-reports/performance-analyzer)
- [Microsoft's optional BPA reporting notebook](https://github.com/microsoft/semantic-link-labs/blob/main/notebooks/Best%20Practice%20Analyzer%20Report.ipynb)
