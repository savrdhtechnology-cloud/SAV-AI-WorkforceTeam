-- SAVRDH Intelligence Workforce - Phase 4 Inbox & Channels
-- PREPARED ONLY. DO NOT APPLY TO PRODUCTION AUTOMATICALLY.
-- Extends the existing sav_ai_crm conversations/messages foundation in-place.

begin;

-- ---------------------------------------------------------------------------
-- Conversation and message model extensions
-- ---------------------------------------------------------------------------
alter table sav_ai_crm.conversations
  add column if not exists subject text,
  add column if not exists priority text not null default 'medium',
  add column if not exists assigned_agent_id uuid,
  add column if not exists unread_count integer not null default 0,
  add column if not exists last_message_preview text,
  add column if not exists archived_at timestamptz,
  add column if not exists updated_at timestamptz not null default now();

alter table sav_ai_crm.conversations drop constraint if exists conversations_status_check;
alter table sav_ai_crm.conversations
  add constraint conversations_status_check check (status in ('open','waiting','closed','archived'));

alter table sav_ai_crm.conversations drop constraint if exists conversations_priority_check;
alter table sav_ai_crm.conversations
  add constraint conversations_priority_check check (priority in ('low','medium','high','urgent'));

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='conversations_assigned_agent_id_fkey'
      and conrelid='sav_ai_crm.conversations'::regclass
  ) then
    alter table sav_ai_crm.conversations
      add constraint conversations_assigned_agent_id_fkey
      foreign key (assigned_agent_id) references sav_ai_crm.ai_agents(id) on delete set null;
  end if;
end $$;

alter table sav_ai_crm.messages
  add column if not exists channel text,
  add column if not exists sender text,
  add column if not exists recipient text,
  add column if not exists message_type text not null default 'text',
  add column if not exists is_read boolean not null default false,
  add column if not exists read_at timestamptz,
  add column if not exists sent_by_member_id uuid,
  add column if not exists sent_by_agent_id uuid,
  add column if not exists error_code text,
  add column if not exists error_message text,
  add column if not exists updated_at timestamptz not null default now();

update sav_ai_crm.messages m
set channel=c.channel
from sav_ai_crm.conversations c
where m.conversation_id=c.id and m.channel is null;

update sav_ai_crm.messages
set delivery_status=case lower(coalesce(delivery_status,'pending'))
  when 'pending' then 'QUEUED'
  when 'queued' then 'QUEUED'
  when 'sending' then 'SENDING'
  when 'sent' then 'SENT'
  when 'delivered' then 'DELIVERED'
  when 'read' then 'READ'
  when 'failed' then 'FAILED'
  else 'QUEUED' end;

alter table sav_ai_crm.messages alter column delivery_status set default 'QUEUED';
alter table sav_ai_crm.messages drop constraint if exists messages_delivery_status_check;
alter table sav_ai_crm.messages
  add constraint messages_delivery_status_check check (delivery_status in ('QUEUED','SENDING','SENT','DELIVERED','READ','FAILED'));
alter table sav_ai_crm.messages drop constraint if exists messages_message_type_check;
alter table sav_ai_crm.messages
  add constraint messages_message_type_check check (message_type in ('text','html','image','file','audio','video','system','note'));
alter table sav_ai_crm.messages drop constraint if exists messages_channel_check;
alter table sav_ai_crm.messages
  add constraint messages_channel_check check (channel in ('whatsapp','email','sms','voice','webchat'));

do $$
begin
  if not exists (select 1 from pg_constraint where conname='messages_sent_by_member_id_fkey' and conrelid='sav_ai_crm.messages'::regclass) then
    alter table sav_ai_crm.messages add constraint messages_sent_by_member_id_fkey foreign key(sent_by_member_id) references sav_ai_crm.members(id) on delete set null;
  end if;
  if not exists (select 1 from pg_constraint where conname='messages_sent_by_agent_id_fkey' and conrelid='sav_ai_crm.messages'::regclass) then
    alter table sav_ai_crm.messages add constraint messages_sent_by_agent_id_fkey foreign key(sent_by_agent_id) references sav_ai_crm.ai_agents(id) on delete set null;
  end if;
end $$;

create table if not exists sav_ai_crm.conversation_participants (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
  conversation_id uuid not null references sav_ai_crm.conversations(id) on delete cascade,
  participant_type text not null check (participant_type in ('lead','contact','member','ai_agent','external')),
  participant_id uuid,
  external_address text,
  display_name text,
  is_primary boolean not null default false,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists sav_ai_crm.message_attachments (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
  message_id uuid not null references sav_ai_crm.messages(id) on delete cascade,
  file_name text not null,
  mime_type text not null,
  size_bytes bigint,
  external_url text,
  provider_attachment_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists sav_ai_crm.conversation_assignments (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
  conversation_id uuid not null references sav_ai_crm.conversations(id) on delete cascade,
  assignment_type text not null check (assignment_type in ('human','ai')),
  member_id uuid references sav_ai_crm.members(id) on delete set null,
  agent_id uuid references sav_ai_crm.ai_agents(id) on delete set null,
  assigned_by uuid references sav_ai_crm.members(id) on delete set null,
  reason text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  ended_at timestamptz
);

create table if not exists sav_ai_crm.conversation_tags (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
  conversation_id uuid not null references sav_ai_crm.conversations(id) on delete cascade,
  tag text not null,
  created_by uuid references sav_ai_crm.members(id) on delete set null,
  created_at timestamptz not null default now(),
  unique(conversation_id,tag)
);

create table if not exists sav_ai_crm.channel_accounts (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
  channel text not null check (channel in ('whatsapp','email','sms','voice','webchat')),
  provider text not null,
  display_name text not null,
  external_account_id text,
  sender_identity text,
  status text not null default 'disconnected' check (status in ('connected','disconnected','error','disabled')),
  public_config jsonb not null default '{}'::jsonb,
  secret_ref text,
  webhook_external_key text,
  created_by uuid references sav_ai_crm.members(id) on delete set null,
  updated_by uuid references sav_ai_crm.members(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(workspace_id,channel,provider,external_account_id)
);

create table if not exists sav_ai_crm.message_delivery_events (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
  message_id uuid not null references sav_ai_crm.messages(id) on delete cascade,
  provider_event_id text,
  provider_message_id text,
  status text not null check (status in ('QUEUED','SENDING','SENT','DELIVERED','READ','FAILED')),
  error_code text,
  error_message text,
  raw_metadata jsonb not null default '{}'::jsonb,
  event_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table if not exists sav_ai_crm.conversation_activity (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
  conversation_id uuid not null references sav_ai_crm.conversations(id) on delete cascade,
  message_id uuid references sav_ai_crm.messages(id) on delete set null,
  actor_member_id uuid references sav_ai_crm.members(id) on delete set null,
  actor_agent_id uuid references sav_ai_crm.ai_agents(id) on delete set null,
  activity_type text not null,
  title text not null,
  description text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists sav_ai_crm.channel_webhook_events (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
  channel_account_id uuid references sav_ai_crm.channel_accounts(id) on delete set null,
  channel text not null check (channel in ('whatsapp','email','sms','voice','webchat')),
  provider text not null,
  provider_event_id text not null,
  provider_message_id text,
  signature_verified boolean not null default false,
  processing_status text not null default 'received' check (processing_status in ('received','processed','duplicate','rejected','failed')),
  error text,
  metadata jsonb not null default '{}'::jsonb,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  unique(workspace_id,provider,provider_event_id)
);

create index if not exists conversations_workspace_inbox_idx on sav_ai_crm.conversations(workspace_id,status,last_message_at desc) where archived_at is null;
create index if not exists conversations_workspace_assignee_idx on sav_ai_crm.conversations(workspace_id,assigned_to,assigned_agent_id) where archived_at is null;
create index if not exists conversations_workspace_channel_idx on sav_ai_crm.conversations(workspace_id,channel,last_message_at desc) where archived_at is null;
create index if not exists messages_conversation_created_idx on sav_ai_crm.messages(conversation_id,created_at);
create index if not exists messages_provider_id_idx on sav_ai_crm.messages(workspace_id,provider_message_id) where provider_message_id is not null;
create index if not exists messages_delivery_idx on sav_ai_crm.messages(workspace_id,delivery_status,updated_at desc);
create index if not exists conversation_participants_idx on sav_ai_crm.conversation_participants(workspace_id,conversation_id);
create index if not exists conversation_assignments_idx on sav_ai_crm.conversation_assignments(conversation_id,active,created_at desc);
create index if not exists conversation_tags_idx on sav_ai_crm.conversation_tags(workspace_id,tag);
create index if not exists channel_accounts_lookup_idx on sav_ai_crm.channel_accounts(workspace_id,channel,status);
create index if not exists delivery_events_message_idx on sav_ai_crm.message_delivery_events(message_id,event_at);
create unique index if not exists delivery_events_provider_event_uq on sav_ai_crm.message_delivery_events(workspace_id,provider_event_id) where provider_event_id is not null;
create index if not exists conversation_activity_idx on sav_ai_crm.conversation_activity(conversation_id,created_at desc);

-- ---------------------------------------------------------------------------
-- RLS and helpers
-- ---------------------------------------------------------------------------
alter table sav_ai_crm.conversation_participants enable row level security;
alter table sav_ai_crm.message_attachments enable row level security;
alter table sav_ai_crm.conversation_assignments enable row level security;
alter table sav_ai_crm.conversation_tags enable row level security;
alter table sav_ai_crm.channel_accounts enable row level security;
alter table sav_ai_crm.message_delivery_events enable row level security;
alter table sav_ai_crm.conversation_activity enable row level security;
alter table sav_ai_crm.channel_webhook_events enable row level security;

create or replace function sav_ai_crm.inbox_current_member()
returns sav_ai_crm.members
language sql stable security definer
set search_path=public,sav_ai_crm
as $$
  select m from sav_ai_crm.members m
  where m.user_id=auth.uid() and m.is_active=true
  order by m.created_at limit 1;
$$;

create or replace function sav_ai_crm.inbox_can_manage(p_role text)
returns boolean language sql immutable
as $$ select p_role in ('owner','admin','manager'); $$;

create or replace function sav_ai_crm.inbox_can_write(p_role text)
returns boolean language sql immutable
as $$ select p_role in ('owner','admin','manager','sales','support','operations'); $$;

revoke all on function sav_ai_crm.inbox_current_member() from public,anon;
grant execute on function sav_ai_crm.inbox_current_member() to authenticated;
revoke all on function sav_ai_crm.inbox_can_manage(text) from public,anon,authenticated;
revoke all on function sav_ai_crm.inbox_can_write(text) from public,anon,authenticated;

do $$
declare t text;
begin
 foreach t in array array[
   'conversation_participants','message_attachments','conversation_assignments','conversation_tags',
   'channel_accounts','message_delivery_events','conversation_activity','channel_webhook_events'
 ] loop
   execute format('drop policy if exists "inbox workspace read %1$s" on sav_ai_crm.%1$I',t);
   execute format('create policy "inbox workspace read %1$s" on sav_ai_crm.%1$I for select to authenticated using (sav_ai_crm.is_workspace_member(workspace_id))',t);
 end loop;
end $$;

-- Existing conversation/message tables remain workspace readable but direct writes are tightened.
drop policy if exists "workspace insert conversations" on sav_ai_crm.conversations;
drop policy if exists "workspace update conversations" on sav_ai_crm.conversations;
drop policy if exists "workspace delete conversations" on sav_ai_crm.conversations;
drop policy if exists "workspace insert messages" on sav_ai_crm.messages;
drop policy if exists "workspace update messages" on sav_ai_crm.messages;
drop policy if exists "workspace delete messages" on sav_ai_crm.messages;

create policy "inbox rpc conversation insert" on sav_ai_crm.conversations for insert to authenticated
with check (false);
create policy "inbox rpc conversation update" on sav_ai_crm.conversations for update to authenticated
using (false) with check(false);
create policy "inbox rpc message insert" on sav_ai_crm.messages for insert to authenticated
with check(false);
create policy "inbox rpc message update" on sav_ai_crm.messages for update to authenticated
using(false) with check(false);

-- ---------------------------------------------------------------------------
-- Context and read RPCs
-- ---------------------------------------------------------------------------
create or replace function public.sav_ai_crm_inbox_context()
returns jsonb language plpgsql stable security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members;
begin
 me:=sav_ai_crm.inbox_current_member();
 if me.id is null then raise exception 'CRM membership required'; end if;
 return jsonb_build_object(
  'member',jsonb_build_object('id',me.id,'role',me.role,'full_name',me.full_name,'email',me.email),
  'members',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'full_name',m.full_name,'email',m.email,'role',m.role) order by coalesce(m.full_name,m.email))
    from sav_ai_crm.members m where m.workspace_id=me.workspace_id and m.is_active),'[]'::jsonb),
  'agents',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'display_name',a.display_name,'name',a.name,'status',a.status,'channels',a.channels,'capabilities',a.capabilities) order by a.display_name)
    from sav_ai_crm.ai_agents a where a.workspace_id=me.workspace_id),'[]'::jsonb),
  'leads',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'title',l.title,'company',l.company) order by l.updated_at desc) from sav_ai_crm.leads l where l.workspace_id=me.workspace_id limit 500),'[]'::jsonb),
  'contacts',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'first_name',c.first_name,'last_name',c.last_name,'company',c.company,'email',c.email,'phone',c.phone) order by c.updated_at desc) from sav_ai_crm.contacts c where c.workspace_id=me.workspace_id limit 500),'[]'::jsonb),
  'channels',jsonb_build_array('whatsapp','email','sms','voice','webchat'),
  'permissions',jsonb_build_object(
    'reply',sav_ai_crm.inbox_can_write(me.role),
    'assign',sav_ai_crm.inbox_can_manage(me.role),
    'assign_ai',sav_ai_crm.inbox_can_manage(me.role),
    'archive',me.role in ('owner','admin'),
    'manage_channels',me.role in ('owner','admin'),
    'read_only',me.role='viewer'
  )
 );
