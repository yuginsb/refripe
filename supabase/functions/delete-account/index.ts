// delete-account — suppression de compte (App Store 5.1.1(v)).
//
// POST {}   (JWT utilisateur requis : verify_jwt = true)
// → 200 { ok: true }
//
// 1. RPC public.delete_account() avec le JWT de l'utilisatrice : refuse si de l'argent est en
//    séquestre, annule les commandes non payées, retire/supprime les annonces, anonymise le
//    profil (les commandes passées sont conservées), efface préférences, envies, blocages…
// 2. Supprime ses fichiers Storage (listing-photos/<uid>/…, chat-photos/<uid>/…).
// 3. Supprime l'utilisateur auth (service_role) : le numéro peut ensuite recréer un compte.

import { errorResponse, json } from "../_shared/http.ts";
import { adminClient, userClient } from "../_shared/supabase.ts";

const BUCKETS = ["listing-photos", "chat-photos"];

async function removeFolder(admin: ReturnType<typeof adminClient>, bucket: string, prefix: string): Promise<void> {
  // Storage n'a pas de suppression récursive : on parcourt les sous-dossiers (2 niveaux suffisent :
  // <uid>/<listing|conversation>/<fichier>).
  const { data: entries } = await admin.storage.from(bucket).list(prefix, { limit: 1000 });
  const files: string[] = [];
  for (const entry of entries ?? []) {
    const path = `${prefix}/${entry.name}`;
    if (entry.id) {
      files.push(path);
    } else {
      const { data: children } = await admin.storage.from(bucket).list(path, { limit: 1000 });
      for (const child of children ?? []) if (child.id) files.push(`${path}/${child.name}`);
    }
  }
  for (let i = 0; i < files.length; i += 100) {
    await admin.storage.from(bucket).remove(files.slice(i, i + 100));
  }
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") return errorResponse("Méthode non autorisée", 405);
  const authorization = req.headers.get("Authorization");
  if (!authorization) return errorResponse("Connecte-toi pour continuer.", 401, "not_authenticated");

  const user = userClient(authorization);
  const { data: userData, error: userError } = await user.auth.getUser();
  if (userError || !userData?.user) return errorResponse("Session expirée, reconnecte-toi.", 401, "not_authenticated");
  const userId = userData.user.id;

  // Règles métier en SQL (message FR lisible en cas de refus).
  const { error: rpcError } = await user.rpc("delete_account");
  if (rpcError) {
    return errorResponse(rpcError.message || "Suppression impossible pour le moment.", 409, rpcError.hint ?? "delete_refused");
  }

  try {
    const admin = adminClient();
    for (const bucket of BUCKETS) await removeFolder(admin, bucket, userId);
    const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
    if (deleteError) throw deleteError;
    return json({ ok: true });
  } catch (e) {
    // Le profil est déjà anonymisé : on journalise pour reprise manuelle.
    console.error("delete-account", userId, e);
    return errorResponse("Ton compte a été anonymisé ; la suppression finale sera terminée sous 24 h.", 502, "delete_partial");
  }
});
