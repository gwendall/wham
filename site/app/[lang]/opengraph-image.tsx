import { ogImage, ogSize, ogWords } from "@/lib/og";

export const contentType = "image/png";

export async function generateImageMetadata({ params }: { params: { lang: string } }) {
  const { lang } = await params;
  return [{ id: "card", alt: (await ogWords(lang)).alt, size: ogSize, contentType }];
}

export default async function Image({ params }: { params: Promise<{ lang: string }> }) {
  return ogImage((await ogWords((await params).lang)).card);
}