end $$;

create or replace function public.sav_ai_crm_inbox_conversations(
 p_search text default null,p_channel text default null,p_status text default null,p_unread_only boolean default false,p_assignment text default null
) returns jsonb language plpgsql stable security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members;
begin
 me:=sav_ai_crm.inbox_current_member();
 if me.id is null then raise exception 'CRM membership required'; end if;
 if p_channel is not null and p_channel not in ('whatsapp','email','sms','voice','webchat') then raise exception 'Invalid channel'; end if;
 if p_status is not null and p_status not in ('open','waiting','closed','archived') then raise exception 'Invalid conversation status'; end if;
 if p_assignment is not null and p_assignment not in ('assigned','unassigned','human','ai','mine') then raise exception 'Invalid assignment filter'; end if;

 return coalesce((select jsonb_agg(to_jsonb(x) order by x.last_message_at desc nulls last,x.created_at desc) from (
  select c.id,c.channel,c.status,c.priority,c.subject,c.lead_id,c.contact_id,c.assigned_to,c.assigned_agent_id,
    c.unread_count,c.last_message_at,c.last_message_preview,c.archived_at,c.created_at,c.updated_at,
    coalesce(l.title,concat_ws(' ',ct.first_name,ct.last_name),ct.company,c.subject,'Unknown contact') related_name,
    coalesce(h.full_name,h.email) assigned_human_name,
    coalesce(a.display_name,a.name) assigned_agent_name,
    coalesce((select array_agg(t.tag order by t.tag) from sav_ai_crm.conversation_tags t where t.conversation_id=c.id),'{}'::text[]) tags
  from sav_ai_crm.conversations c
  left join sav_ai_crm.leads l on l.id=c.lead_id and l.workspace_id=c.workspace_id
  left join sav_ai_crm.contacts ct on ct.id=c.contact_id and ct.workspace_id=c.workspace_id
  left join sav_ai_crm.members h on h.id=c.assigned_to and h.workspace_id=c.workspace_id
  left join sav_ai_crm.ai_agents a on a.id=c.assigned_agent_id and a.workspace_id=c.workspace_id
  where c.workspace_id=me.workspace_id
    and (p_status='archived' or c.archived_at is null)
    and (p_channel is null or c.channel=p_channel)
    and (p_status is null or c.status=p_status)
    and (not p_unread_only or c.unread_count>0)
    and (p_assignment is null
      or (p_assignment='assigned' and (c.assigned_to is not null or c.assigned_agent_id is not null))
      or (p_assignment='unassigned' and c.assigned_to is null and c.assigned_agent_id is null)
      or (p_assignment='human' and c.assigned_to is not null)
      or (p_assignment='ai' and c.assigned_agent_id is not null)
      or (p_assignment='mine' and c.assigned_to=me.id))
    and (p_search is null
      or coalesce(c.subject,'') ilike '%'||p_search||'%'
      or coalesce(l.title,'') ilike '%'||p_search||'%'
      or concat_ws(' ',ct.first_name,ct.last_name) ilike '%'||p_search||'%'
      or coalesce(ct.email,'') ilike '%'||p_search||'%'
      or coalesce(ct.phone,'') ilike '%'||p_search||'%'
      or coalesce(c.last_message_preview,'') ilike '%'||p_search||'%')
 ) x),'[]'::jsonb);
end $$;

