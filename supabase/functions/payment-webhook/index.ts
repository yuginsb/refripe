// payment-webhook — notifications des prestataires de paiement.
//
// URL : /functions/v1/payment-webhook?provider=wave|orange_money|sandbox
// verify_jwt = false (appelé par Wave / Orange Money) : l'authenticité est
// garantie par la signature HMAC (Wave, sandbox) ou le notif_token (Orange Money).
//
// Idempotent : chaque événement est journalisé dans payment_events
// (unique provider + event_id) ; confirm_payment / fail_payment sont eux-mêmes
// idempotents côté SQL. Transition : PAYMENT_PENDING → PAID → AWAITING_SHIPMENT.

import { errorResponse, json } from "../_shared/http.ts";
import { type PaymentProvider, providerByName, timingSafeEqual, type WebhookEvent, WebhookSignatureError } from "../_shared/payments.ts";
import { adminClient } from "../_shared/supabase.ts";

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") return errorResponse("Méthode non autorisée", 405);

  const providerName = new URL(req.url).searchParams.get("provider");
  const found = providerByName(providerName);
  if (!found) return errorResponse("Prestataire inconnu", 400);
  const provider: PaymentProvider = found;

  const rawBody = await req.text();
  const admin = adminClient();

  let event: WebhookEvent;
  try {
    event = await provider.parseWebhook(req.headers, rawBody);
  } catch (e) {
    if (e instanceof WebhookSignatureError || e instanceof SyntaxError) {
      console.warn("payment-webhook: signature/corps invalide", provider.name, (e as Error).message);
      return errorResponse("Signature invalide", 401);
    }
    console.error("payment-webhook: parse", e);
    return errorResponse("Erreur interne", 500);
  }

  try {
    // Résolution de la commande et vérification complémentaire.
    let orderId = event.orderId;
    if (event.notifToken) {
      // Orange Money : le notif_token doit correspondre à une session connue.
      const { data: payment, error } = await admin
        .from("payments")
        .select("order_id, notif_token")
        .eq("provider", provider.name)
        .eq("notif_token", event.notifToken)
        .maybeSingle<{ order_id: string; notif_token: string }>();
      if (error) throw error;
      if (!payment || !timingSafeEqual(payment.notif_token, event.notifToken)) {
        return errorResponse("Signature invalide", 401);
      }
      orderId = payment.order_id;
    }
    if (!orderId) return json({ received: true, ignored: "no_order" });

    // Idempotence : premier passage uniquement.
    const { error: dupError } = await admin
      .from("payment_events")
      .insert({ provider: provider.name, event_id: event.eventId, order_id: orderId, payload: event.raw });
    if (dupError) {
      if (dupError.code === "23505") return json({ received: true, duplicate: true });
      throw dupError;
    }

    if (event.outcome === "ignored") return json({ received: true, ignored: true });

    try {
      return await applyEvent(orderId);
    } catch (e) {
      // Échec du traitement : on « libère » l'événement pour que le retry du prestataire soit rejoué.
      await admin.from("payment_events").delete().eq("provider", provider.name).eq("event_id", event.eventId);
      throw e;
    }
  } catch (e) {
    console.error("payment-webhook", provider.name, e);
    return errorResponse("Erreur interne", 500);
  }

  async function applyEvent(orderId: string): Promise<Response> {
    if (event.outcome === "succeeded") {
      // Montant : celui de l'événement s'il est fourni, sinon celui de la session enregistrée.
      let amount = event.amount;
      if (amount == null) {
        const { data: p } = await admin
          .from("payments").select("amount")
          .eq("order_id", orderId).eq("provider", provider.name)
          .order("created_at", { ascending: false }).limit(1)
          .maybeSingle<{ amount: number }>();
        amount = p?.amount ?? null;
      }
      const { data, error } = await admin.rpc("confirm_payment", {
        p_order_id: orderId,
        p_amount: amount,
        p_provider: provider.name,
        p_provider_ref: event.providerRef,
      });
      if (error) throw error;
      if (data === "CANCELLED") {
        // Paiement arrivé après annulation (délai de 30 min dépassé) : remboursement manuel.
        console.error("payment-webhook: paiement reçu pour une commande annulée, à rembourser", orderId);
      }
      return json({ received: true, status: data });
    }

    const { data, error } = await admin.rpc("fail_payment", { p_order_id: orderId, p_provider: provider.name });
    if (error) throw error;
    return json({ received: true, status: data });
  }
});
