-- Keep unknown legacy owners unchanged. Never infer ownership from display names.
-- Apply together with the language ownership controls in index.html.
begin;

create or replace function public.is_balcony_language_admin()
returns boolean language sql stable security definer
set search_path = public, pg_temp
as $$
  select auth.uid() is not null and exists (
    select 1 from public.pocony_users u
    where u.uid::text = auth.uid()::text
      and to_jsonb(u.roles) ? 'balcony_admin'
  );
$$;

create or replace function public.can_delete_balcony_language(entry_id text)
returns boolean language sql stable security definer
set search_path = public, pg_temp
as $$
  select auth.uid() is not null and exists (
    select 1 from public.balcony_language entry
    where entry.id::text = entry_id
      and (public.is_balcony_language_admin() or entry.uploader_uid::text = auth.uid()::text)
      and (
        entry.kind = 'file'
        or (
          entry.kind = 'folder'
          and lower(trim(entry.name)) not in ('english', 'original file')
          and (
            public.is_balcony_language_admin()
            or not exists (
              select 1 from public.balcony_language child
              where child.folder_id = entry.id
                and child.uploader_uid::text is distinct from auth.uid()::text
            )
          )
        )
      )
  );
$$;

alter table public.balcony_language enable row level security;

-- The restrictive policy also constrains any pre-existing permissive policy.
create policy language_delete_ownership_guard
on public.balcony_language as restrictive for delete to authenticated
using (public.can_delete_balcony_language(id::text));

create policy language_delete_own_or_admin
on public.balcony_language for delete to authenticated
using (public.can_delete_balcony_language(id::text));

create or replace function public.guard_balcony_language_ownership()
returns trigger language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  -- Trusted maintenance jobs retain their existing access.
  if auth.role() = 'service_role' then
    if tg_op = 'DELETE' then return old; else return new; end if;
  end if;

  if tg_op = 'DELETE' then
    if not public.can_delete_balcony_language(old.id::text) then
      raise exception 'You cannot delete this entry or a folder containing files you do not own.'
        using errcode = '42501';
    end if;
    return old;
  end if;

  if tg_op = 'UPDATE' then
    if new.uploader_uid is distinct from old.uploader_uid
       or new.kind is distinct from old.kind
       or new.folder_id is distinct from old.folder_id
       or new.storage_path is distinct from old.storage_path then
      raise exception 'Language entry ownership and location cannot be changed.' using errcode = '42501';
    end if;
    if old.kind = 'folder' and lower(trim(old.name)) in ('english', 'original file')
       and new.name is distinct from old.name then
      raise exception 'The Original File folder cannot be renamed.' using errcode = '42501';
    end if;
    return new;
  end if;

  if auth.uid() is null then
    raise exception 'Please sign in first.' using errcode = '42501';
  end if;
  -- All new records belong to the caller, regardless of the supplied value.
  new.uploader_uid := auth.uid();
  if new.kind = 'file' then
    -- Serialize child insertion with deletion of its parent. A concurrent upload
    -- cannot appear after the folder's ownership check and then be cascaded away.
    perform 1 from public.balcony_language parent
      where parent.id = new.folder_id and parent.kind = 'folder'
      for key share;
    if not found then
      raise exception 'Folder no longer exists.' using errcode = '23503';
    end if;
    if not public.is_balcony_language_admin() then
      perform 1 from storage.objects object
        where object.bucket_id = 'balcony_language' and object.name = new.storage_path
          and object.owner_id = auth.uid()::text;
      if not found then
        raise exception 'You can only register files you uploaded.' using errcode = '42501';
      end if;
    end if;
  end if;
  return new;
end;
$$;

create trigger language_entry_ownership_guard
before insert or update or delete on public.balcony_language
for each row execute function public.guard_balcony_language_ownership();

create or replace function public.can_delete_balcony_language_object(object_name text, object_owner text)
returns boolean language plpgsql stable security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then return false; end if;
  if public.is_balcony_language_admin() then return true; end if;
  if exists (
    select 1 from public.balcony_language entry
    where entry.kind = 'file' and entry.storage_path = object_name
  ) then
    -- Null owners are deliberately rejected, including for legacy files.
    return not exists (
      select 1 from public.balcony_language entry
      where entry.kind = 'file' and entry.storage_path = object_name
        and entry.uploader_uid::text is distinct from auth.uid()::text
    );
  end if;
  -- Permit cleanup of the caller's upload if creating its database record failed.
  return coalesce(object_owner = auth.uid()::text, false);
end;
$$;

create policy language_storage_delete_ownership_guard
on storage.objects as restrictive for delete to authenticated
using (
  bucket_id <> 'balcony_language'
  or public.can_delete_balcony_language_object(name, owner_id)
);

create policy language_storage_delete_own_or_admin
on storage.objects for delete to authenticated
using (
  bucket_id = 'balcony_language'
  and public.can_delete_balcony_language_object(name, owner_id)
);

revoke all on function public.is_balcony_language_admin() from public, anon;
revoke all on function public.can_delete_balcony_language(text) from public, anon;
revoke all on function public.can_delete_balcony_language_object(text, text) from public, anon;
revoke all on function public.guard_balcony_language_ownership() from public, anon, authenticated;
grant execute on function public.is_balcony_language_admin() to authenticated;
grant execute on function public.can_delete_balcony_language(text) to authenticated;
grant execute on function public.can_delete_balcony_language_object(text, text) to authenticated;

commit;
