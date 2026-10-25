Plan a complete series of small commits for the requested change. Each commit must have a concrete role and a distinct review question that its subject can describe. When splitting and combining are both reasonable, prefer more commits. Keep unrelated work out.

Combine only when a proposed split lacks distinct review questions or conflicts with an explicit per-commit repository requirement. Shared motivation, the same feature or file, few changed lines, and dependencies alone do not justify combining.

For example, a validation helper and its adoption in each API, a function signature and its caller updates, or dev and prod configuration can be separate commits, even for one-line changes. A distinct test scenario or a standalone explanation of a non-obvious decision can also be a commit. Use these examples to judge boundaries in the actual diff.

Commits may depend on earlier or later commits. Definitions and references, extraction and adoption, implementation and tests, and source and generated output can be separate. Independent reverts, complete functionality, and passing builds or tests at intermediate commits are required only when the repository explicitly requires them. Order commits to reduce temporary inconsistencies while preserving meaningful boundaries.

Keep assertions for one test scenario, both sides of a pure file move, and output from one generation or formatting operation together. Reference updates after a move can be separate. Avoid splitting equivalent references by occurrence or expressions by line, and avoid scaffolding, temporary APIs, or add-then-remove work created merely for extra commits or intermediate builds.

Complete all requested work and necessary follow-ups in this series. The final state must have consistent references, configuration, and generated output, with required validation completed and any unresolved failures reported. Briefly explain non-obvious combinations or dependencies.
