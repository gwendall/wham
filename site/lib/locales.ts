// The site's languages. English lives at /, every other one under its code:
// /fr, /ja. Safe for the browser: the messages themselves load in lib/i18n.ts.
export const LOCALES = ["en", "fr", "es", "de", "it", "pt", "ja", "ko", "zh"] as const;
export type Locale = (typeof LOCALES)[number];

// `tag` is the page's lang and hreflang, `og` Open Graph's locale, `name` what
// the language switcher shows, in the language itself.
export const LANGUAGES: Record<Locale, { name: string; tag: string; og: string }> = {
  en: { name: "English", tag: "en", og: "en_US" },
  fr: { name: "Français", tag: "fr", og: "fr_FR" },
  es: { name: "Español", tag: "es", og: "es_ES" },
  de: { name: "Deutsch", tag: "de", og: "de_DE" },
  it: { name: "Italiano", tag: "it", og: "it_IT" },
  pt: { name: "Português", tag: "pt-BR", og: "pt_BR" },
  ja: { name: "日本語", tag: "ja", og: "ja_JP" },
  ko: { name: "한국어", tag: "ko", og: "ko_KR" },
  zh: { name: "简体中文", tag: "zh-Hans", og: "zh_CN" },
};

// The cookie the language switcher sets, which / then follows.
export const LANG_COOKIE = "wham-lang";

export const isLocale = (value: string): value is Locale => (LOCALES as readonly string[]).includes(value);

export const pathFor = (locale: Locale) => (locale === "en" ? "/" : `/${locale}`);

// "Copy: {command}" with { command: "npx wham.sh" }.
export const fill = (text: string, values: Record<string, string>) =>
  text.replace(/\{(\w+)\}/g, (all, key: string) => values[key] ?? all);
