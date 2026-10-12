// The installers go out as plain text with a short cache, so a fix reaches
// `curl | sh` within minutes of a deploy.
export function scriptResponse(body: string): Response {
  return new Response(body, {
    headers: {
      "content-type": "text/plain; charset=utf-8",
      "cache-control": "public, max-age=300, s-maxage=300",
      "x-content-type-options": "nosniff",
    },
  });
}
