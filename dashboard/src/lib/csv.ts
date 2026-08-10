// csv.ts
// CSV-Export der gefilterten Rohdaten – für die Weiterverarbeitung in
// SPSS/R/Excel und als Anhang der Arbeit.

/** Ein Feld nach RFC 4180: Anführungszeichen verdoppeln, Feld einfassen. */
function escapeField(value: unknown): string {
  if (value === null || value === undefined) return "";
  const text = String(value);
  return `"${text.replace(/"/g, '""')}"`;
}

/** Baut eine CSV-Zeichenkette aus Kopfzeile und Datenzeilen. */
export function toCsv(
  header: readonly string[],
  rows: readonly (readonly unknown[])[],
): string {
  const lines = [
    header.map(escapeField).join(";"),
    ...rows.map((row) => row.map(escapeField).join(";")),
  ];
  // CRLF und Semikolon: so öffnet Excel in der Schweizer Gebietsschema-
  // Einstellung die Datei ohne Import-Dialog.
  return lines.join("\r\n");
}

/** Bietet eine CSV-Zeichenkette als Download an. */
export function downloadCsv(filename: string, csv: string): void {
  // BOM voran, sonst zeigt Excel Umlaute falsch an.
  const blob = new Blob([`﻿${csv}`], {
    type: "text/csv;charset=utf-8;",
  });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
}