create or replace function public.sav_ai_crm_inbox_conversation_detail(p_conversation_id uuid)
returns jsonb language plpgsql stable security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; c sav_ai_crm.conversations;
begin
 me:=sav_ai_crm.inbox_current_member();
 if me.id is null then raise exception 'CRM membership required'; end if;
 select * into c from sav_ai_crm.conversations where id=p_conversation_id and workspace_id=me.workspace_id;
 if c.id is null then raise exception 'Conversation not found'; end if;

 return jsonb_build_object(
  'conversation',(select to_jsonb(x) from (
    select c.*,coalesce(l.title,concat_ws(' ',ct.first_name,ct.last_name),ct.company,c.subject,'Unknown contact') related_name,
      coalesce(h.full_name,h.email) assigned_human_name,coalesce(a.display_name,a.name) assigned_agent_name,
      coalesce((select array_agg(t.tag order by t.tag) from sav_ai_crm.conversation_tags t where t.conversation_id=c.id),'{}'::text[]) tags
    from sav_ai_crm.conversations c
    left join sav_ai_crm.leads l on l.id=c.lead_id left join sav_ai_crm.contacts ct on ct.id=c.contact_id
    left join sav_ai_crm.members h on h.id=c.assigned_to left join sav_ai_crm.ai_agents a on a.id=c.assigned_agent_id
    where c.id=p_conversation_id and c.workspace_id=me.workspace_id
  ) x),
  'messages',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from (
    select m.*,coalesce((select jsonb_agg(to_jsonb(ma) order by ma.created_at) from sav_ai_crm.message_attachments ma where ma.message_id=m.id),'[]'::jsonb) attachments
    from sav_ai_crm.messages m where m.conversation_id=p_conversation_id and m.workspace_id=me.workspace_id
  ) x),'[]'::jsonb),
  'participants',coalesce((select jsonb_agg(to_jsonb(p) order by p.created_at) from sav_ai_crm.conversation_participants p where p.conversation_id=p_conversation_id and p.workspace_id=me.workspace_id),'[]'::jsonb),
  'assignments',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'assignment_type',a.assignment_type,'member_id',a.member_id,'agent_id',a.agent_id,'reason',a.reason,'active',a.active,'created_at',a.created_at,'ended_at',a.ended_at,'member_name',coalesce(m.full_name,m.email),'agent_name',coalesce(ag.display_name,ag.name)) order by a.created_at desc)
    from sav_ai_crm.conversation_assignments a left join sav_ai_crm.members m on m.id=a.member_id left join sav_ai_crm.ai_agents ag on ag.id=a.agent_id
    where a.conversation_id=p_conversation_id and a.workspace_id=me.workspace_id),'[]'::jsonb),
  'activities',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'activity_type',a.activity_type,'title',a.title,'description',a.description,'metadata',a.metadata,'created_at',a.created_at,'actor_name',coalesce(m.full_name,m.email,ag.display_name,ag.name)) order by a.created_at desc)
    from sav_ai_crm.conversation_activity a left join sav_ai_crm.members m on m.id=a.actor_member_id left join sav_ai_crm.ai_agents ag on ag.id=a.actor_agent_id
    where a.conversation_id=p_conversation_id and a.workspace_id=me.workspace_id),'[]'::jsonb)
 );
end $$;

-- ---------------------------------------------------------------------------
-- Conversation mutations
-- ---------------------------------------------------------------------------
create or replace function public.sav_ai_crm_create_conversation(
 p_channel text,p_subject text default null,p_lead_id uuid default null,p_contact_id uuid default null,p_priority text default 'medium',p_external_thread_id text default null
) returns uuid language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; cid uuid;
begin
 me:=sav_ai_crm.inbox_current_member();
 if me.id is null or not sav_ai_crm.inbox_can_write(me.role) then raise exception 'Conversation creation not permitted'; end if;
 if p_channel not in ('whatsapp','email','sms','voice','webchat') then raise exception 'Invalid channel'; end if;
 if p_priority not in ('low','medium','high','urgent') then raise exception 'Invalid priority'; end if;
 if p_lead_id is not null and p_contact_id is not null then raise exception 'Conversation may link to lead or contact, not both'; end if;
 if p_lead_id is not null and not exists(select 1 from sav_ai_crm.leads where id=p_lead_id and workspace_id=me.workspace_id) then raise exception 'Lead outside workspace'; end if;
 if p_contact_id is not null and not exists(select 1 from sav_ai_crm.contacts where id=p_contact_id and workspace_id=me.workspace_id) then raise exception 'Contact outside workspace'; end if;

 insert into sav_ai_crm.conversations(workspace_id,lead_id,contact_id,channel,external_thread_id,status,priority,subject,created_at,updated_at)
 values(me.workspace_id,p_lead_id,p_contact_id,p_channel,p_external_thread_id,'open',p_priority,nullif(trim(coalesce(p_subject,'')),''),now(),now())
 returning id into cid;
 insert into sav_ai_crm.conversation_activity(workspace_id,conversation_id,actor_member_id,activity_type,title,metadata)
 values(me.workspace_id,cid,me.id,'conversation_created','Conversation created',jsonb_build_object('channel',p_channel));
 insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id,metadata)
 values(me.workspace_id,auth.uid(),'inbox.conversation.create','conversation',cid,jsonb_build_object('channel',p_channel));
 return cid;
end $$;

create or replace function public.sav_ai_crm_update_conversation(
 p_conversation_id uuid,p_priority text default null,p_lead_id uuid default null,p_contact_id uuid default null,p_subject text default null,p_tags text[] default null,p_mark_unread boolean default null,p_archive boolean default null
) returns void language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; c sav_ai_crm.conversations; tag_value text;
begin
 me:=sav_ai_crm.inbox_current_member();
 if me.id is null or not sav_ai_crm.inbox_can_write(me.role) then raise exception 'Conversation update not permitted'; end if;
 select * into c from sav_ai_crm.conversations where id=p_conversation_id and workspace_id=me.workspace_id;
 if c.id is null then raise exception 'Conversation not found'; end if;
 if p_priority is not null and p_priority not in ('low','medium','high','urgent') then raise exception 'Invalid priority'; end if;
 if p_lead_id is not null and p_contact_id is not null then raise exception 'Conversation may link to lead or contact, not both'; end if;
 if p_lead_id is not null and not exists(select 1 from sav_ai_crm.leads where id=p_lead_id and workspace_id=me.workspace_id) then raise exception 'Lead outside workspace'; end if;
 if p_contact_id is not null and not exists(select 1 from sav_ai_crm.contacts where id=p_contact_id and workspace_id=me.workspace_id) then raise exception 'Contact outside workspace'; end if;
 if p_archive=true and me.role not in ('owner','admin') then raise exception 'Archive requires owner or admin'; end if;

 update sav_ai_crm.conversations set
  priority=coalesce(p_priority,priority),lead_id=case when p_lead_id is not null then p_lead_id when p_contact_id is not null then null else lead_id end,
  contact_id=case when p_contact_id is not null then p_contact_id when p_lead_id is not null then null else contact_id end,
  subject=case when p_subject is not null then nullif(trim(p_subject),'') else subject end,
  unread_count=case when p_mark_unread=true then greatest(unread_count,1) when p_mark_unread=false then 0 else unread_count end,
  status=case when p_archive=true then 'archived' else status end,
  archived_at=case when p_archive=true then now() when p_archive=false then null else archived_at end,
  updated_at=now()
 where id=c.id;

 if p_tags is not null then
  delete from sav_ai_crm.conversation_tags where conversation_id=c.id and workspace_id=me.workspace_id;
  foreach tag_value in array p_tags loop
    if length(trim(tag_value)) between 1 and 40 then
      insert into sav_ai_crm.conversation_tags(workspace_id,conversation_id,tag,created_by)
      values(me.workspace_id,c.id,lower(trim(tag_value)),me.id) on conflict(conversation_id,tag) do nothing;
    end if;
  end loop;
 end if;
 insert into sav_ai_crm.conversation_activity(workspace_id,conversation_id,actor_member_id,activity_type,title,metadata)
 values(me.workspace_id,c.id,me.id,case when p_archive=true then 'conversation_archived' else 'conversation_updated' end,
   case when p_archive=true then 'Conversation archived' else 'Conversation updated' end,
   jsonb_build_object('priority',p_priority,'lead_id',p_lead_id,'contact_id',p_contact_id,'mark_unread',p_mark_unread));
 insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id,metadata)
 values(me.workspace_id,auth.uid(),'inbox.conversation.update','conversation',c.id,jsonb_build_object('archive',p_archive,'priority',p_priority));
end $$;

create or replace function public.sav_ai_crm_assign_conversation(p_conversation_id uuid,p_assignment_type text,p_member_id uuid default null,p_agent_id uuid default null,p_reason text default null)
returns void language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; c sav_ai_crm.conversations;
begin
 me:=sav_ai_crm.inbox_current_member();
 if me.id is null or not sav_ai_crm.inbox_can_manage(me.role) then raise exception 'Conversation assignment not permitted'; end if;
 select * into c from sav_ai_crm.conversations where id=p_conversation_id and workspace_id=me.workspace_id and archived_at is null;
 if c.id is null then raise exception 'Conversation not found'; end if;
 if p_assignment_type not in ('human','ai') then raise exception 'Invalid assignment type'; end if;
 if p_assignment_type='human' then
  if p_member_id is null or not exists(select 1 from sav_ai_crm.members where id=p_member_id and workspace_id=me.workspace_id and is_active) then raise exception 'Invalid human assignee'; end if;
  p_agent_id:=null;
 else
  if p_agent_id is null or not exists(select 1 from sav_ai_crm.ai_agents where id=p_agent_id and workspace_id=me.workspace_id and status='active' and c.channel=any(channels) and 'READ_CONVERSATION'=any(capabilities)) then raise exception 'Invalid AI assignee or missing channel capability'; end if;
  p_member_id:=null;
 end if;
 update sav_ai_crm.conversation_assignments set active=false,ended_at=now() where conversation_id=c.id and workspace_id=me.workspace_id and active;
 insert into sav_ai_crm.conversation_assignments(workspace_id,conversation_id,assignment_type,member_id,agent_id,assigned_by,reason)
 values(me.workspace_id,c.id,p_assignment_type,p_member_id,p_agent_id,me.id,nullif(trim(coalesce(p_reason,'')),''));
 update sav_ai_crm.conversations set assigned_to=p_member_id,assigned_agent_id=p_agent_id,updated_at=now() where id=c.id;
 insert into sav_ai_crm.conversation_activity(workspace_id,conversation_id,actor_member_id,actor_agent_id,activity_type,title,description)
 values(me.workspace_id,c.id,me.id,p_agent_id,case when p_assignment_type='ai' then 'ai_assignment' else 'assignment' end,
   case when p_assignment_type='ai' then 'Conversation assigned to AI agent' else 'Conversation assigned to human' end,p_reason);
 insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id,metadata)
 values(me.workspace_id,auth.uid(),'inbox.conversation.assign','conversation',c.id,jsonb_build_object('assignment_type',p_assignment_type,'member_id',p_member_id,'agent_id',p_agent_id));
