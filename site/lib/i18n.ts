import type en from "@/messages/en.json";
import type { Locale } from "@/lib/locales";

export * from "@/lib/locales";

// Each language speaks from messages/<code>.json, which
// scripts/check-messages.mjs holds to English's keys, tags and placeholders.
export type Messages = typeof en;

const MESSAGES: Record<Locale, () => Promise<Messages>> = {
  en: () => import("@/messages/en.json").then((m) => m.default),
  fr: () => import("@/messages/fr.json").then((m) => m.default),
  es: () => import("@/messages/es.json").then((m) => m.default),
  de: () => import("@/messages/de.json").then((m) => m.default),
  it: () => import("@/messages/it.json").then((m) => m.default),
  pt: () => import("@/messages/pt.json").then((m) => m.default),
  ja: () => import("@/messages/ja.json").then((m) => m.default),
  ko: () => import("@/messages/ko.json").then((m) => m.default),
  zh: () => import("@/messages/zh.json").then((m) => m.default),
};

export const messages = (locale: Locale) => MESSAGES[locale]();
