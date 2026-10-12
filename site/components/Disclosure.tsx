"use client";

import { domAnimation, LazyMotion, m, useReducedMotion, type Transition } from "motion/react";
import { useId, useState, useSyncExternalStore, type ReactNode } from "react";

// A row that opens in place: the panel grows to its height and fades in, the
// plus turns into an x, both on the same ease-out. A closed panel stays in the
// page (inert), so find-in-page and search engines still read it. A link to
// the row's id (#developers) opens it. With reduced motion it opens at once.
const EASE = [0.22, 1, 0.36, 1] as const;
const DURATION = 0.32;

export function Disclosure({
  id,
  heading: Heading = "h3",
  summary,
  className = "",
  buttonClassName = "",
  children,
}: {
  id?: string;
  heading?: "h2" | "h3";
  summary: ReactNode;
  className?: string;
  buttonClassName?: string;
  children: ReactNode;
}) {
  const [open, setOpen] = useState(false);
  const reduce = useReducedMotion();
  const panel = useId();

  // Opened by a link to it: on load, or when the hash changes to its id.
  const hash = useSyncExternalStore(onHashChange, () => window.location.hash, () => "");
  const linked = Boolean(id) && hash === `#${id}`;
  const [wasLinked, setWasLinked] = useState(false);
  if (linked !== wasLinked) {
    setWasLinked(linked);
    if (linked) setOpen(true);
  }

  const transition = { duration: reduce ? 0 : DURATION, ease: EASE };
  return (
    <LazyMotion features={domAnimation} strict>
      <div id={id} data-open={open} className={className}>
        <Heading className="m-0">
          <button
            type="button"
            aria-expanded={open}
            aria-controls={panel}
            onClick={() => setOpen((o) => !o)}
            className={`group flex w-full cursor-pointer items-center justify-between gap-4 text-left ${buttonClassName}`}
          >
            {summary}
            <Plus open={open} transition={transition} />
          </button>
        </Heading>
        <m.div
          id={panel}
          initial={false}
          animate={open ? { height: "auto", opacity: 1 } : { height: 0, opacity: 0 }}
          transition={transition}
          style={{ overflow: "hidden" }}
          inert={!open}
        >
          {children}
        </m.div>
      </div>
    </LazyMotion>
  );
}

function onHashChange(update: () => void) {
  window.addEventListener("hashchange", update);
  return () => window.removeEventListener("hashchange", update);
}

// A 10 px plus of 2 px bars in a 24 px disc; an eighth of a turn makes it an x.
function Plus({ open, transition }: { open: boolean; transition: Transition }) {
  return (
    <m.span
      aria-hidden="true"
      initial={false}
      animate={{ rotate: open ? 45 : 0 }}
      transition={transition}
      className="flex size-6 shrink-0 items-center justify-center rounded-full bg-fg/6 transition-colors group-hover:bg-fg/12"
    >
      <svg width="10" height="10" viewBox="0 0 10 10" fill="currentColor" shapeRendering="crispEdges">
        <rect x="4" y="0" width="2" height="10" />
        <rect x="0" y="4" width="10" height="2" />
      </svg>
    </m.span>
  );
}
