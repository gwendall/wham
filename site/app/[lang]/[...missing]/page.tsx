import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { isLocale, messages } from "@/lib/i18n";

export async function generateMetadata({ params }: PageProps<"/[lang]/[...missing]">): Promise<Metadata> {
  const { lang } = await params;
  const { errors } = await messages(isLocale(lang) ? lang : "en");
  return { title: `${errors.notFound.eyebrow} · Wham` };
}

// Any deeper URL, so its 404 renders inside the layout, in the URL's language.
export default function Missing() {
  notFound();
}
