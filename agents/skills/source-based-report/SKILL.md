---
name: source-based-report
description: Create or revise Japanese study reports from designated sources, or adapt them into presentation notes, matching the audience and supplied writing samples.
---

# Source-Based Report

Turn designated evidence into a report with clear reasoning and an appropriate
voice. Default to Japanese output for this workflow. The user's current
instructions override the audience, structure, source, and formatting defaults
below; apply overrides to the intended deliverable.

## Sources and Inputs

- Treat reference material as evidence, case or assignment details as supplied
  facts, and writing samples as guidance for vocabulary, explanatory depth,
  structure, and length. Previous generated drafts remain subject to verification.
- Read the relevant content of designated pages, saved HTML, or PDFs. Distinguish
  full text from excerpts or login screens, and identify consequential gaps in
  access. A readable saved copy does not establish that its public URL still works.
- Inspect relevant figures and images when they contribute to the assessment;
  text extraction alone does not establish their findings. Separate visible
  features, supplied interpretations, and your own diagnostic reasoning. Limit
  claims to what the supplied views establish; some conclusions require an
  unavailable image series or additional measurements.
- Supplement the designated material when the requested claims need more support.
  Prefer authoritative Japanese sources, such as public agencies and medical
  societies. Keep additions few and relevant; neither fill a citation quota nor
  sacrifice necessary evidence to a numerical cap. Respect an explicit source
  boundary: do not import detailed thresholds or treatment rules from memory.
  Follow an overview's own references only when the task or an unresolved evidence
  gap requires it.
- Borrow a sample's register and explanation style without importing its facts,
  errors, or PDF line wrapping. Match its vocabulary, sentence endings, explanatory
  depth, and degree of formality. Recent explicit preferences take precedence over
  incidental features of a sample. A clinician audience does not by itself call
  for a more formal or advanced voice than the requested student writing level.

## Facts and Assessment

- Keep supplied facts, source statements, and interpretations distinguishable.
  An omitted finding is unknown, not negative; proposed tests and actions have not
  already happened. Conversely, a documented negative or "not evident" examination
  finding is an observed result, not missing data. Give a clinical reason for
  reassessment rather than requesting it merely because the wording is cautious.
  Preserve chronology, including onset, temporary relief, and deterioration.
- Apply corrected facts to affected summaries and reasoning. Keep independent
  cases self-contained, without borrowing their findings or repeatedly comparing
  each new case with the preceding one.
- Compare items at the same explanatory level: diseases with diseases, mechanisms
  with mechanisms. Explain the relationship when a syndrome and its causes both
  appear, using hierarchy or prose rather than presenting them as peers.
- Connect each candidate or conclusion to the relevant findings. Name what a
  proposed investigation would assess rather than vaguely saying it leads to
  further testing.
- Write assessment as an evaluation of the evidence: a finding increases a
  candidate's priority; the writer does not merely intend to prioritize it.
  Explain when information is insufficient for a conclusion instead of giving
  an instruction not to conclude. Keep actual plans explicit in the plan section.
- Express relative likelihood, urgency, and the specific information that could
  change the assessment. Repeatedly appending "cannot be ruled out" adds little.
  Do not mechanically replace that phrase with "unlikely": the latter requires
  supporting evidence. Correct material errors or overstatements against sources
  before polishing language; stylistic edits should preserve clinical meaning.
- For laboratory data, use the case's reference ranges. Discuss minor deviations
  or measurement methods only when they affect the assessment.
- When using a formal score, verify its version, item definitions, weights, and
  available inputs against the designated source. Evaluate each item separately;
  a related finding does not establish the criterion. Keep missing inputs distinct
  from negative findings and a confirmed subtotal distinct from a completed score.

## Choose the Deliverable

Use the requested structure. These are defaults for the corresponding task, not
mandatory sections for every report.

### Study Report

For a symptom overview, a useful structure is definition, mechanisms, then
possible diseases. Explain how the mechanisms relate to the diseases, with enough
context to make the account understandable without reading the source first.
Keep mechanisms brief by default. For disease lists, default to disease groups
as parent bullets, with representative diseases and short distinguishing
features in indented bullets. Follow any requested alternative grouping or layout.

### Case Discussion

Introduce the case before discussing individual clues. For pain presentations,
use relevant OPQRST information to briefly establish the direction of the
differential; do not force six headings or fill missing fields with assumptions.

Address intuitive candidates and urgent conditions early. Then use relevant
background and combinations of symptoms not yet accounted for to develop the
remaining differential. Select plausible candidates rather than an exhaustive
list. Distinguish likelihood from urgency: the leading diagnosis and a condition
requiring prompt evaluation may occupy different positions on those two axes.

