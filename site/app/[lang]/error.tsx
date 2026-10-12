"use client";

import { useEffect } from "react";
import { ErrorScreen } from "@/components/ErrorScreen";

// A page that throws while rendering, inside the layout and in its language.
export default function PageError({ error, retry }: { error: Error & { digest?: string }; retry: () => void }) {
  useEffect(() => console.error(error), [error]);
  return <ErrorScreen kind="failed" retry={retry} digest={error.digest} />;
}