end $$;

create or replace function public.sav_ai_crm_set_conversation_state(p_conversation_id uuid,p_action text)
returns void language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; c sav_ai_crm.conversations; new_status text;
begin
 me:=sav_ai_crm.inbox_current_member();
 if me.id is null or not sav_ai_crm.inbox_can_write(me.role) then raise exception 'Conversation state change not permitted'; end if;
 select * into c from sav_ai_crm.conversations where id=p_conversation_id and workspace_id=me.workspace_id;
 if c.id is null then raise exception 'Conversation not found'; end if;
 if p_action='close' then new_status:='closed'; elsif p_action='reopen' then new_status:='open'; else raise exception 'Invalid conversation action'; end if;
 update sav_ai_crm.conversations set status=new_status,archived_at=null,updated_at=now() where id=c.id;
 insert into sav_ai_crm.conversation_activity(workspace_id,conversation_id,actor_member_id,activity_type,title)
 values(me.workspace_id,c.id,me.id,'conversation_'||p_action,'Conversation '||p_action||'ed');
 insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id,metadata)
 values(me.workspace_id,auth.uid(),'inbox.conversation.'||p_action,'conversation',c.id,'{}'::jsonb);
end $$;

create or replace function public.sav_ai_crm_escalate_conversation(p_conversation_id uuid,p_reason text)
returns uuid language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; c sav_ai_crm.conversations; agent_id uuid; escalation_id uuid;
begin
 me:=sav_ai_crm.inbox_current_member();
 if me.id is null or not sav_ai_crm.inbox_can_write(me.role) then raise exception 'Conversation escalation not permitted'; end if;
 select * into c from sav_ai_crm.conversations where id=p_conversation_id and workspace_id=me.workspace_id and archived_at is null;
 if c.id is null then raise exception 'Conversation not found'; end if;
 agent_id:=c.assigned_agent_id;
 if agent_id is null then select id into agent_id from sav_ai_crm.ai_agents where workspace_id=me.workspace_id and slug='sav-support' limit 1; end if;
 if agent_id is null then raise exception 'No valid escalation agent exists'; end if;
 insert into sav_ai_crm.ai_agent_escalations(workspace_id,agent_id,lead_id,conversation_id,reason,details,status)
 values(me.workspace_id,agent_id,c.lead_id,c.id,'CUSTOMER_REQUESTED_HUMAN',nullif(trim(coalesce(p_reason,'')),'') ,'open')
 returning id into escalation_id;
 update sav_ai_crm.conversations set assigned_agent_id=null,status='waiting',priority=case when priority='urgent' then priority else 'high' end,updated_at=now() where id=c.id;
 insert into sav_ai_crm.conversation_activity(workspace_id,conversation_id,actor_member_id,activity_type,title,description,metadata)
 values(me.workspace_id,c.id,me.id,'escalation','Conversation escalated to human',p_reason,jsonb_build_object('escalation_id',escalation_id));
 insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id,metadata)
 values(me.workspace_id,auth.uid(),'inbox.conversation.escalate','conversation',c.id,jsonb_build_object('escalation_id',escalation_id));
 return escalation_id;
end $$;

-- ---------------------------------------------------------------------------
-- Message queue/result/read/draft boundaries
-- ---------------------------------------------------------------------------
create or replace function public.sav_ai_crm_queue_outbound_message(
 p_conversation_id uuid,p_body text,p_message_type text default 'text',p_recipient text default null,p_agent_id uuid default null,p_attachments jsonb default '[]'::jsonb
) returns jsonb language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; c sav_ai_crm.conversations; agent sav_ai_crm.ai_agents; mid uuid; sender_identity text; account sav_ai_crm.channel_accounts; needs_approval boolean:=false; action_result jsonb;
begin
 me:=sav_ai_crm.inbox_current_member();
 if me.id is null or not sav_ai_crm.inbox_can_write(me.role) then raise exception 'Message send not permitted'; end if;
 select * into c from sav_ai_crm.conversations where id=p_conversation_id and workspace_id=me.workspace_id and archived_at is null;
 if c.id is null then raise exception 'Conversation not found'; end if;
 if c.status='closed' then raise exception 'Conversation is closed'; end if;
 if p_message_type not in ('text','html','image','file','audio','video') then raise exception 'Invalid outbound message type'; end if;
 if coalesce(trim(p_body),'')='' and coalesce(jsonb_array_length(p_attachments),0)=0 then raise exception 'Message body or attachment required'; end if;

 if p_agent_id is not null then
  select * into agent from sav_ai_crm.ai_agents where id=p_agent_id and workspace_id=me.workspace_id and status='active';
  if agent.id is null then raise exception 'AI agent not found'; end if;
  if not c.channel=any(agent.channels) or not 'SEND_MESSAGE'=any(agent.capabilities) then raise exception 'AI agent lacks channel SEND_MESSAGE capability'; end if;
  action_result:=public.sav_ai_crm_request_agent_action(agent.id,'SEND_MESSAGE','conversation',c.id,jsonb_build_object('body',p_body,'channel',c.channel,'message_type',p_message_type));
  needs_approval:=coalesce((action_result->>'approval_required')::boolean,true);
  if needs_approval then
    return jsonb_build_object('approval_required',true,'agent_action_id',action_result->>'action_id','risk_level',action_result->>'risk_level');
  end if;
 end if;

 select * into account from sav_ai_crm.channel_accounts
 where workspace_id=me.workspace_id and channel=c.channel and status='connected'
 order by updated_at desc limit 1;
 sender_identity:=account.sender_identity;

 insert into sav_ai_crm.messages(workspace_id,conversation_id,channel,direction,sender_type,sender_name,sender,recipient,message_type,body,delivery_status,is_read,sent_by_member_id,sent_by_agent_id,metadata,updated_at)
 values(me.workspace_id,c.id,c.channel,'outbound',case when p_agent_id is null then 'human' else 'ai_agent' end,
   case when p_agent_id is null then coalesce(me.full_name,me.email) else agent.display_name end,
   sender_identity,nullif(trim(coalesce(p_recipient,'')),''),p_message_type,nullif(p_body,''),'QUEUED',true,
   case when p_agent_id is null then me.id else null end,p_agent_id,
   jsonb_build_object('channel_account_id',account.id,'provider',coalesce(account.provider,'unconfigured'),'provider_configured',account.id is not null and sender_identity is not null),now())
 returning id into mid;

 if jsonb_typeof(coalesce(p_attachments,'[]'::jsonb))='array' then
   insert into sav_ai_crm.message_attachments(workspace_id,message_id,file_name,mime_type,size_bytes,external_url,provider_attachment_id,metadata)
   select me.workspace_id,mid,x->>'file_name',x->>'mime_type',nullif(x->>'size_bytes','')::bigint,x->>'external_url',x->>'provider_attachment_id',coalesce(x->'metadata','{}'::jsonb)
   from jsonb_array_elements(p_attachments) x
   where coalesce(x->>'file_name','')<>'' and coalesce(x->>'mime_type','')<>'';
 end if;
 insert into sav_ai_crm.message_delivery_events(workspace_id,message_id,status) values(me.workspace_id,mid,'QUEUED');
 insert into sav_ai_crm.conversation_activity(workspace_id,conversation_id,message_id,actor_member_id,actor_agent_id,activity_type,title,metadata)
 values(me.workspace_id,c.id,mid,case when p_agent_id is null then me.id else null end,p_agent_id,'message_queued','Outbound message queued',jsonb_build_object('channel',c.channel));
 insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id,metadata)
 values(me.workspace_id,auth.uid(),'inbox.message.queued','message',mid,jsonb_build_object('conversation_id',c.id,'channel',c.channel,'agent_id',p_agent_id));

 return jsonb_build_object('message_id',mid,'conversation_id',c.id,'channel',c.channel,'channel_account_id',account.id,'provider',coalesce(account.provider,'unconfigured'),'sender',sender_identity,'recipient',p_recipient,'provider_configured',account.id is not null and sender_identity is not null,'approval_required',false);
