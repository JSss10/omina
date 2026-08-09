-- Omina – Storage-Bucket für Profilfotos
--
-- Der iOS-Client (AvatarStore.swift) speichert das Profilfoto unter
-- <user_id>/avatar.jpg. Der Bucket ist privat; die Policies erlauben jedem
-- User nur Zugriff auf seinen eigenen Ordner (erste Pfad-Komponente = uid).
--
-- Einspielen im Supabase SQL Editor (einmalig).

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', false)
on conflict (id) do nothing;

drop policy if exists "Avatars: eigener Ordner lesen" on storage.objects;
create policy "Avatars: eigener Ordner lesen"
on storage.objects for select to authenticated
using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Avatars: eigener Ordner schreiben" on storage.objects;
create policy "Avatars: eigener Ordner schreiben"
on storage.objects for insert to authenticated
with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Avatars: eigener Ordner aktualisieren" on storage.objects;
create policy "Avatars: eigener Ordner aktualisieren"
on storage.objects for update to authenticated
using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Avatars: eigener Ordner löschen" on storage.objects;
create policy "Avatars: eigener Ordner löschen"
on storage.objects for delete to authenticated
using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
);