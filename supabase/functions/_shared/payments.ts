// Abstraction des prestataires de paiement mobile money (séquestre ReFripe).
//
// PAYMENT_MODE=sandbox (défaut) : tous les paiements passent par SandboxProvider,
//   qui confirme automatiquement (aucun argent ne circule).
// PAYMENT_MODE=live : Wave ou Orange Money selon le moyen choisi par l'acheteuse.
//
// Aucune clé n'est en dur : tout vient des variables d'environnement
// (`supabase secrets set ...`, voir docs/BACKEND.md).

import { hmacSha256Hex, optionalEnv, requireEnv, timingSafeEqual, verifyTimestampedSignature } from "./http.ts";

export type PaymentMethod = "wave" | "orange_money";
export type ProviderName = "sandbox" | "wave" | "orange_money";

export interface CreateSessionInput {
  orderId: string;
  amount: number;          // FCFA (XOF n'a pas de sous-unité)
  currency: "XOF";
  method: PaymentMethod;
  description: string;
  successUrl: string;      // deep link de retour dans l'app
  errorUrl: string;
  webhookUrl: string;      // URL publique de payment-webhook?provider=...
}

export interface PaymentSession {
  sessionId: string;
  checkoutUrl: string | null;   // à ouvrir côté app (Wave / Orange Money), null en sandbox
  notifToken?: string | null;   // Orange Money : jeton renvoyé dans la notification
  raw: unknown;
}

export interface WebhookEvent {
  eventId: string;              // identifiant unique (idempotence)
  orderId: string | null;       // null si le prestataire ne le renvoie pas (OM : résolu via notif_token)
  sessionId: string | null;
  notifToken?: string | null;
  outcome: "succeeded" | "failed" | "ignored";
  amount: number | null;
  providerRef: string | null;   // identifiant de transaction côté prestataire
  raw: unknown;
}

export interface PaymentProvider {
  readonly name: ProviderName;
  /** true : la session est confirmée immédiatement sans webhook (sandbox). */
  readonly autoConfirm: boolean;
  createSession(input: CreateSessionInput): Promise<PaymentSession>;
  /** Vérifie la signature puis traduit la notification. Lève une erreur si invalide. */
  parseWebhook(headers: Headers, rawBody: string): Promise<WebhookEvent>;
}

export class WebhookSignatureError extends Error {}

// ---------------------------------------------------------------------------
// Sandbox
// ---------------------------------------------------------------------------
export class SandboxProvider implements PaymentProvider {
  readonly name = "sandbox" as const;
  readonly autoConfirm: boolean;

  constructor() {
    // SANDBOX_AUTO_CONFIRM=false pour tester le webhook à la main (curl signé).
    this.autoConfirm = optionalEnv("SANDBOX_AUTO_CONFIRM", "true") !== "false";
  }

  createSession(input: CreateSessionInput): Promise<PaymentSession> {
    return Promise.resolve({
      sessionId: `sbx_${crypto.randomUUID()}`,
      checkoutUrl: null,
      raw: { sandbox: true, method: input.method, amount: input.amount },
    });
  }

  async parseWebhook(headers: Headers, rawBody: string): Promise<WebhookEvent> {
    const secret = requireEnv("SANDBOX_WEBHOOK_SECRET");
    const ok = await verifyTimestampedSignature(headers.get("x-refripe-signature"), rawBody, secret);
    if (!ok) throw new WebhookSignatureError("Signature sandbox invalide");
    const body = JSON.parse(rawBody) as {
      id: string; order_id: string; session_id?: string; status: string; amount: number;
    };
    return {
      eventId: body.id,
      orderId: body.order_id,
      sessionId: body.session_id ?? null,
      outcome: body.status === "succeeded" ? "succeeded" : body.status === "failed" ? "failed" : "ignored",
      amount: Number(body.amount),
      providerRef: body.id,
      raw: body,
    };
  }
}

