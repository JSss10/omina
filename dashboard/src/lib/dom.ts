// dom.ts
// Kleine Helfer zum Bauen von DOM-Knoten.
//
// Bewusst über `createElement` + Textknoten statt über `innerHTML`: die
// Inhalte des Dashboards (Namen, Screen-Bezeichnungen, `properties`) kommen
// aus Eingaben der Testpersonen. Über `innerHTML` eingesetzt wäre jeder davon
// ein möglicher Einfallsweg für eingeschleustes Markup; als Textknoten kann
// keiner davon zu Markup werden.

type AttrValue = string | number | boolean | null | undefined;

export type Attrs = Record<string, AttrValue>;
export type Child = Node | string | number | null | undefined | false;

/** Hängt Kinder an einen Knoten an; Strings und Zahlen werden zu Textknoten. */
export function append(parent: Node, children: Child | Child[]): void {
  const list = Array.isArray(children) ? children : [children];
  for (const child of list) {
    if (child === null || child === undefined || child === false) continue;
    parent.appendChild(
      typeof child === "string" || typeof child === "number"
        ? document.createTextNode(String(child))
        : child,
    );
  }
}

/**
 * Erzeugt ein Element mit Attributen und Kindern.
 * `true` setzt ein Attribut ohne Wert, `false`/`null`/`undefined` lassen es weg.
 */
export function el<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  attrs: Attrs = {},
  children: Child | Child[] = [],
): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag);
  for (const [name, value] of Object.entries(attrs)) {
    if (value === null || value === undefined || value === false) continue;
    node.setAttribute(name, value === true ? "" : String(value));
  }
  append(node, children);
  return node;
}

/** Leert einen Knoten. */
export function clear(node: Node): void {
  while (node.firstChild !== null) {
    node.removeChild(node.firstChild);
  }
}

/** Ersetzt den Inhalt eines Knotens. */
export function render(parent: Node, children: Child | Child[]): void {
  clear(parent);
  append(parent, children);
}

/** Element per Selektor holen und dabei sicherstellen, dass es existiert. */
export function must<T extends Element>(selector: string): T {
  const node = document.querySelector<T>(selector);
  if (node === null) {
    throw new Error(`Element nicht gefunden: ${selector}`);
  }
  return node;
}