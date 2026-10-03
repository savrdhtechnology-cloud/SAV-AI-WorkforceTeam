-- Snapshot of existing SAVRDH AI CRM base migration 20261002095012 (sav_ai_crm_isolated_foundation).
-- Copied read-only from Supabase migration history for reproducible staging verification.
-- Do not edit without reconciling against the original migration history.

create schema if not exists sav_ai_crm;

grant usage on schema sav_ai_crm to authenticated, anon;

create table if not exists sav_ai_crm.workspaces (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  company_name text,
  website text,
  status text not null default 'active' check (status in ('active','paused','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists sav_ai_crm.members (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner','admin','manager','sales','support','operations','viewer')),
  full_name text,
  email text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(workspace_id,user_id)
);

create table if not exists sav_ai_crm.contacts (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
  first_name text,
  last_name text,
  email text,
  phone text,
  company text,
  designation text,
  source text default 'manual',
  tags text[] not null default '{}',
  owner_id uuid references sav_ai_crm.members(id) on delete set null,
  last_contacted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists sav_ai_crm.leads (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
  contact_id uuid references sav_ai_crm.contacts(id) on delete set null,
  title text not null,
  company text,
  email text,
  phone text,
  source text not null default 'manual',
  status text not null default 'new' check (status in ('new','contacted','qualified','proposal','negotiation','won','lost','nurture')),
  priority text not null default 'medium' check (priority in ('low','medium','high','urgent')),
  score integer not null default 0 check (score between 0 and 100),
  value numeric(14,2) not null default 0,
  owner_id uuid references sav_ai_crm.members(id) on delete set null,
  next_followup_at timestamptz,
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists sav_ai_crm.deals (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
  lead_id uuid references sav_ai_crm.leads(id) on delete set null,
  name text not null,
  stage text not null default 'discovery' check (stage in ('discovery','qualified','proposal','negotiation','won','lost')),
  amount numeric(14,2) not null default 0,
  probability integer not null default 20 check (probability between 0 and 100),
  expected_close_date date,
  owner_id uuid references sav_ai_crm.members(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists sav_ai_crm.tasks (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
  lead_id uuid references sav_ai_crm.leads(id) on delete cascade,
  contact_id uuid references sav_ai_crm.contacts(id) on delete cascade,
  title text not null,
  description text,
  task_type text not null default 'followup',
  status text not null default 'pending' check (status in ('pending','in_progress','completed','cancelled')),
  priority text not null default 'medium' check (priority in ('low','medium','high','urgent')),
  due_at timestamptz,
  assigned_to uuid references sav_ai_crm.members(id) on delete set null,
  created_by uuid references sav_ai_crm.members(id) on delete set null,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

create table if not exists sav_ai_crm.activities (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
  lead_id uuid references sav_ai_crm.leads(id) on delete cascade,
  contact_id uuid references sav_ai_crm.contacts(id) on delete cascade,
  actor_member_id uuid references sav_ai_crm.members(id) on delete set null,
  activity_type text not null,
  title text not null,
  description text,
  channel text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists sav_ai_crm.conversations (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
  contact_id uuid references sav_ai_crm.contacts(id) on delete set null,
  lead_id uuid references sav_ai_crm.leads(id) on delete set null,
  channel text not null check (channel in ('whatsapp','email','sms','voice','webchat')),
  external_thread_id text,
  status text not null default 'open' check (status in ('open','waiting','closed')),
  assigned_to uuid references sav_ai_crm.members(id) on delete set null,
  last_message_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists sav_ai_crm.messages (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
  conversation_id uuid not null references sav_ai_crm.conversations(id) on delete cascade,
  direction text not null check (direction in ('inbound','outbound')),
  sender_type text not null default 'human' check (sender_type in ('human','ai_agent','system','contact')),
  sender_name text,
  body text,
  provider_message_id text,
  delivery_status text default 'pending',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists sav_ai_crm.ai_agents (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
  name text not null,
  slug text not null,
  role_name text not null,
  description text,
  status text not null default 'active' check (status in ('active','paused','draft')),
  channels text[] not null default '{}',
  autonomy_level text not null default 'assisted' check (autonomy_level in ('manual','assisted','autonomous')),
  approval_required boolean not null default true,
  configuration jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(workspace_id,slug)
);

create table if not exists sav_ai_crm.workflows (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
  name text not null,
  trigger_type text not null,
  status text not null default 'draft' check (status in ('draft','active','paused')),
  agent_id uuid references sav_ai_crm.ai_agents(id) on delete set null,
  definition jsonb not null default '{}'::jsonb,
  run_count bigint not null default 0,
  success_count bigint not null default 0,
  last_run_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists sav_ai_crm.workflow_runs (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
  workflow_id uuid not null references sav_ai_crm.workflows(id) on delete cascade,
  status text not null default 'running' check (status in ('queued','running','success','failed','cancelled')),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  input jsonb not null default '{}'::jsonb,
  output jsonb not null default '{}'::jsonb,
  error_message text
);

create table if not exists sav_ai_crm.integrations (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
  provider text not null,
  display_name text not null,
  status text not null default 'disconnected' check (status in ('connected','disconnected','error')),
  config jsonb not null default '{}'::jsonb,
  connected_at timestamptz,
  updated_at timestamptz not null default now(),
  unique(workspace_id,provider)
);

create table if not exists sav_ai_crm.audit_logs (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_type text,
  entity_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists sav_ai_crm_leads_workspace_status_idx on sav_ai_crm.leads(workspace_id,status,created_at desc);
create index if not exists sav_ai_crm_contacts_workspace_idx on sav_ai_crm.contacts(workspace_id,created_at desc);
create index if not exists sav_ai_crm_tasks_workspace_due_idx on sav_ai_crm.tasks(workspace_id,status,due_at);
create index if not exists sav_ai_crm_activities_workspace_created_idx on sav_ai_crm.activities(workspace_id,created_at desc);
create index if not exists sav_ai_crm_messages_conversation_created_idx on sav_ai_crm.messages(conversation_id,created_at);
create index if not exists sav_ai_crm_workflow_runs_workspace_idx on sav_ai_crm.workflow_runs(workspace_id,started_at desc);

create or replace function sav_ai_crm.is_workspace_member(target_workspace uuid)
returns boolean
language sql
stable
security definer
set search_path = sav_ai_crm, public
as $$
  select exists (
    select 1
    from sav_ai_crm.members m
    where m.workspace_id = target_workspace
      and m.user_id = auth.uid()
      and m.is_active = true
  );
$$;

revoke all on function sav_ai_crm.is_workspace_member(uuid) from public;
grant execute on function sav_ai_crm.is_workspace_member(uuid) to authenticated;

alter table sav_ai_crm.workspaces enable row level security;
alter table sav_ai_crm.members enable row level security;
alter table sav_ai_crm.contacts enable row level security;
alter table sav_ai_crm.leads enable row level security;
alter table sav_ai_crm.deals enable row level security;
alter table sav_ai_crm.tasks enable row level security;
alter table sav_ai_crm.activities enable row level security;
alter table sav_ai_crm.conversations enable row level security;
alter table sav_ai_crm.messages enable row level security;
alter table sav_ai_crm.ai_agents enable row level security;
alter table sav_ai_crm.workflows enable row level security;
alter table sav_ai_crm.workflow_runs enable row level security;
alter table sav_ai_crm.integrations enable row level security;
alter table sav_ai_crm.audit_logs enable row level security;

create policy "workspace members can read workspace" on sav_ai_crm.workspaces
for select to authenticated
using (sav_ai_crm.is_workspace_member(id));

create policy "members can view workspace members" on sav_ai_crm.members
for select to authenticated
using (sav_ai_crm.is_workspace_member(workspace_id));

create policy "members can update self profile" on sav_ai_crm.members
for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

do $$
declare t text;
begin
  foreach t in array array['contacts','leads','deals','tasks','activities','conversations','messages','ai_agents','workflows','workflow_runs','integrations','audit_logs']
  loop
    execute format('create policy "workspace read %1$s" on sav_ai_crm.%1$I for select to authenticated using (sav_ai_crm.is_workspace_member(workspace_id))', t);
    execute format('create policy "workspace insert %1$s" on sav_ai_crm.%1$I for insert to authenticated with check (sav_ai_crm.is_workspace_member(workspace_id))', t);
    execute format('create policy "workspace update %1$s" on sav_ai_crm.%1$I for update to authenticated using (sav_ai_crm.is_workspace_member(workspace_id)) with check (sav_ai_crm.is_workspace_member(workspace_id))', t);
    execute format('create policy "workspace delete %1$s" on sav_ai_crm.%1$I for delete to authenticated using (sav_ai_crm.is_workspace_member(workspace_id))', t);
  end loop;
end $$;

grant select, insert, update, delete on all tables in schema sav_ai_crm to authenticated;
grant usage, select on all sequences in schema sav_ai_crm to authenticated;

alter default privileges in schema sav_ai_crm grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema sav_ai_crm grant usage, select on sequences to authenticated;

comment on schema sav_ai_crm is 'Isolated SAVRDH Intelligence Workforce CRM namespace. Designed for later migration to a dedicated Supabase project.';
