"use client";

import { ErrorScreen } from "@/components/ErrorScreen";

// A language the site does not have (/xx), or a page under one it has
// (/fr/anything, through [...missing]): in that language, English otherwise.
export default function NotFound() {
  return <ErrorScreen kind="notFound" />;
}
