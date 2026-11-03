// payment-init — crée la session de paiement (Wave / Orange Money) d'une commande
// PAYMENT_PENDING appartenant à l'acheteuse authentifiée.
//
// POST { "order_id": "<uuid>" }   (JWT utilisateur requis : verify_jwt = true)
// → 200 { payment_id, provider, status, checkout_url, ussd_code, masked_phone, amount, method }
//
// v3 (paiement guidé) : l'app ouvre `checkout_url` (Wave : wave_launch_url, Orange Money :
// payment_url) avec UIApplication.open / SFSafariViewController, ou affiche `ussd_code`
// (OM_USSD_CODE, optionnel), puis interroge la commande toutes les 3 s jusqu'à PAID.
// `masked_phone` = numéro du compte masqué (« 07 07 •• •• 07 ») pour l'écran de confirmation.
//
// En sandbox (PAYMENT_MODE=sandbox, défaut), le paiement est confirmé
// immédiatement : la commande passe PAYMENT_PENDING → PAID → AWAITING_SHIPMENT.

import { errorResponse, json, optionalEnv, requireEnv } from "../_shared/http.ts";
import { type PaymentMethod, providerForMethod } from "../_shared/payments.ts";
import { adminClient, userClient } from "../_shared/supabase.ts";

/** "+2250707070707" → "07 07 •• •• 07" ; "+221770000004" → "77 ••• •• 04". */
function maskPhone(raw: string | null | undefined): string | null {
  if (!raw) return null;
  let digits = raw.replace(/\D/g, "");
  if (digits.startsWith("00")) digits = digits.slice(2);
  if (digits.startsWith("225") && digits.length === 13) digits = digits.slice(3);
  else if (digits.startsWith("221") && digits.length === 12) digits = digits.slice(3);
  if (digits.length === 10) {
    return `${digits.slice(0, 2)} ${digits.slice(2, 4)} •• •• ${digits.slice(8, 10)}`;
  }
  if (digits.length === 9) {
    return `${digits.slice(0, 2)} ••• •• ${digits.slice(7, 9)}`;
  }
  return digits.length > 4 ? `•• ${digits.slice(-2)}` : null;
}

interface OrderRow {
  id: string;
  buyer_id: string;
  listing_title: string;
  item_price: number;
  delivery_fee: number;
  payment: PaymentMethod;
  status: string;
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") return errorResponse("Méthode non autorisée", 405);

  const authorization = req.headers.get("Authorization");
  if (!authorization) return errorResponse("Connecte-toi pour continuer.", 401, "not_authenticated");

  let orderId: string;
  try {
    const body = await req.json();
    orderId = String(body?.order_id ?? "");
  } catch {
    return errorResponse("Corps JSON invalide", 400);
  }
  if (!/^[0-9a-f-]{36}$/i.test(orderId)) return errorResponse("order_id invalide", 400);

  try {
    const { data: userData, error: userError } = await userClient(authorization).auth.getUser();
    if (userError || !userData?.user) return errorResponse("Session expirée, reconnecte-toi.", 401, "not_authenticated");
    const userId = userData.user.id;

    const admin = adminClient();
    const { data: order, error: orderError } = await admin
      .from("orders")
      .select("id, buyer_id, listing_title, item_price, delivery_fee, payment, status")
      .eq("id", orderId)
      .maybeSingle<OrderRow>();
    if (orderError) throw orderError;
    if (!order || order.buyer_id !== userId) return errorResponse("Commande introuvable.", 404, "not_found");

    const amount = order.item_price + order.delivery_fee;
    const { data: profile } = await admin
      .from("profiles")
      .select("phone")
      .eq("id", userId)
      .maybeSingle<{ phone: string | null }>();
    const extra = {
      amount,
      method: order.payment,
      masked_phone: maskPhone(profile?.phone ?? userData.user.phone ?? null),
      ussd_code: order.payment === "orange_money" ? (optionalEnv("OM_USSD_CODE") || null) : null,
    };

    // Idempotence : commande déjà payée / annulée → on renvoie simplement l'état.
    if (order.status !== "PAYMENT_PENDING") {
      return json({ payment_id: null, provider: null, status: order.status, checkout_url: null, ...extra });
    }

    const provider = providerForMethod(order.payment);

    // Idempotence : une session déjà ouverte pour ce prestataire est réutilisée.
    const { data: existing } = await admin
      .from("payments")
      .select("id, checkout_url")
      .eq("order_id", order.id)
      .eq("provider", provider.name)
      .eq("state", "pending")
      .maybeSingle<{ id: string; checkout_url: string | null }>();
    if (existing && !provider.autoConfirm) {
      return json({
        payment_id: existing.id, provider: provider.name, status: order.status,
        checkout_url: existing.checkout_url, ...extra,
      });
    }

    const functionsBase = `${requireEnv("SUPABASE_URL")}/functions/v1`;
    const appScheme = optionalEnv("APP_URL_SCHEME", "refripe");
    const session = await provider.createSession({
      orderId: order.id,
      amount,
      currency: "XOF",
      method: order.payment,
      description: `ReFripe — ${order.listing_title}`.slice(0, 120),
      successUrl: `${appScheme}://orders/${order.id}?payment=success`,
      errorUrl: `${appScheme}://orders/${order.id}?payment=error`,
      webhookUrl: `${functionsBase}/payment-webhook?provider=${provider.name}`,
    });

    let paymentId: string | null = existing?.id ?? null;
    if (!paymentId) {
      const { data: inserted, error: insertError } = await admin
        .from("payments")
        .insert({
          order_id: order.id,
          provider: provider.name,
          amount,
          currency: "XOF",
          session_id: session.sessionId,
          checkout_url: session.checkoutUrl,
          notif_token: session.notifToken ?? null,
          raw: session.raw,
        })
        .select("id")
        .single<{ id: string }>();
      if (insertError) throw insertError;
      paymentId = inserted.id;
    }

    let status = order.status;
    if (provider.autoConfirm) {
      const { data, error } = await admin.rpc("confirm_payment", {
        p_order_id: order.id,
        p_amount: amount,
        p_provider: provider.name,
        p_provider_ref: session.sessionId,
      });
      if (error) throw error;
      status = String(data);
    }

    return json({ payment_id: paymentId, provider: provider.name, status, checkout_url: session.checkoutUrl, ...extra });
  } catch (e) {
    console.error("payment-init", e);
    return errorResponse("Le paiement n’a pas pu être initialisé. Réessaie dans un instant.", 502, "payment_init_failed");
  }
});
