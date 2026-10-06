/** The API base. Inlined at build time, so changing it needs a rebuild. */
export const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "https://api.notchmetrics.com";

export class ApiError extends Error {
  readonly status: number;
  readonly code: string;
  constructor(status: number, code: string, message: string) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.code = code;
  }
}

/**
 * Every call is credentialed: the dashboard authenticates with the session
 * cookie Better Auth set, never with a bearer token. Bearer tokens belong to
 * the desktop app, and minting one for a browser would mean storing it
 * somewhere a script can read.
 */
export async function api<T>(path: string, init: RequestInit = {}): Promise<T> {
  const response = await fetch(`${API_URL}${path}`, {
    ...init,
    credentials: "include",
    headers: {
      ...(init.body ? { "content-type": "application/json" } : {}),
      ...(init.headers ?? {}),
    },
  });

  if (!response.ok) {
    const body = (await response.json().catch(() => ({}))) as {
      code?: string;
      message?: string;
    };
    throw new ApiError(
      response.status,
      body.code ?? "UNKNOWN",
      body.message ?? "Something went wrong.",
    );
  }

  // 204 has no body to parse, and `.json()` on one throws.
  return response.status === 204 ? (undefined as T) : ((await response.json()) as T);
}
