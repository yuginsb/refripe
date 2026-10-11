-- ReFripe — 5/6 : Storage
-- Bucket public `listing-photos` : lecture publique par URL, écriture limitée
-- au dossier `<auth.uid()>/` de chaque utilisatrice.
-- Convention de chemin : <uid en minuscules>/<listing id en minuscules>/<n>.jpg

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'listing-photos', 'listing-photos', true, 5242880,
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic']
)
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

create policy "listing-photos: lecture publique"
  on storage.objects for select
  to anon, authenticated
  using (bucket_id = 'listing-photos');

create policy "listing-photos: upload dans son dossier"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'listing-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "listing-photos: mise à jour dans son dossier"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'listing-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'listing-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "listing-photos: suppression dans son dossier"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'listing-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