end $$;

create or replace function public.sav_ai_crm_mark_message_sending(p_message_id uuid)
returns jsonb language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; m sav_ai_crm.messages; c sav_ai_crm.conversations;
begin
 me:=sav_ai_crm.inbox_current_member();
 if me.id is null or not sav_ai_crm.inbox_can_write(me.role) then raise exception 'Message send not permitted'; end if;
 select * into m from sav_ai_crm.messages where id=p_message_id and workspace_id=me.workspace_id for update;
 if m.id is null then raise exception 'Message not found'; end if;
 if m.delivery_status not in ('QUEUED','FAILED') then raise exception 'Message is not sendable'; end if;
 select * into c from sav_ai_crm.conversations where id=m.conversation_id and workspace_id=me.workspace_id;
 update sav_ai_crm.messages set delivery_status='SENDING',error_code=null,error_message=null,updated_at=now() where id=m.id;
 insert into sav_ai_crm.message_delivery_events(workspace_id,message_id,status) values(me.workspace_id,m.id,'SENDING');
 return jsonb_build_object('message_id',m.id,'conversation_id',c.id,'channel',c.channel,'sender',m.sender,'recipient',m.recipient,'message_type',m.message_type,'body',m.body,'metadata',m.metadata);
end $$;

create or replace function public.sav_ai_crm_record_message_result(
 p_message_id uuid,p_ok boolean,p_provider text,p_provider_message_id text default null,p_status text default null,p_error_code text default null,p_error_message text default null,p_raw jsonb default '{}'::jsonb
) returns void language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; m sav_ai_crm.messages; final_status text;
begin
 me:=sav_ai_crm.inbox_current_member();
 if me.id is null or not sav_ai_crm.inbox_can_write(me.role) then raise exception 'Message result not permitted'; end if;
 select * into m from sav_ai_crm.messages where id=p_message_id and workspace_id=me.workspace_id for update;
 if m.id is null then raise exception 'Message not found'; end if;
 final_status:=case when p_ok then coalesce(p_status,'SENT') else 'FAILED' end;
 if final_status not in ('SENT','DELIVERED','READ','FAILED') then raise exception 'Invalid delivery result'; end if;
 if p_ok and coalesce(p_provider_message_id,'')='' then raise exception 'Provider message ID required for successful send'; end if;
 update sav_ai_crm.messages set provider_message_id=case when p_ok then p_provider_message_id else provider_message_id end,
   delivery_status=final_status,error_code=case when p_ok then null else coalesce(p_error_code,'CHANNEL_PROVIDER_ERROR') end,
   error_message=case when p_ok then null else p_error_message end,updated_at=now()
 where id=m.id;
 insert into sav_ai_crm.message_delivery_events(workspace_id,message_id,provider_message_id,status,error_code,error_message,raw_metadata)
 values(me.workspace_id,m.id,p_provider_message_id,final_status,case when p_ok then null else coalesce(p_error_code,'CHANNEL_PROVIDER_ERROR') end,p_error_message,coalesce(p_raw,'{}'));
 if p_ok then
  update sav_ai_crm.conversations set last_message_at=now(),last_message_preview=left(coalesce(m.body,''),180),updated_at=now() where id=m.conversation_id;
 end if;
 insert into sav_ai_crm.conversation_activity(workspace_id,conversation_id,message_id,actor_member_id,activity_type,title,description,metadata)
 values(me.workspace_id,m.conversation_id,m.id,me.id,case when p_ok then 'message_sent' else 'provider_failure' end,
   case when p_ok then 'Message sent' else 'Message failed' end,p_error_message,jsonb_build_object('provider',p_provider,'status',final_status,'provider_message_id',p_provider_message_id));
 insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id,metadata)
 values(me.workspace_id,auth.uid(),case when p_ok then 'inbox.message.sent' else 'inbox.message.failed' end,'message',m.id,jsonb_build_object('provider',p_provider,'status',final_status,'error_code',p_error_code));
end $$;

create or replace function public.sav_ai_crm_mark_message_read(p_message_id uuid,p_read boolean default true)
returns void language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; m sav_ai_crm.messages;
begin
 me:=sav_ai_crm.inbox_current_member();
 if me.id is null then raise exception 'CRM membership required'; end if;
 select * into m from sav_ai_crm.messages where id=p_message_id and workspace_id=me.workspace_id;
 if m.id is null then raise exception 'Message not found'; end if;
 update sav_ai_crm.messages set is_read=p_read,read_at=case when p_read then now() else null end,
   delivery_status=case when p_read and direction='outbound' and delivery_status in ('SENT','DELIVERED') then 'READ' else delivery_status end,updated_at=now()
 where id=m.id;
 if m.direction='inbound' then
   update sav_ai_crm.conversations set unread_count=(select count(*) from sav_ai_crm.messages x where x.conversation_id=m.conversation_id and x.workspace_id=me.workspace_id and x.direction='inbound' and not x.is_read),updated_at=now()
   where id=m.conversation_id;
 end if;
end $$;

create or replace function public.sav_ai_crm_add_internal_note(p_conversation_id uuid,p_body text)
returns uuid language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; c sav_ai_crm.conversations; mid uuid;
begin
 me:=sav_ai_crm.inbox_current_member();
 if me.id is null or not sav_ai_crm.inbox_can_write(me.role) then raise exception 'Internal note not permitted'; end if;
 select * into c from sav_ai_crm.conversations where id=p_conversation_id and workspace_id=me.workspace_id;
 if c.id is null then raise exception 'Conversation not found'; end if;
 if length(trim(coalesce(p_body,'')))<1 then raise exception 'Note required'; end if;
 insert into sav_ai_crm.messages(workspace_id,conversation_id,channel,direction,sender_type,sender_name,message_type,body,delivery_status,is_read,sent_by_member_id,metadata,updated_at)
 values(me.workspace_id,c.id,c.channel,'outbound','system',coalesce(me.full_name,me.email),'note',trim(p_body),'SENT',true,me.id,'{"internal":true}'::jsonb,now())
 returning id into mid;
 insert into sav_ai_crm.conversation_activity(workspace_id,conversation_id,message_id,actor_member_id,activity_type,title,description)
 values(me.workspace_id,c.id,mid,me.id,'internal_note','Internal note added',left(trim(p_body),180));
 insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id)
 values(me.workspace_id,auth.uid(),'inbox.note.create','message',mid);
 return mid;
end $$;

-- ---------------------------------------------------------------------------
-- Inbound webhook persistence (called only after server adapter verification)
-- ---------------------------------------------------------------------------
create or replace function public.sav_ai_crm_resolve_channel_account(p_channel text,p_provider text,p_external_account_id text default null,p_webhook_external_key text default null)
returns jsonb language plpgsql stable security definer
set search_path=public,sav_ai_crm
as $$
declare acc sav_ai_crm.channel_accounts;
begin
 select * into acc from sav_ai_crm.channel_accounts
 where channel=p_channel and provider=p_provider and status='connected'
   and (p_external_account_id is null or external_account_id=p_external_account_id)
   and (p_webhook_external_key is null or webhook_external_key=p_webhook_external_key)
 order by updated_at desc limit 1;
 if acc.id is null then raise exception 'CHANNEL_PROVIDER_NOT_CONFIGURED'; end if;
 return jsonb_build_object('id',acc.id,'workspace_id',acc.workspace_id,'channel',acc.channel,'provider',acc.provider);
end $$;