When one case in a report seems thin, revisit findings that could change the
ranking and explain which question or test would distinguish the candidates.
Let the available evidence determine how much space each case needs.

### Presentation Notes for Clinicians

Organize priority differentials, other differentials, and necessary history,
examinations, investigations, management, and treatment. Add a case summary only
when requested or needed to orient the reader; omit it when the user has excluded
it. Within the priority group, identify whether a candidate leads because of
likelihood, urgency, or both. Put diagnoses in parent bullets and their evidence
in subordinate bullets. History, investigations, and management usually work as
flat bullets under short subheadings unless a further hierarchy adds meaning.

Select pertinent positive and negative findings, and separate known observations
from assessments and next steps. Match the detail to an educational presentation
or an urgent consultation. For a consultation, make the question requiring the
recipient's judgment clear. Research reporting conventions when requested rather
than claiming an unverified format is standard; do not impose a named framework
over the user's requested structure.

Label the management section for management and treatment in the output language.
Include specialist consultation only when its purpose or timing affects a
treatment decision, urgent response, or transfer. Do not insert it as a routine
step for every suspected diagnosis. Account for assessments already completed and
describe the next decision. Base consultation timing on the evidence and urgency
rather than a blanket rule to consult immediately or await diagnostic certainty.

## Voice and Layout

- Keep necessary technical terms while making surrounding explanations concrete
  and natural for the intended writer. Avoid unnecessary formality and abstract
  wording without turning particular words into a universal blacklist. State
  findings, assessments, and actions directly instead of recasting them as
  administrative labels such as "an item for consideration."
- Group prose by the question it answers. Keep a finding, the diagnoses it
  suggests, and the history or tests that distinguish them in one paragraph.
  Use a single line break when the next point continues that reasoning. In
  Markdown, two trailing spaces before the newline make the break visible.
  Leave a blank line when the discussion turns to a different question.
- Use complete explanations for reasoning and evaluation. Concise fragments are
  appropriate for labels, measurements, and lists of findings. Repeated statements
  of what the writer wants to do usually belong as assessments or necessary actions,
  not as superficially varied sentence endings.
- Keep punctuation that clarifies scope or prevents misreading. Avoid inserting
  pauses mechanically, and do not optimize for a fixed comma or sentence count.
- Default to bullets rather than tables for presentation notes. Use nesting for
  relationships such as a diagnosis and its supporting evidence, not for every
  item. Prefer headings and indentation to bold emphasis. Keep length proportionate
  to the samples and purpose, omitting repetitive caveats and process narration.

## Citations

- When citations are included, place numbered references near the claims they
  support and use one bibliography and numbering sequence across the document's
  cases. Keep claim-to-source correspondence intact when adding or removing items.
- When no formal citation style is required, default to numbered entries in the
  form `linked page title - source/site name`. Include full bibliographic metadata
  when requested, and claim compliance with a named standard only after checking
  it.
- Check newly added or changed URLs against the actual referenced content.
  Distinguish unavailable links from readable saved sources; do not invent a
  replacement URL or imply that inaccessible material was read.
- Apply citation-display preferences per deliverable. Removing references from
  presentation notes does not remove them from the source report or waive evidence
  checking. Keep sources about presentation technique distinct from references
  supporting the report's substantive claims.

## Revision and Completion

Determine whether the request changes content, adds a case, creates a separate
presentation, or only adjusts formatting. Reuse established context and resolve
routine choices without repeated clarification. Ask about inaccessible essential
material or conflicting facts when they materially affect the result; continue
work that does not depend on the answer.

Respect staged requests: a source inspection and preliminary assessment need not
become a finished report before the user supplies the planned additional material.
When appending an independent case, use the requested separator and consistent
headings, while preserving earlier cases except for necessary structural changes
or corrections that actually apply to them.

Revise the intended artifact and affected reasoning. For formatting-only edits,
preserve wording, facts, certainty, and ordering except where the requested format
requires a change. For substantive edits, revisit the relevant evidence rather
than restarting all research. Preserve the original report when a separate output
is requested.

Follow applicable user or environment requirements to use `yomiyasu` for Japanese
prose. Its language review complements evidence checking and does not certify
medical correctness. Keep its procedures in that skill rather than duplicating
them here.

Finish when the requested artifact is updated, its claims and uncertainty match
the evidence, and its structure and citations follow the current instructions.
Check the affected scope, fix identified problems, and report meaningful limits
of verification. Additional research, repeated reviews, or long audit documents
should have a concrete purpose in the current request.