// ---------------------------------------------------------------------------
// Wave — API Checkout (https://docs.wave.com/checkout)
// Variables : WAVE_API_KEY, WAVE_WEBHOOK_SECRET, (option) WAVE_AGGREGATED_MERCHANT_ID
// ---------------------------------------------------------------------------
export class WaveProvider implements PaymentProvider {
  readonly name = "wave" as const;
  readonly autoConfirm = false;
  private readonly baseUrl = optionalEnv("WAVE_API_BASE", "https://api.wave.com");

  async createSession(input: CreateSessionInput): Promise<PaymentSession> {
    // TODO(Wave) : valider avec le contrat marchand — champs obligatoires, plafond
    // par transaction, signature des requêtes API si activée sur la clé
    // (en-tête Wave-Signature côté requête), et usage de aggregated_merchant_id.
    const body: Record<string, unknown> = {
      amount: String(input.amount),
      currency: input.currency,
      client_reference: input.orderId,
      success_url: input.successUrl,
      error_url: input.errorUrl,
    };
    const aggregated = optionalEnv("WAVE_AGGREGATED_MERCHANT_ID");
    if (aggregated) body.aggregated_merchant_id = aggregated;

    const res = await fetch(`${this.baseUrl}/v1/checkout/sessions`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${requireEnv("WAVE_API_KEY")}`,
        "Content-Type": "application/json",
        "Idempotency-Key": `refripe-${input.orderId}`,
      },
      body: JSON.stringify(body),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      throw new Error(`Wave checkout ${res.status}: ${JSON.stringify(data)}`);
    }
    return {
      sessionId: String(data.id),
      checkoutUrl: data.wave_launch_url ?? null,
      raw: data,
    };
  }

  async parseWebhook(headers: Headers, rawBody: string): Promise<WebhookEvent> {
    // Wave signe les webhooks : `Wave-Signature: t=<timestamp>,v1=<hmac>` avec
    // HMAC-SHA256(WAVE_WEBHOOK_SECRET, timestamp + corps brut).
    // TODO(Wave) : confirmer le schéma exact des événements sur le compte marchand.
    const ok = await verifyTimestampedSignature(
      headers.get("wave-signature"), rawBody, requireEnv("WAVE_WEBHOOK_SECRET"),
    );
    if (!ok) throw new WebhookSignatureError("Signature Wave invalide");

    const evt = JSON.parse(rawBody) as {
      id: string;
      type: string;
      data?: {
        id?: string; client_reference?: string; amount?: string;
        payment_status?: string; checkout_status?: string; transaction_id?: string;
      };
    };
    const d = evt.data ?? {};
    let outcome: WebhookEvent["outcome"] = "ignored";
    if (evt.type === "checkout.session.completed" && d.payment_status === "succeeded") outcome = "succeeded";
    else if (evt.type === "checkout.session.payment_failed" ||
             (evt.type === "checkout.session.completed" && d.payment_status === "cancelled")) outcome = "failed";

    return {
      eventId: evt.id,
      orderId: d.client_reference ?? null,
      sessionId: d.id ?? null,
      outcome,
      amount: d.amount != null ? Number(d.amount) : null,
      providerRef: d.transaction_id ?? d.id ?? null,
      raw: evt,
    };
  }
}

// ---------------------------------------------------------------------------
// Orange Money — Web Payment (API Orange Developer « Orange Money Web Pay »)
// Variables : OM_CLIENT_ID, OM_CLIENT_SECRET, OM_MERCHANT_KEY, OM_COUNTRY (ci par défaut)
// ---------------------------------------------------------------------------
export class OrangeMoneyProvider implements PaymentProvider {
  readonly name = "orange_money" as const;
  readonly autoConfirm = false;
  private readonly baseUrl = optionalEnv("OM_API_BASE", "https://api.orange.com");

  private async accessToken(): Promise<string> {
    const basic = btoa(`${requireEnv("OM_CLIENT_ID")}:${requireEnv("OM_CLIENT_SECRET")}`);
    const res = await fetch(`${this.baseUrl}/oauth/v3/token`, {
      method: "POST",
      headers: {
        Authorization: `Basic ${basic}`,
        "Content-Type": "application/x-www-form-urlencoded",
        Accept: "application/json",
      },
      body: "grant_type=client_credentials",
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok || !data.access_token) throw new Error(`Orange OAuth ${res.status}`);
    return data.access_token as string;
  }

  async createSession(input: CreateSessionInput): Promise<PaymentSession> {
    // TODO(Orange Money) : l'API Web Pay est ouverte pays par pays (« ci » pour la
    // Côte d'Ivoire). Le Sénégal passe par l'API Sonatel / Orange Money SN, à
    // brancher dans une implémentation dédiée (ou via un agrégateur).
    // En environnement de test Orange, la devise est « OUV » au lieu de « XOF ».
    const country = optionalEnv("OM_COUNTRY", "ci");
    const currency = optionalEnv("OM_CURRENCY", input.currency);
    const token = await this.accessToken();
    const res = await fetch(`${this.baseUrl}/orange-money-webpay/${country}/v1/webpayment`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify({
        merchant_key: requireEnv("OM_MERCHANT_KEY"),
        currency,
        order_id: input.orderId,
        amount: input.amount,
        return_url: input.successUrl,
        cancel_url: input.errorUrl,
        notif_url: input.webhookUrl,
        lang: "fr",
        reference: "ReFripe",
      }),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(`Orange Money webpayment ${res.status}: ${JSON.stringify(data)}`);
    return {
      sessionId: String(data.pay_token),
      checkoutUrl: data.payment_url ?? null,
      notifToken: data.notif_token ?? null,
      raw: data,
    };
  }

  parseWebhook(_headers: Headers, rawBody: string): Promise<WebhookEvent> {
    // Orange Money n'envoie pas de HMAC : la notification contient le notif_token
    // reçu à la création de la session. La vérification (comparaison en temps
    // constant avec payments.notif_token) est faite par payment-webhook.
    // TODO(Orange Money) : restreindre en plus l'appel aux IP Orange si possible.
    const body = JSON.parse(rawBody) as { status?: string; notif_token?: string; txnid?: string };
    if (!body.notif_token) throw new WebhookSignatureError("notif_token manquant");
    const status = (body.status ?? "").toUpperCase();
    return Promise.resolve({
      eventId: `${body.notif_token}:${status}`,
      orderId: null,
      sessionId: null,
      notifToken: body.notif_token,
      outcome: status === "SUCCESS" ? "succeeded" : status === "FAILED" || status === "EXPIRED" ? "failed" : "ignored",
      amount: null,
      providerRef: body.txnid ?? null,
      raw: body,
    });
  }
}

// ---------------------------------------------------------------------------

export function paymentMode(): "sandbox" | "live" {
  return optionalEnv("PAYMENT_MODE", "sandbox") === "live" ? "live" : "sandbox";
}

/** Prestataire utilisé pour créer une session selon le moyen choisi. */
export function providerForMethod(method: PaymentMethod): PaymentProvider {
  if (paymentMode() === "sandbox") return new SandboxProvider();
  return method === "wave" ? new WaveProvider() : new OrangeMoneyProvider();
}

/** Prestataire désigné par le paramètre `?provider=` du webhook. */
export function providerByName(name: string | null): PaymentProvider | null {
  switch (name) {
    case "sandbox": return new SandboxProvider();
    case "wave": return new WaveProvider();
    case "orange_money": return new OrangeMoneyProvider();
    default: return null;
  }
}

/** Signe un corps de webhook sandbox (utile pour les tests). */
export async function signSandboxPayload(rawBody: string, secret: string): Promise<string> {
  const t = Math.floor(Date.now() / 1000).toString();
  return `t=${t},v1=${await hmacSha256Hex(secret, `${t}${rawBody}`)}`;
}

export { timingSafeEqual };