create or replace function public.sav_ai_crm_persist_inbound_message(
 p_workspace_id uuid,p_channel_account_id uuid,p_provider text,p_provider_event_id text,p_provider_message_id text,p_channel text,
 p_sender text,p_recipient text,p_body text,p_message_type text,p_external_thread_id text default null,p_received_at timestamptz default now(),p_attachments jsonb default '[]'::jsonb,p_metadata jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare acc sav_ai_crm.channel_accounts; cid uuid; mid uuid; resolved_lead_id uuid; resolved_contact_id uuid; duplicate_mid uuid;
begin
 select * into acc from sav_ai_crm.channel_accounts where id=p_channel_account_id and workspace_id=p_workspace_id and channel=p_channel and provider=p_provider and status='connected';
 if acc.id is null then raise exception 'CHANNEL_PROVIDER_NOT_CONFIGURED'; end if;
 if p_message_type not in ('text','html','image','file','audio','video') then raise exception 'Invalid inbound message type'; end if;

 select m.id into duplicate_mid from sav_ai_crm.messages m where m.workspace_id=p_workspace_id and m.provider_message_id=p_provider_message_id limit 1;
 if duplicate_mid is not null then return jsonb_build_object('duplicate',true,'message_id',duplicate_mid); end if;

 insert into sav_ai_crm.channel_webhook_events(workspace_id,channel_account_id,channel,provider,provider_event_id,provider_message_id,signature_verified,processing_status,metadata)
 values(p_workspace_id,acc.id,p_channel,p_provider,p_provider_event_id,p_provider_message_id,true,'received',coalesce(p_metadata,'{}'))
 on conflict(workspace_id,provider,provider_event_id) do nothing;
 if not found then
   return jsonb_build_object('duplicate',true,'provider_event_id',p_provider_event_id);
 end if;

 select ct.id into resolved_contact_id from sav_ai_crm.contacts ct where ct.workspace_id=p_workspace_id and (ct.phone=p_sender or lower(ct.email)=lower(p_sender)) order by ct.updated_at desc limit 1;
 if resolved_contact_id is null then
   select l.id into resolved_lead_id from sav_ai_crm.leads l where l.workspace_id=p_workspace_id and (l.phone=p_sender or lower(l.email)=lower(p_sender)) order by l.updated_at desc limit 1;
 end if;

 select cv.id into cid from sav_ai_crm.conversations cv
 where cv.workspace_id=p_workspace_id and cv.channel=p_channel and cv.archived_at is null
   and ((p_external_thread_id is not null and cv.external_thread_id=p_external_thread_id)
     or (resolved_contact_id is not null and cv.contact_id=resolved_contact_id)
     or (resolved_lead_id is not null and cv.lead_id=resolved_lead_id))
 order by last_message_at desc nulls last,created_at desc limit 1;

 if cid is null then
  insert into sav_ai_crm.conversations(workspace_id,contact_id,lead_id,channel,external_thread_id,status,priority,unread_count,last_message_at,last_message_preview,created_at,updated_at)
  values(p_workspace_id,resolved_contact_id,resolved_lead_id,p_channel,p_external_thread_id,'open','medium',0,p_received_at,left(coalesce(p_body,''),180),now(),now()) returning id into cid;
  insert into sav_ai_crm.conversation_activity(workspace_id,conversation_id,activity_type,title,metadata)
  values(p_workspace_id,cid,'conversation_created','Conversation created from inbound message',jsonb_build_object('provider',p_provider,'channel',p_channel));
 end if;

 insert into sav_ai_crm.messages(workspace_id,conversation_id,channel,direction,sender_type,sender_name,sender,recipient,message_type,body,provider_message_id,delivery_status,is_read,metadata,created_at,updated_at)
 values(p_workspace_id,cid,p_channel,'inbound','contact',p_sender,p_sender,p_recipient,p_message_type,nullif(p_body,''),p_provider_message_id,'DELIVERED',false,coalesce(p_metadata,'{}'),p_received_at,now())
 returning id into mid;

 if jsonb_typeof(coalesce(p_attachments,'[]'::jsonb))='array' then
   insert into sav_ai_crm.message_attachments(workspace_id,message_id,file_name,mime_type,size_bytes,external_url,provider_attachment_id,metadata)
   select p_workspace_id,mid,x->>'file_name',x->>'mime_type',nullif(x->>'size_bytes','')::bigint,x->>'external_url',x->>'provider_attachment_id',coalesce(x->'metadata','{}'::jsonb)
   from jsonb_array_elements(p_attachments) x where coalesce(x->>'file_name','')<>'' and coalesce(x->>'mime_type','')<>'';
 end if;
 insert into sav_ai_crm.message_delivery_events(workspace_id,message_id,provider_event_id,provider_message_id,status,raw_metadata,event_at)
 values(p_workspace_id,mid,p_provider_event_id,p_provider_message_id,'DELIVERED',coalesce(p_metadata,'{}'),p_received_at);
 update sav_ai_crm.conversations set unread_count=unread_count+1,last_message_at=p_received_at,last_message_preview=left(coalesce(p_body,''),180),updated_at=now() where id=cid;
 insert into sav_ai_crm.conversation_activity(workspace_id,conversation_id,message_id,activity_type,title,metadata)
 values(p_workspace_id,cid,mid,'message_received','Inbound message received',jsonb_build_object('provider',p_provider,'channel',p_channel));
 insert into sav_ai_crm.audit_logs(workspace_id,action,entity_type,entity_id,metadata)
 values(p_workspace_id,'inbox.message.received','message',mid,jsonb_build_object('conversation_id',cid,'provider',p_provider,'channel',p_channel));
 update sav_ai_crm.channel_webhook_events set processing_status='processed',processed_at=now() where workspace_id=p_workspace_id and provider=p_provider and provider_event_id=p_provider_event_id;
 return jsonb_build_object('duplicate',false,'conversation_id',cid,'message_id',mid,'lead_id',resolved_lead_id,'contact_id',resolved_contact_id);
end $$;

revoke all on function public.sav_ai_crm_resolve_channel_account(text,text,text,text) from public,anon,authenticated;
revoke all on function public.sav_ai_crm_persist_inbound_message(uuid,uuid,text,text,text,text,text,text,text,text,text,timestamptz,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.sav_ai_crm_resolve_channel_account(text,text,text,text) to service_role;
grant execute on function public.sav_ai_crm_persist_inbound_message(uuid,uuid,text,text,text,text,text,text,text,text,text,timestamptz,jsonb,jsonb) to service_role;

-- ---------------------------------------------------------------------------
-- Channel delivery events
-- ---------------------------------------------------------------------------
create or replace function public.sav_ai_crm_apply_delivery_event(
 p_workspace_id uuid,p_provider text,p_provider_event_id text,p_provider_message_id text,p_status text,p_error_code text default null,p_error_message text default null,p_metadata jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare m sav_ai_crm.messages; rank_old integer; rank_new integer;
begin
 if p_status not in ('SENT','DELIVERED','READ','FAILED') then raise exception 'Invalid delivery status'; end if;
 select * into m from sav_ai_crm.messages where workspace_id=p_workspace_id and provider_message_id=p_provider_message_id limit 1 for update;
 if m.id is null then raise exception 'Message not found'; end if;
 insert into sav_ai_crm.message_delivery_events(workspace_id,message_id,provider_event_id,provider_message_id,status,error_code,error_message,raw_metadata)
 values(p_workspace_id,m.id,p_provider_event_id,p_provider_message_id,p_status,p_error_code,p_error_message,coalesce(p_metadata,'{}'))
 on conflict(workspace_id,provider_event_id) where provider_event_id is not null do nothing;
 if not found then return jsonb_build_object('duplicate',true,'message_id',m.id); end if;
 rank_old:=case m.delivery_status when 'QUEUED' then 1 when 'SENDING' then 2 when 'SENT' then 3 when 'DELIVERED' then 4 when 'READ' then 5 else 0 end;
 rank_new:=case p_status when 'SENT' then 3 when 'DELIVERED' then 4 when 'READ' then 5 when 'FAILED' then 6 else 0 end;
 if p_status='FAILED' or rank_new>=rank_old then
  update sav_ai_crm.messages set delivery_status=p_status,is_read=case when p_status='READ' then true else is_read end,read_at=case when p_status='READ' then now() else read_at end,
    error_code=case when p_status='FAILED' then p_error_code else null end,error_message=case when p_status='FAILED' then p_error_message else null end,updated_at=now() where id=m.id;
 end if;
 insert into sav_ai_crm.conversation_activity(workspace_id,conversation_id,message_id,activity_type,title,description,metadata)
 values(p_workspace_id,m.conversation_id,m.id,'delivery_update','Message delivery update',p_error_message,jsonb_build_object('provider',p_provider,'status',p_status,'provider_event_id',p_provider_event_id));
 insert into sav_ai_crm.audit_logs(workspace_id,action,entity_type,entity_id,metadata)
 values(p_workspace_id,'inbox.delivery.update','message',m.id,jsonb_build_object('provider',p_provider,'status',p_status));
 return jsonb_build_object('duplicate',false,'message_id',m.id,'conversation_id',m.conversation_id,'status',p_status);
end $$;
revoke all on function public.sav_ai_crm_apply_delivery_event(uuid,text,text,text,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.sav_ai_crm_apply_delivery_event(uuid,text,text,text,text,text,text,jsonb) to service_role;

-- ---------------------------------------------------------------------------
-- Task/follow-up integration through existing Phase 1 boundary
-- ---------------------------------------------------------------------------
create or replace function public.sav_ai_crm_inbox_create_task(
 p_conversation_id uuid,p_title text,p_description text default null,p_followup_type text default 'general',p_priority text default 'medium',
 p_due_at timestamptz default null,p_reminder_at timestamptz default null,p_assignee_type text default 'human',p_assigned_to uuid default null,p_assigned_agent_id uuid default null
) returns uuid language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; c sav_ai_crm.conversations; tid uuid;
begin
 me:=sav_ai_crm.inbox_current_member();
 if me.id is null or not sav_ai_crm.inbox_can_write(me.role) then raise exception 'Task creation not permitted'; end if;
 select * into c from sav_ai_crm.conversations where id=p_conversation_id and workspace_id=me.workspace_id and archived_at is null;
 if c.id is null then raise exception 'Conversation not found'; end if;
 tid:=public.sav_ai_crm_create_task(p_title,p_description,p_followup_type,p_priority,'pending',p_due_at,p_reminder_at,c.lead_id,c.contact_id,'Created from Inbox conversation '||c.id::text,p_assignee_type,p_assigned_to,p_assigned_agent_id);
 insert into sav_ai_crm.conversation_activity(workspace_id,conversation_id,actor_member_id,activity_type,title,metadata)
 values(me.workspace_id,c.id,me.id,case when p_followup_type='general' then 'task_created' else 'followup_created' end,
   case when p_followup_type='general' then 'Task created from conversation' else 'Follow-up created from conversation' end,jsonb_build_object('task_id',tid));
 return tid;
end $$;

-- ---------------------------------------------------------------------------
-- Phase 2 AI integration: draft only; sending still uses controlled SEND_MESSAGE
-- ---------------------------------------------------------------------------
create or replace function public.sav_ai_crm_request_conversation_ai(p_conversation_id uuid,p_agent_id uuid,p_mode text,p_instruction text default null)
returns jsonb language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; c sav_ai_crm.conversations; agent sav_ai_crm.ai_agents; result jsonb;
begin
 me:=sav_ai_crm.inbox_current_member();
 if me.id is null or not sav_ai_crm.inbox_can_write(me.role) then raise exception 'AI conversation action not permitted'; end if;
 select * into c from sav_ai_crm.conversations where id=p_conversation_id and workspace_id=me.workspace_id and archived_at is null;
 if c.id is null then raise exception 'Conversation not found'; end if;
 select * into agent from sav_ai_crm.ai_agents where id=p_agent_id and workspace_id=me.workspace_id and status='active';
 if agent.id is null then raise exception 'AI agent not found'; end if;
 if p_mode not in ('draft_reply','summarize','escalate') then raise exception 'Invalid AI conversation mode'; end if;
 if not 'READ_CONVERSATION'=any(agent.capabilities) then raise exception 'AI agent lacks READ_CONVERSATION capability'; end if;
 if p_mode='draft_reply' then
   if not 'SEND_MESSAGE'=any(agent.capabilities) or not c.channel=any(agent.channels) then raise exception 'AI agent lacks channel SEND_MESSAGE capability'; end if;
   result:=jsonb_build_object(
     'draft_allowed',true,'mode','draft_reply','agent_id',agent.id,'conversation_id',c.id,
     'channel',c.channel,'send_requires_approval',true,'instruction',p_instruction
   );
 elsif p_mode='escalate' then
   result:=public.sav_ai_crm_request_agent_action(agent.id,'CREATE_ESCALATION','conversation',c.id,jsonb_build_object('reason','AI_ESCALATION','details',p_instruction));
 else
   result:=jsonb_build_object('draft_only',true,'mode','summarize','agent_id',agent.id,'conversation_id',c.id,'instruction',p_instruction);
 end if;
 insert into sav_ai_crm.conversation_activity(workspace_id,conversation_id,actor_member_id,actor_agent_id,activity_type,title,metadata)
 values(me.workspace_id,c.id,me.id,agent.id,'ai_action_requested','AI conversation action requested',jsonb_build_object('mode',p_mode,'result',result));
 insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id,metadata)
 values(me.workspace_id,auth.uid(),'inbox.ai.request','conversation',c.id,jsonb_build_object('agent_id',agent.id,'mode',p_mode));
 return result;
end $$;

create or replace function public.sav_ai_crm_ai_draft_context(p_message_id uuid,p_agent_id uuid,p_instruction text default null)
returns jsonb language plpgsql security definer
set search_path=public,sav_ai_crm
as $
declare me sav_ai_crm.members; m sav_ai_crm.messages; c sav_ai_crm.conversations; agent sav_ai_crm.ai_agents; permission jsonb;
begin
 me:=sav_ai_crm.inbox_current_member();
 if me.id is null or not sav_ai_crm.inbox_can_write(me.role) then raise exception 'AI draft not permitted'; end if;
 select * into m from sav_ai_crm.messages where id=p_message_id and workspace_id=me.workspace_id;
 if m.id is null then raise exception 'Message not found'; end if;
 select * into c from sav_ai_crm.conversations where id=m.conversation_id and workspace_id=me.workspace_id and archived_at is null;
 if c.id is null then raise exception 'Conversation not found'; end if;
 select * into agent from sav_ai_crm.ai_agents where id=p_agent_id and workspace_id=me.workspace_id and status='active';
 if agent.id is null then raise exception 'AI agent not found'; end if;
 if not 'READ_CONVERSATION'=any(agent.capabilities) or not 'SEND_MESSAGE'=any(agent.capabilities) or not c.channel=any(agent.channels) then
   raise exception 'AI agent lacks conversation/channel capabilities';
 end if;
 permission:=public.sav_ai_crm_request_conversation_ai(c.id,agent.id,'draft_reply',p_instruction);
 return jsonb_build_object(
   'permission',permission,
   'conversation_id',c.id,'message_id',m.id,'agent_id',agent.id,'agent_name',coalesce(agent.display_name,agent.name),
   'channel',c.channel,'instruction',p_instruction,
   'messages',coalesce((select jsonb_agg(jsonb_build_object(
      'role',case when x.direction='inbound' then 'customer' else case when x.sender_type='ai_agent' then 'assistant' else 'human' end end,
      'content',coalesce(x.body,''),'created_at',x.created_at,'message_type',x.message_type
    ) order by x.created_at) from (
      select * from sav_ai_crm.messages where conversation_id=c.id and workspace_id=me.workspace_id and message_type<>'note' order by created_at desc limit 50
    ) x),'[]'::jsonb)
 );
end $;

-- ---------------------------------------------------------------------------
-- Phase 3 workflow event extension; same engine, no second workflow system
-- ---------------------------------------------------------------------------
alter table sav_ai_crm.workflow_triggers drop constraint if exists workflow_triggers_event_check;
alter table sav_ai_crm.workflow_triggers add constraint workflow_triggers_event_check check (event in (
 'NEW_LEAD','LEAD_STATUS_CHANGED','PIPELINE_STAGE_CHANGED','TASK_CREATED','TASK_COMPLETED','FOLLOWUP_DUE','REMINDER_DUE',
 'CONVERSATION_RECEIVED','MANUAL_TRIGGER','SCHEDULED_TRIGGER','AI_ESCALATION',
 'CONVERSATION_CREATED','CONVERSATION_ASSIGNED','MESSAGE_RECEIVED','MESSAGE_DELIVERED','MESSAGE_FAILED','CONVERSATION_CLOSED','CONVERSATION_REOPENED'
));

create or replace function public.sav_ai_crm_dispatch_workflow_event(p_event text,p_context jsonb,p_event_key text)
returns jsonb language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; tr record; results jsonb:='[]'::jsonb; eid uuid; run_result jsonb; idem text;
begin
 me:=sav_ai_crm.workflow_current_member();
 if me.id is null or me.role='viewer' then raise exception 'Workflow event dispatch not permitted'; end if;
 if p_event not in (
   'NEW_LEAD','LEAD_STATUS_CHANGED','PIPELINE_STAGE_CHANGED','TASK_CREATED','TASK_COMPLETED','FOLLOWUP_DUE','REMINDER_DUE',
   'CONVERSATION_RECEIVED','MANUAL_TRIGGER','SCHEDULED_TRIGGER','AI_ESCALATION',
   'CONVERSATION_CREATED','CONVERSATION_ASSIGNED','MESSAGE_RECEIVED','MESSAGE_DELIVERED','MESSAGE_FAILED','CONVERSATION_CLOSED','CONVERSATION_REOPENED'
 ) then raise exception 'Invalid workflow event'; end if;
 if coalesce(trim(p_event_key),'')='' then raise exception 'Event idempotency key is required'; end if;
 for tr in select t.* from sav_ai_crm.workflow_triggers t join sav_ai_crm.workflows w on w.id=t.workflow_id
   where t.workspace_id=me.workspace_id and t.event=p_event and t.enabled=true and w.status='active' and w.archived_at is null
 loop
   if sav_ai_crm.workflow_conditions_match(tr.conditions,coalesce(p_context,'{}')) then
     idem:='event:'||p_event||':'||p_event_key||':'||tr.workflow_id::text;
     eid:=public.sav_ai_crm_start_workflow(tr.workflow_id,coalesce(p_context,'{}'),idem,p_event);
     run_result:=public.sav_ai_crm_run_workflow_execution(eid);
     results:=results||jsonb_build_array(jsonb_build_object('workflow_id',tr.workflow_id,'execution_id',eid,'result',run_result));
   end if;
 end loop;
 return results;
end $$;

-- ---------------------------------------------------------------------------
-- Channel account metadata management (credentials remain server-side refs)
-- ---------------------------------------------------------------------------
create or replace function public.sav_ai_crm_channel_accounts()
returns jsonb language plpgsql stable security definer
set search_path=public,sav_ai_crm
as $
declare me sav_ai_crm.members;
begin
 me:=sav_ai_crm.inbox_current_member();
 if me.id is null then raise exception 'CRM membership required'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object(
   'id',a.id,'channel',a.channel,'provider',a.provider,'display_name',a.display_name,'external_account_id',a.external_account_id,
   'sender_identity',a.sender_identity,'status',a.status,'public_config',a.public_config,'has_secret_ref',a.secret_ref is not null,
   'created_at',a.created_at,'updated_at',a.updated_at
 ) order by a.channel,a.display_name) from sav_ai_crm.channel_accounts a where a.workspace_id=me.workspace_id),'[]'::jsonb);
