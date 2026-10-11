// Utilitaires HTTP / crypto partagés par les Edge Functions ReFripe.

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
}

export function errorResponse(message: string, status = 400, code?: string): Response {
  return json({ error: message, code }, status);
}

export function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Variable d'environnement manquante : ${name}`);
  return value;
}

export function optionalEnv(name: string, fallback = ""): string {
  return Deno.env.get(name) ?? fallback;
}

const encoder = new TextEncoder();

export async function hmacSha256Hex(secret: string, payload: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, encoder.encode(payload));
  return Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Comparaison en temps constant de deux chaînes. */
export function timingSafeEqual(a: string, b: string): boolean {
  const ab = encoder.encode(a);
  const bb = encoder.encode(b);
  let diff = ab.length ^ bb.length;
  const len = Math.max(ab.length, bb.length);
  for (let i = 0; i < len; i++) diff |= (ab[i] ?? 0) ^ (bb[i] ?? 0);
  return diff === 0;
}

/**
 * Vérifie un en-tête de signature au format `t=<unix>,v1=<hex>[,v1=<hex>...]`
 * où v1 = HMAC-SHA256(secret, `${t}${rawBody}`) (format utilisé par Wave et
 * par notre sandbox). Rejette les signatures de plus de `toleranceSec`.
 */
export async function verifyTimestampedSignature(
  header: string | null,
  rawBody: string,
  secret: string,
  toleranceSec = 300,
): Promise<boolean> {
  if (!header || !secret) return false;
  let timestamp = "";
  const candidates: string[] = [];
  for (const part of header.split(",")) {
    const [k, v] = part.trim().split("=", 2);
    if (k === "t") timestamp = v ?? "";
    if (k === "v1" && v) candidates.push(v);
  }
  const t = Number(timestamp);
  if (!timestamp || !Number.isFinite(t) || candidates.length === 0) return false;
  if (Math.abs(Date.now() / 1000 - t) > toleranceSec) return false;
  const expected = await hmacSha256Hex(secret, `${timestamp}${rawBody}`);
  return candidates.some((c) => timingSafeEqual(c.toLowerCase(), expected));
}
