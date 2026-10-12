import { UNINSTALL_SH } from "@/generated/scripts";
import { scriptResponse } from "@/lib/script-response";

// Also served at /uninstall.sh (see next.config.ts).
export function GET() {
  return scriptResponse(UNINSTALL_SH);
}
