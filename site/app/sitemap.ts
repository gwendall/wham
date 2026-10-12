import type { MetadataRoute } from "next";

export default function sitemap(): MetadataRoute.Sitemap {
  return [{ url: "https://wham.sh", changeFrequency: "monthly", priority: 1 }];
}