end $;

create or replace function public.sav_ai_crm_upsert_channel_account(
 p_account_id uuid,p_channel text,p_provider text,p_display_name text,p_external_account_id text default null,
 p_sender_identity text default null,p_status text default 'disconnected',p_public_config jsonb default '{}'::jsonb,p_secret_ref text default null
) returns uuid language plpgsql security definer
set search_path=public,sav_ai_crm
as $
declare me sav_ai_crm.members; aid uuid;
begin
 me:=sav_ai_crm.inbox_current_member();
 if me.id is null or me.role not in ('owner','admin') then raise exception 'Channel management requires owner or admin'; end if;
 if p_channel not in ('whatsapp','email','sms','voice','webchat') then raise exception 'Invalid channel'; end if;
 if p_status not in ('connected','disconnected','error','disabled') then raise exception 'Invalid channel status'; end if;
 if length(trim(coalesce(p_provider,'')))<2 or length(trim(coalesce(p_display_name,'')))<2 then raise exception 'Provider and display name required'; end if;
 if p_secret_ref is not null and (length(p_secret_ref)>180 or p_secret_ref ~ '[[:space:]]') then raise exception 'Invalid server secret reference'; end if;
 if p_account_id is null then
   insert into sav_ai_crm.channel_accounts(workspace_id,channel,provider,display_name,external_account_id,sender_identity,status,public_config,secret_ref,created_by,updated_by)
   values(me.workspace_id,p_channel,trim(p_provider),trim(p_display_name),nullif(trim(coalesce(p_external_account_id,'')),''),nullif(trim(coalesce(p_sender_identity,'')),''),p_status,coalesce(p_public_config,'{}'),nullif(trim(coalesce(p_secret_ref,'')),''),me.id,me.id)
   returning id into aid;
 else
   update sav_ai_crm.channel_accounts set channel=p_channel,provider=trim(p_provider),display_name=trim(p_display_name),
     external_account_id=nullif(trim(coalesce(p_external_account_id,'')),''),sender_identity=nullif(trim(coalesce(p_sender_identity,'')),''),
     status=p_status,public_config=coalesce(p_public_config,'{}'),secret_ref=nullif(trim(coalesce(p_secret_ref,'')),''),updated_by=me.id,updated_at=now()
   where id=p_account_id and workspace_id=me.workspace_id returning id into aid;
   if aid is null then raise exception 'Channel account not found'; end if;
 end if;
 insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id,metadata)
 values(me.workspace_id,auth.uid(),'inbox.channel.configure','channel_account',aid,jsonb_build_object('channel',p_channel,'provider',p_provider,'status',p_status));
 return aid;
