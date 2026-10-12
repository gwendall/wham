import { INSTALL_SH } from "@/generated/scripts";
import { scriptResponse } from "@/lib/script-response";

// Also served at /install.sh, and at / for curl and friends (see next.config.ts).
export function GET() {
  return scriptResponse(INSTALL_SH);
}
