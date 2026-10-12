import { Fragment, type ReactNode } from "react";

// A message with markup, "every line of it is on <github>GitHub</github>",
// rendered with one function per tag. Tags do not nest; an empty one,
// "<heart></heart>", places an element without text.
export function rich(text: string, tags: Record<string, (children: string) => ReactNode>): ReactNode {
  const parts: ReactNode[] = [];
  const pattern = /<(\w+)>(.*?)<\/\1>/g;
  let last = 0;
  for (const match of text.matchAll(pattern)) {
    const [whole, tag, inner] = match;
    const render = tags[tag];
    if (!render) throw new Error(`rich: no renderer for <${tag}> in "${text}"`);
    parts.push(text.slice(last, match.index), <Fragment key={match.index}>{render(inner)}</Fragment>);
    last = match.index + whole.length;
  }
  parts.push(text.slice(last));
  return parts;
}
