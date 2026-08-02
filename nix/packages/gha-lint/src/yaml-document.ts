import { LineCounter, parseDocument, type Document, type Node } from "yaml";

export type ParsedYaml = {
  document: Document.Parsed;
  lineCounter: LineCounter;
  value: unknown;
};

export function parseYaml(source: string): ParsedYaml {
  const lineCounter = new LineCounter();
  const document = parseDocument(source, {
    keepSourceTokens: true,
    lineCounter,
    prettyErrors: false,
    uniqueKeys: true
  });

  return {
    document,
    lineCounter,
    value: document.errors.length === 0 ? document.toJS({ maxAliasCount: 100 }) : undefined
  };
}

export function nodeAt(document: Document.Parsed, path: readonly (string | number)[]): Node | null {
  const node = document.getIn(path, true);
  return node && typeof node === "object" ? (node as Node) : null;
}
