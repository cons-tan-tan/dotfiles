export type DiagnosticSource = "actions-language-service" | "schemastore" | "shellcheck" | "yaml";
export type DiagnosticSeverity = "error" | "warning" | "information";

export type LintDiagnostic = {
  file: string;
  source: DiagnosticSource;
  severity: DiagnosticSeverity;
  message: string;
  line: number;
  column: number;
  endLine: number;
  endColumn: number;
  code?: string;
};

export function sortAndDeduplicate(diagnostics: LintDiagnostic[]): LintDiagnostic[] {
  const sorted = diagnostics.toSorted((left, right) => {
    return (
      left.file.localeCompare(right.file) ||
      left.line - right.line ||
      left.column - right.column ||
      left.source.localeCompare(right.source) ||
      left.message.localeCompare(right.message)
    );
  });

  const seen = new Set<string>();
  return sorted.filter(diagnostic => {
    const key = JSON.stringify(diagnostic);
    if (seen.has(key)) {
      return false;
    }
    seen.add(key);
    return true;
  });
}

export function formatText(diagnostic: LintDiagnostic): string {
  const code = diagnostic.code ? ` [${diagnostic.code}]` : "";
  return `${diagnostic.file}:${diagnostic.line}:${diagnostic.column}: ${diagnostic.severity}: ${diagnostic.message} (${diagnostic.source})${code}`;
}