end $;

create or replace function sav_ai_crm.dispatch_workflow_event_system(p_workspace_id uuid,p_event text,p_context jsonb,p_event_key text)
returns jsonb language plpgsql security definer
set search_path=public,sav_ai_crm
as $
declare tr record; results jsonb:='[]'::jsonb; eid uuid; run_result jsonb; idem text;
begin
 if p_event not in (
   'CONVERSATION_CREATED','CONVERSATION_ASSIGNED','MESSAGE_RECEIVED','MESSAGE_DELIVERED','MESSAGE_FAILED','CONVERSATION_CLOSED','CONVERSATION_REOPENED'
 ) then raise exception 'Invalid system workflow event'; end if;
 if coalesce(trim(p_event_key),'')='' then raise exception 'Event idempotency key is required'; end if;
 for tr in select t.* from sav_ai_crm.workflow_triggers t join sav_ai_crm.workflows w on w.id=t.workflow_id
   where t.workspace_id=p_workspace_id and t.event=p_event and t.enabled=true and w.status='active' and w.archived_at is null
 loop
   if sav_ai_crm.workflow_conditions_match(tr.conditions,coalesce(p_context,'{}')) then
     idem:='system-event:'||p_event||':'||p_event_key||':'||tr.workflow_id::text;
     insert into sav_ai_crm.workflow_executions(
       workspace_id,workflow_id,workflow_version,trigger,context,current_node_id,execution_state,idempotency_key,started_at
     )
     select p_workspace_id,w.id,w.version,p_event,coalesce(p_context,'{}'),n.id,'queued',idem,now()
     from sav_ai_crm.workflows w
     join sav_ai_crm.workflow_nodes n on n.workflow_id=w.id and n.workflow_version=w.version and n.node_type='TRIGGER'
     where w.id=tr.workflow_id
     order by n.created_at limit 1
     on conflict(workspace_id,idempotency_key) do nothing
     returning id into eid;
     if eid is null then
       select id into eid from sav_ai_crm.workflow_executions where workspace_id=p_workspace_id and idempotency_key=idem;
     end if;
     if eid is not null then
       -- System webhook dispatch only queues execution. Authenticated workers/users resume it through existing engine.
       results:=results||jsonb_build_array(jsonb_build_object('workflow_id',tr.workflow_id,'execution_id',eid,'status','queued'));
     end if;
   end if;
 end loop;
 return results;
end $;

revoke all on function sav_ai_crm.dispatch_workflow_event_system(uuid,text,jsonb,text) from public,anon,authenticated;
grant execute on function sav_ai_crm.dispatch_workflow_event_system(uuid,text,jsonb,text) to service_role;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
revoke all on function public.sav_ai_crm_channel_accounts() from public,anon;
revoke all on function public.sav_ai_crm_upsert_channel_account(uuid,text,text,text,text,text,text,jsonb,text) from public,anon;
revoke all on function public.sav_ai_crm_inbox_context() from public,anon;
revoke all on function public.sav_ai_crm_inbox_conversations(text,text,text,boolean,text) from public,anon;
revoke all on function public.sav_ai_crm_inbox_conversation_detail(uuid) from public,anon;
revoke all on function public.sav_ai_crm_create_conversation(text,text,uuid,uuid,text,text) from public,anon;
revoke all on function public.sav_ai_crm_update_conversation(uuid,text,uuid,uuid,text,text[],boolean,boolean) from public,anon;
revoke all on function public.sav_ai_crm_assign_conversation(uuid,text,uuid,uuid,text) from public,anon;
revoke all on function public.sav_ai_crm_set_conversation_state(uuid,text) from public,anon;
revoke all on function public.sav_ai_crm_escalate_conversation(uuid,text) from public,anon;
revoke all on function public.sav_ai_crm_queue_outbound_message(uuid,text,text,text,uuid,jsonb) from public,anon;
revoke all on function public.sav_ai_crm_mark_message_sending(uuid) from public,anon;
revoke all on function public.sav_ai_crm_record_message_result(uuid,boolean,text,text,text,text,text,jsonb) from public,anon;
revoke all on function public.sav_ai_crm_mark_message_read(uuid,boolean) from public,anon;
revoke all on function public.sav_ai_crm_add_internal_note(uuid,text) from public,anon;
revoke all on function public.sav_ai_crm_inbox_create_task(uuid,text,text,text,text,timestamptz,timestamptz,text,uuid,uuid) from public,anon;
revoke all on function public.sav_ai_crm_request_conversation_ai(uuid,uuid,text,text) from public,anon;
revoke all on function public.sav_ai_crm_ai_draft_context(uuid,uuid,text) from public,anon;

grant execute on function public.sav_ai_crm_channel_accounts() to authenticated;
grant execute on function public.sav_ai_crm_upsert_channel_account(uuid,text,text,text,text,text,text,jsonb,text) to authenticated;
grant execute on function public.sav_ai_crm_inbox_context() to authenticated;
grant execute on function public.sav_ai_crm_inbox_conversations(text,text,text,boolean,text) to authenticated;
grant execute on function public.sav_ai_crm_inbox_conversation_detail(uuid) to authenticated;
grant execute on function public.sav_ai_crm_create_conversation(text,text,uuid,uuid,text,text) to authenticated;
grant execute on function public.sav_ai_crm_update_conversation(uuid,text,uuid,uuid,text,text[],boolean,boolean) to authenticated;
grant execute on function public.sav_ai_crm_assign_conversation(uuid,text,uuid,uuid,text) to authenticated;
grant execute on function public.sav_ai_crm_set_conversation_state(uuid,text) to authenticated;
grant execute on function public.sav_ai_crm_escalate_conversation(uuid,text) to authenticated;
grant execute on function public.sav_ai_crm_queue_outbound_message(uuid,text,text,text,uuid,jsonb) to authenticated;
grant execute on function public.sav_ai_crm_mark_message_sending(uuid) to authenticated;
grant execute on function public.sav_ai_crm_record_message_result(uuid,boolean,text,text,text,text,text,jsonb) to authenticated;
grant execute on function public.sav_ai_crm_mark_message_read(uuid,boolean) to authenticated;
grant execute on function public.sav_ai_crm_add_internal_note(uuid,text) to authenticated;
grant execute on function public.sav_ai_crm_inbox_create_task(uuid,text,text,text,text,timestamptz,timestamptz,text,uuid,uuid) to authenticated;
grant execute on function public.sav_ai_crm_request_conversation_ai(uuid,uuid,text,text) to authenticated;
grant execute on function public.sav_ai_crm_ai_draft_context(uuid,uuid,text) to authenticated;

commit;
