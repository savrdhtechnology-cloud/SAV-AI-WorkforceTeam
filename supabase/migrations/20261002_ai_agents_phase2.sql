-- SAVRDH Intelligence Workforce - Phase 2 AI Agents
-- PREPARED ONLY. DO NOT APPLY TO PRODUCTION AUTOMATICALLY.
-- Requires the Tasks/Follow-up migration to be applied first in staging.

begin;

-- ---------------------------------------------------------------------------
-- Agent registry extension
-- ---------------------------------------------------------------------------
alter table sav_ai_crm.ai_agents
  add column if not exists display_name text,
  add column if not exists avatar_icon text,
  add column if not exists allowed_actions text[] not null default '{}',
  add column if not exists knowledge_scopes text[] not null default '{}',
  add column if not exists workflow_access text[] not null default '{}',
  add column if not exists task_permissions text[] not null default '{}',
  add column if not exists escalation_rules jsonb not null default '{}'::jsonb,
  add column if not exists working_hours jsonb not null default '{}'::jsonb,
  add column if not exists daily_limits jsonb not null default '{}'::jsonb,
  add column if not exists confidence_threshold numeric(5,4) not null default 0.7000;

alter table sav_ai_crm.ai_agents drop constraint if exists ai_agents_status_check;
alter table sav_ai_crm.ai_agents add constraint ai_agents_status_check
  check (status in ('active','paused','disabled','error'));

update sav_ai_crm.ai_agents
set display_name=coalesce(display_name,name)
where display_name is null;

alter table sav_ai_crm.ai_agents alter column display_name set not null;

-- ---------------------------------------------------------------------------
-- Capability / access tables
-- ---------------------------------------------------------------------------
create table if not exists sav_ai_crm.ai_agent_capabilities (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
  agent_id uuid not null references sav_ai_crm.ai_agents(id) on delete cascade,
  capability text not null,
  risk_level text not null check (risk_level in ('low','medium','high','critical')),
  approval_required boolean not null default false,
  is_enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(agent_id,capability)
);

create table if not exists sav_ai_crm.ai_agent_knowledge (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
  agent_id uuid not null references sav_ai_crm.ai_agents(id) on delete cascade,
  knowledge_scope text not null,
  access_level text not null default 'read' check (access_level in ('read','none')),
  created_at timestamptz not null default now(),
  unique(agent_id,knowledge_scope)
);

create table if not exists sav_ai_crm.ai_agent_workflows (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
  agent_id uuid not null references sav_ai_crm.ai_agents(id) on delete cascade,
  workflow_id uuid references sav_ai_crm.workflows(id) on delete cascade,
  workflow_key text,
  can_execute boolean not null default false,
  created_at timestamptz not null default now(),
  check (workflow_id is not null or workflow_key is not null)
);

create table if not exists sav_ai_crm.ai_agent_executions (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
  agent_id uuid not null references sav_ai_crm.ai_agents(id) on delete cascade,
  requested_by uuid references sav_ai_crm.members(id) on delete set null,
  command text not null,
  input jsonb not null default '{}'::jsonb,
  planned_action jsonb,
  approval_status text check (approval_status in ('not_required','pending','approved','rejected')),
  execution_status text not null default 'queued'
    check (execution_status in ('queued','running','waiting_approval','completed','failed','cancelled')),
  output jsonb,
  error text,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists sav_ai_crm.ai_agent_actions (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
  agent_id uuid not null references sav_ai_crm.ai_agents(id) on delete cascade,
  execution_id uuid references sav_ai_crm.ai_agent_executions(id) on delete set null,
  requested_by uuid references sav_ai_crm.members(id) on delete set null,
  action text not null,
  target_type text not null,
  target_id uuid,
  payload jsonb not null default '{}'::jsonb,
  risk_level text not null check (risk_level in ('low','medium','high','critical')),
  approval_required boolean not null default false,
  status text not null default 'pending'
    check (status in ('pending','waiting_approval','approved','rejected','executing','completed','failed','cancelled')),
  result jsonb,
  error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz
);

create table if not exists sav_ai_crm.ai_agent_approvals (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
  action_id uuid not null references sav_ai_crm.ai_agent_actions(id) on delete cascade,
  requested_by uuid references sav_ai_crm.members(id) on delete set null,
  reviewed_by uuid references sav_ai_crm.members(id) on delete set null,
  status text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  reason text,
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz,
  unique(action_id)
);

create table if not exists sav_ai_crm.ai_agent_escalations (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
  agent_id uuid not null references sav_ai_crm.ai_agents(id) on delete cascade,
  execution_id uuid references sav_ai_crm.ai_agent_executions(id) on delete set null,
  lead_id uuid references sav_ai_crm.leads(id) on delete cascade,
  conversation_id uuid references sav_ai_crm.conversations(id) on delete cascade,
  task_id uuid references sav_ai_crm.tasks(id) on delete cascade,
  reason text not null check (reason in (
    'LOW_CONFIDENCE','CUSTOMER_REQUESTED_HUMAN','SENSITIVE_REQUEST','HIGH_VALUE_LEAD',
    'FINANCIAL_APPROVAL','COMPLAINT','FAILED_ACTION','REPEATED_FOLLOWUP_FAILURE'
  )),
  status text not null default 'open'
    check (status in ('open','assigned','in_progress','resolved','cancelled')),
  assigned_to uuid references sav_ai_crm.members(id) on delete set null,
  details text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolved_at timestamptz
);

create index if not exists ai_agent_capabilities_workspace_agent_idx on sav_ai_crm.ai_agent_capabilities(workspace_id,agent_id);
create index if not exists ai_agent_executions_workspace_agent_idx on sav_ai_crm.ai_agent_executions(workspace_id,agent_id,created_at desc);
create index if not exists ai_agent_executions_status_idx on sav_ai_crm.ai_agent_executions(workspace_id,execution_status);
create index if not exists ai_agent_actions_workspace_agent_idx on sav_ai_crm.ai_agent_actions(workspace_id,agent_id,created_at desc);
create index if not exists ai_agent_actions_status_idx on sav_ai_crm.ai_agent_actions(workspace_id,status,risk_level);
create index if not exists ai_agent_approvals_status_idx on sav_ai_crm.ai_agent_approvals(workspace_id,status,requested_at);
create index if not exists ai_agent_escalations_status_idx on sav_ai_crm.ai_agent_escalations(workspace_id,status,created_at desc);

-- ---------------------------------------------------------------------------
-- Shared auth helpers
-- ---------------------------------------------------------------------------
create or replace function sav_ai_crm.agent_current_member()
returns sav_ai_crm.members
language sql stable security definer
set search_path=public,sav_ai_crm
as $$
  select m from sav_ai_crm.members m
  where m.user_id=auth.uid() and m.is_active=true
  order by m.created_at limit 1;
$$;

create or replace function sav_ai_crm.agent_is_admin(p_role text)
returns boolean language sql immutable
as $$ select p_role in ('owner','admin'); $$;

create or replace function sav_ai_crm.agent_can_manage(p_role text)
returns boolean language sql immutable
as $$ select p_role in ('owner','admin','manager'); $$;

revoke all on function sav_ai_crm.agent_current_member() from public,anon;
grant execute on function sav_ai_crm.agent_current_member() to authenticated;

-- ---------------------------------------------------------------------------
-- RLS: readable within workspace; writes through RPCs / privileged roles only
-- ---------------------------------------------------------------------------
alter table sav_ai_crm.ai_agent_capabilities enable row level security;
alter table sav_ai_crm.ai_agent_knowledge enable row level security;
alter table sav_ai_crm.ai_agent_workflows enable row level security;
alter table sav_ai_crm.ai_agent_executions enable row level security;
alter table sav_ai_crm.ai_agent_actions enable row level security;
alter table sav_ai_crm.ai_agent_approvals enable row level security;
alter table sav_ai_crm.ai_agent_escalations enable row level security;

drop policy if exists "workspace insert ai_agents" on sav_ai_crm.ai_agents;
drop policy if exists "workspace update ai_agents" on sav_ai_crm.ai_agents;
drop policy if exists "workspace delete ai_agents" on sav_ai_crm.ai_agents;

create policy "agent admins insert ai_agents" on sav_ai_crm.ai_agents
for insert to authenticated
with check (
  exists(select 1 from sav_ai_crm.members m where m.user_id=auth.uid() and m.workspace_id=ai_agents.workspace_id and m.is_active=true and m.role in ('owner','admin'))
);
create policy "agent managers update ai_agents" on sav_ai_crm.ai_agents
for update to authenticated
using (
  exists(select 1 from sav_ai_crm.members m where m.user_id=auth.uid() and m.workspace_id=ai_agents.workspace_id and m.is_active=true and m.role in ('owner','admin','manager'))
)
with check (
  exists(select 1 from sav_ai_crm.members m where m.user_id=auth.uid() and m.workspace_id=ai_agents.workspace_id and m.is_active=true and m.role in ('owner','admin','manager'))
);
create policy "agent admins delete ai_agents" on sav_ai_crm.ai_agents
for delete to authenticated
using (
  exists(select 1 from sav_ai_crm.members m where m.user_id=auth.uid() and m.workspace_id=ai_agents.workspace_id and m.is_active=true and m.role in ('owner','admin'))
);

do $$
declare t text;
begin
  foreach t in array array['ai_agent_capabilities','ai_agent_knowledge','ai_agent_workflows','ai_agent_executions','ai_agent_actions','ai_agent_approvals','ai_agent_escalations']
  loop
    execute format('drop policy if exists "agent workspace read %1$s" on sav_ai_crm.%1$I',t);
    execute format('create policy "agent workspace read %1$s" on sav_ai_crm.%1$I for select to authenticated using (sav_ai_crm.is_workspace_member(workspace_id))',t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Seed canonical eight-agent registry for every existing workspace.
-- Existing rows are preserved and canonical rows are updated safely.
-- ---------------------------------------------------------------------------
with definitions(slug,name,display_name,role_name,description,channels,allowed_actions,knowledge_scopes,task_permissions,confidence_threshold) as (
values
('sav-sales','SAV-Sales','SAV-Sales','Sales & Telecalling Executive',
 'Handles new leads, initial qualification, product/service information, follow-ups, sales tasks, summaries and escalation.',
 array['crm','voice','whatsapp','sms','email']::text[],
 array['READ_LEAD','UPDATE_LEAD','CREATE_TASK','CREATE_FOLLOWUP','READ_CONVERSATION','CREATE_NOTE','CREATE_ESCALATION','READ_KNOWLEDGE','SUMMARIZE_CONVERSATION']::text[],
 array['sales']::text[],array['create','update_own']::text[],0.72::numeric),
('sav-bde','SAV-BDE','SAV-BDE','Business Development Executive',
 'Handles qualified leads, requirement collection, business information, application preparation, document coordination and escalation.',
 array['crm','voice','whatsapp','sms','email']::text[],
 array['READ_LEAD','UPDATE_LEAD','CREATE_TASK','CREATE_FOLLOWUP','READ_CONVERSATION','CREATE_NOTE','CREATE_ESCALATION','READ_KNOWLEDGE']::text[],
 array['sales','business-development','documents']::text[],array['create','update_own']::text[],0.74::numeric),
('sav-sales-manager','SAV-Sales-Manager','SAV-Sales-Manager','Sales Management',
 'Handles lead distribution, sales oversight, approvals, team monitoring, escalations and sales analytics.',
 array['crm','email']::text[],
 array['READ_LEAD','UPDATE_LEAD','CREATE_TASK','UPDATE_TASK','CREATE_FOLLOWUP','CREATE_NOTE','CREATE_ESCALATION','ASSIGN_TASK','READ_KNOWLEDGE']::text[],
 array['sales','management']::text[],array['create','update','assign']::text[],0.78::numeric),
('sav-finance','SAV-Finance','SAV-Finance','Finance Manager',
 'Coordinates finance workflows, payment tasks, financial document requests and finance escalation. Cannot approve financial transactions automatically.',
 array['crm','whatsapp','sms','email']::text[],
 array['READ_LEAD','CREATE_TASK','CREATE_FOLLOWUP','CREATE_NOTE','CREATE_ESCALATION','READ_KNOWLEDGE','FINANCIAL_ACTION']::text[],
 array['finance']::text[],array['create','update_own']::text[],0.82::numeric),
('sav-credit','SAV-Credit','SAV-Credit','Credit & Risk Executive',
 'Collects credit information, creates credit tasks, prepares analysis and escalates decisions. Does not make lending decisions.',
 array['crm','whatsapp','sms','email']::text[],
 array['READ_LEAD','CREATE_TASK','CREATE_FOLLOWUP','CREATE_NOTE','CREATE_ESCALATION','READ_KNOWLEDGE']::text[],
 array['credit']::text[],array['create','update_own']::text[],0.82::numeric),
('sav-document','SAV-Document','SAV-Document','Documentation Executive',
 'Manages document checklists, requests, missing-document follow-ups and document status tracking.',
 array['crm','whatsapp','sms','email']::text[],
 array['READ_LEAD','CREATE_TASK','CREATE_FOLLOWUP','CREATE_NOTE','CREATE_ESCALATION','READ_KNOWLEDGE']::text[],
 array['documents']::text[],array['create','update_own']::text[],0.76::numeric),
('sav-followup','SAV-Followup','SAV-Followup','Customer Follow-up Executive',
 'Schedules follow-ups, creates reminder tasks, manages follow-up sequences and escalates non-response.',
 array['crm','voice','whatsapp','sms','email']::text[],
 array['READ_LEAD','CREATE_TASK','UPDATE_TASK','CREATE_FOLLOWUP','READ_CONVERSATION','CREATE_NOTE','CREATE_ESCALATION']::text[],
 array['sales','support']::text[],array['create','update_own']::text[],0.73::numeric),
('sav-support','SAV-Support','SAV-Support','Customer Support Executive',
 'Handles customer support, issue classification, support task creation and human escalation.',
 array['crm','voice','whatsapp','sms','email','webchat']::text[],
 array['READ_LEAD','CREATE_TASK','READ_CONVERSATION','CREATE_NOTE','CREATE_ESCALATION','READ_KNOWLEDGE','SUMMARIZE_CONVERSATION']::text[],
 array['support']::text[],array['create','update_own']::text[],0.75::numeric)
)
insert into sav_ai_crm.ai_agents(
  workspace_id,name,slug,display_name,role_name,description,status,avatar_icon,channels,
  autonomy_level,approval_required,allowed_actions,knowledge_scopes,task_permissions,
  escalation_rules,working_hours,daily_limits,confidence_threshold,configuration
)
select w.id,d.name,d.slug,d.display_name,d.role_name,d.description,'active','Bot',d.channels,
       'assisted',true,d.allowed_actions,d.knowledge_scopes,d.task_permissions,
       jsonb_build_object('human_escalation',true),
       jsonb_build_object('timezone','Asia/Kolkata','days',jsonb_build_array(1,2,3,4,5,6),'start','09:00','end','19:00'),
       jsonb_build_object('executions',100,'external_messages',25),
       d.confidence_threshold,'{}'::jsonb
from sav_ai_crm.workspaces w cross join definitions d
on conflict(workspace_id,slug) do update set
 name=excluded.name,display_name=excluded.display_name,role_name=excluded.role_name,
 description=excluded.description,channels=excluded.channels,allowed_actions=excluded.allowed_actions,
 knowledge_scopes=excluded.knowledge_scopes,task_permissions=excluded.task_permissions,
 confidence_threshold=excluded.confidence_threshold,updated_at=now();

update sav_ai_crm.ai_agents
set status='disabled',updated_at=now()
where slug='sav-operations';

-- Canonical capabilities (sensitive capabilities are not globally granted)
with cap(agent_slug,capability,risk,approval) as (
values
('sav-sales','READ_LEAD','low',false),('sav-sales','UPDATE_LEAD','medium',false),('sav-sales','CREATE_TASK','low',false),('sav-sales','CREATE_FOLLOWUP','medium',false),('sav-sales','READ_CONVERSATION','low',false),('sav-sales','CREATE_NOTE','low',false),('sav-sales','CREATE_ESCALATION','low',false),('sav-sales','READ_KNOWLEDGE','low',false),('sav-sales','SUMMARIZE_CONVERSATION','low',false),
('sav-bde','READ_LEAD','low',false),('sav-bde','UPDATE_LEAD','medium',false),('sav-bde','CREATE_TASK','low',false),('sav-bde','CREATE_FOLLOWUP','medium',false),('sav-bde','CREATE_NOTE','low',false),('sav-bde','CREATE_ESCALATION','low',false),('sav-bde','READ_KNOWLEDGE','low',false),
('sav-sales-manager','READ_LEAD','low',false),('sav-sales-manager','UPDATE_LEAD','medium',false),('sav-sales-manager','CREATE_TASK','low',false),('sav-sales-manager','UPDATE_TASK','medium',false),('sav-sales-manager','CREATE_FOLLOWUP','medium',false),('sav-sales-manager','CREATE_NOTE','low',false),('sav-sales-manager','CREATE_ESCALATION','low',false),('sav-sales-manager','ASSIGN_TASK','medium',false),('sav-sales-manager','READ_KNOWLEDGE','low',false),
('sav-finance','READ_LEAD','low',false),('sav-finance','CREATE_TASK','low',false),('sav-finance','CREATE_FOLLOWUP','medium',false),('sav-finance','CREATE_NOTE','low',false),('sav-finance','CREATE_ESCALATION','low',false),('sav-finance','READ_KNOWLEDGE','low',false),('sav-finance','FINANCIAL_ACTION','critical',true),
('sav-credit','READ_LEAD','low',false),('sav-credit','CREATE_TASK','low',false),('sav-credit','CREATE_FOLLOWUP','medium',false),('sav-credit','CREATE_NOTE','low',false),('sav-credit','CREATE_ESCALATION','low',false),('sav-credit','READ_KNOWLEDGE','low',false),
('sav-document','READ_LEAD','low',false),('sav-document','CREATE_TASK','low',false),('sav-document','CREATE_FOLLOWUP','medium',false),('sav-document','CREATE_NOTE','low',false),('sav-document','CREATE_ESCALATION','low',false),('sav-document','READ_KNOWLEDGE','low',false),
('sav-followup','READ_LEAD','low',false),('sav-followup','CREATE_TASK','low',false),('sav-followup','UPDATE_TASK','medium',false),('sav-followup','CREATE_FOLLOWUP','medium',false),('sav-followup','READ_CONVERSATION','low',false),('sav-followup','CREATE_NOTE','low',false),('sav-followup','CREATE_ESCALATION','low',false),
('sav-support','READ_LEAD','low',false),('sav-support','CREATE_TASK','low',false),('sav-support','READ_CONVERSATION','low',false),('sav-support','CREATE_NOTE','low',false),('sav-support','CREATE_ESCALATION','low',false),('sav-support','READ_KNOWLEDGE','low',false),('sav-support','SUMMARIZE_CONVERSATION','low',false)
)
insert into sav_ai_crm.ai_agent_capabilities(workspace_id,agent_id,capability,risk_level,approval_required)
select a.workspace_id,a.id,c.capability,c.risk,c.approval
from cap c join sav_ai_crm.ai_agents a on a.slug=c.agent_slug
on conflict(agent_id,capability) do update set
 risk_level=excluded.risk_level,approval_required=excluded.approval_required,is_enabled=true,updated_at=now();

insert into sav_ai_crm.ai_agent_knowledge(workspace_id,agent_id,knowledge_scope)
select a.workspace_id,a.id,s.scope
from sav_ai_crm.ai_agents a
cross join lateral unnest(a.knowledge_scopes) s(scope)
where a.slug in ('sav-sales','sav-bde','sav-sales-manager','sav-finance','sav-credit','sav-document','sav-followup','sav-support')
on conflict(agent_id,knowledge_scope) do update set access_level='read';

-- ---------------------------------------------------------------------------
-- Registry / analytics RPCs
-- ---------------------------------------------------------------------------
create or replace function public.sav_ai_crm_agent_registry()
returns jsonb language plpgsql stable security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members;
begin
 me:=sav_ai_crm.agent_current_member();
 if me.id is null then raise exception 'CRM membership required'; end if;
 return coalesce((
   select jsonb_agg(jsonb_build_object(
     'id',a.id,'name',a.name,'slug',a.slug,'display_name',a.display_name,'role_name',a.role_name,
     'description',a.description,'status',a.status,'avatar_icon',a.avatar_icon,'channels',a.channels,
     'autonomy_level',a.autonomy_level,'approval_required',a.approval_required,
     'capabilities',coalesce((select jsonb_agg(c.capability order by c.capability) from sav_ai_crm.ai_agent_capabilities c where c.agent_id=a.id and c.is_enabled),'[]'::jsonb),
     'allowed_actions',a.allowed_actions,'knowledge_scopes',a.knowledge_scopes,'workflow_access',a.workflow_access,
     'task_permissions',a.task_permissions,'escalation_rules',a.escalation_rules,'working_hours',a.working_hours,
     'daily_limits',a.daily_limits,'confidence_threshold',a.confidence_threshold,'configuration',a.configuration,
     'created_at',a.created_at,'updated_at',a.updated_at
   ) order by a.name)
   from sav_ai_crm.ai_agents a where a.workspace_id=me.workspace_id and a.slug<>'sav-operations'
 ),'[]'::jsonb);
end $$;

create or replace function public.sav_ai_crm_agent_detail(p_agent_id uuid)
returns jsonb language plpgsql stable security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; result jsonb;
begin
 me:=sav_ai_crm.agent_current_member();
 if me.id is null then raise exception 'CRM membership required'; end if;
 select jsonb_build_object(
   'agent',to_jsonb(a),
   'capabilities',coalesce((select jsonb_agg(to_jsonb(c) order by c.capability) from sav_ai_crm.ai_agent_capabilities c where c.agent_id=a.id),'[]'::jsonb),
   'knowledge',coalesce((select jsonb_agg(to_jsonb(k) order by k.knowledge_scope) from sav_ai_crm.ai_agent_knowledge k where k.agent_id=a.id),'[]'::jsonb),
   'workflows',coalesce((select jsonb_agg(to_jsonb(w)) from sav_ai_crm.ai_agent_workflows w where w.agent_id=a.id),'[]'::jsonb),
   'executions',coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at desc) from (select * from sav_ai_crm.ai_agent_executions where agent_id=a.id order by created_at desc limit 50) e),'[]'::jsonb),
   'actions',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select * from sav_ai_crm.ai_agent_actions where agent_id=a.id order by created_at desc limit 50) x),'[]'::jsonb),
   'escalations',coalesce((select jsonb_agg(to_jsonb(s) order by s.created_at desc) from (select * from sav_ai_crm.ai_agent_escalations where agent_id=a.id order by created_at desc limit 50) s),'[]'::jsonb),
   'permissions',jsonb_build_object('manage',sav_ai_crm.agent_can_manage(me.role),'admin',sav_ai_crm.agent_is_admin(me.role))
 ) into result
 from sav_ai_crm.ai_agents a where a.id=p_agent_id and a.workspace_id=me.workspace_id;
 if result is null then raise exception 'Agent not found'; end if;
 return result;
end $$;

create or replace function public.sav_ai_crm_agent_metrics()
returns jsonb language plpgsql stable security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members;
begin
 me:=sav_ai_crm.agent_current_member();
 if me.id is null then raise exception 'CRM membership required'; end if;
 return jsonb_build_object(
   'active_agents',(select count(*) from sav_ai_crm.ai_agents where workspace_id=me.workspace_id and status='active' and slug<>'sav-operations'),
   'executions',(select count(*) from sav_ai_crm.ai_agent_executions where workspace_id=me.workspace_id),
   'successful_executions',(select count(*) from sav_ai_crm.ai_agent_executions where workspace_id=me.workspace_id and execution_status='completed'),
   'failed_executions',(select count(*) from sav_ai_crm.ai_agent_executions where workspace_id=me.workspace_id and execution_status='failed'),
   'pending_approvals',(select count(*) from sav_ai_crm.ai_agent_approvals where workspace_id=me.workspace_id and status='pending'),
   'escalations',(select count(*) from sav_ai_crm.ai_agent_escalations where workspace_id=me.workspace_id and status in ('open','assigned','in_progress')),
   'tasks_created',(select count(*) from sav_ai_crm.activities where workspace_id=me.workspace_id and activity_type='agent_task_created'),
   'followups_created',(select count(*) from sav_ai_crm.activities where workspace_id=me.workspace_id and activity_type='agent_followup_created')
 );
end $$;

-- ---------------------------------------------------------------------------
-- Persistent admin management
-- ---------------------------------------------------------------------------
create or replace function public.sav_ai_crm_update_agent(
 p_agent_id uuid,p_display_name text,p_description text,p_channels text[],p_confidence_threshold numeric,
 p_working_hours jsonb,p_daily_limits jsonb,p_escalation_rules jsonb
) returns void language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members;
begin
 me:=sav_ai_crm.agent_current_member();
 if me.id is null or not sav_ai_crm.agent_can_manage(me.role) then raise exception 'Agent management not permitted'; end if;
 if p_confidence_threshold<0 or p_confidence_threshold>1 then raise exception 'Confidence threshold must be between 0 and 1'; end if;
 update sav_ai_crm.ai_agents set
   display_name=trim(p_display_name),description=nullif(trim(p_description),''),
   channels=coalesce(p_channels,'{}'),confidence_threshold=p_confidence_threshold,
   working_hours=coalesce(p_working_hours,'{}'),daily_limits=coalesce(p_daily_limits,'{}'),
   escalation_rules=coalesce(p_escalation_rules,'{}'),updated_at=now()
 where id=p_agent_id and workspace_id=me.workspace_id;
 if not found then raise exception 'Agent not found'; end if;
 insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id,metadata)
 values(me.workspace_id,auth.uid(),'agent.update','ai_agent',p_agent_id,'{}');
end $$;

create or replace function public.sav_ai_crm_set_agent_status(p_agent_id uuid,p_status text)
returns void language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; old_status text;
begin
 me:=sav_ai_crm.agent_current_member();
 if me.id is null or not sav_ai_crm.agent_can_manage(me.role) then raise exception 'Agent management not permitted'; end if;
 if p_status not in ('active','paused','disabled','error') then raise exception 'Invalid agent status'; end if;
 select status into old_status from sav_ai_crm.ai_agents where id=p_agent_id and workspace_id=me.workspace_id;
 if old_status is null then raise exception 'Agent not found'; end if;
 update sav_ai_crm.ai_agents set status=p_status,updated_at=now() where id=p_agent_id;
 insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id,metadata)
 values(me.workspace_id,auth.uid(),'agent.status','ai_agent',p_agent_id,jsonb_build_object('from',old_status,'to',p_status));
end $$;

-- ---------------------------------------------------------------------------
-- Controlled action request engine
-- ---------------------------------------------------------------------------
create or replace function public.sav_ai_crm_request_agent_action(
 p_agent_id uuid,p_action text,p_target_type text,p_target_id uuid default null,p_payload jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare
 me sav_ai_crm.members; agent sav_ai_crm.ai_agents; cap sav_ai_crm.ai_agent_capabilities;
 action_id uuid; approval_id uuid; needs_approval boolean;
begin
 me:=sav_ai_crm.agent_current_member();
 if me.id is null then raise exception 'CRM membership required'; end if;
 select * into agent from sav_ai_crm.ai_agents where id=p_agent_id and workspace_id=me.workspace_id;
 if agent.id is null then raise exception 'Agent not found'; end if;
 if agent.status<>'active' then raise exception 'Agent is not active'; end if;

 select * into cap from sav_ai_crm.ai_agent_capabilities
 where agent_id=agent.id and capability=p_action and is_enabled=true;
 if cap.id is null then raise exception 'Agent capability denied'; end if;

 if p_target_type='lead' and p_target_id is not null and not exists(select 1 from sav_ai_crm.leads where id=p_target_id and workspace_id=me.workspace_id) then
   raise exception 'Lead is outside this workspace';
 elsif p_target_type='task' and p_target_id is not null and not exists(select 1 from sav_ai_crm.tasks where id=p_target_id and workspace_id=me.workspace_id) then
   raise exception 'Task is outside this workspace';
 elsif p_target_type='conversation' and p_target_id is not null and not exists(select 1 from sav_ai_crm.conversations where id=p_target_id and workspace_id=me.workspace_id) then
   raise exception 'Conversation is outside this workspace';
 end if;

 needs_approval:=cap.approval_required or cap.risk_level in ('high','critical');

 insert into sav_ai_crm.ai_agent_actions(
   workspace_id,agent_id,requested_by,action,target_type,target_id,payload,risk_level,approval_required,status
 ) values(
   me.workspace_id,agent.id,me.id,p_action,p_target_type,p_target_id,coalesce(p_payload,'{}'),cap.risk_level,needs_approval,
   case when needs_approval then 'waiting_approval' else 'approved' end
 ) returning id into action_id;

 if needs_approval then
   insert into sav_ai_crm.ai_agent_approvals(workspace_id,action_id,requested_by,status)
   values(me.workspace_id,action_id,me.id,'pending') returning id into approval_id;
 end if;

 insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id,metadata)
 values(me.workspace_id,auth.uid(),'agent.action.request','ai_agent_action',action_id,
   jsonb_build_object('agent_id',agent.id,'capability',p_action,'risk',cap.risk_level,'approval_required',needs_approval));

 return jsonb_build_object('action_id',action_id,'risk_level',cap.risk_level,'approval_required',needs_approval,'approval_id',approval_id,
   'status',case when needs_approval then 'waiting_approval' else 'approved' end);
end $$;

create or replace function public.sav_ai_crm_review_agent_action(p_action_id uuid,p_decision text,p_reason text default null)
returns void language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; a sav_ai_crm.ai_agent_actions; approval sav_ai_crm.ai_agent_approvals;
begin
 me:=sav_ai_crm.agent_current_member();
 if me.id is null or not sav_ai_crm.agent_can_manage(me.role) then raise exception 'Approval review not permitted'; end if;
 if p_decision not in ('approved','rejected') then raise exception 'Invalid approval decision'; end if;
 select * into a from sav_ai_crm.ai_agent_actions where id=p_action_id and workspace_id=me.workspace_id;
 if a.id is null or a.status<>'waiting_approval' then raise exception 'Pending action not found'; end if;
 select * into approval from sav_ai_crm.ai_agent_approvals where action_id=a.id and workspace_id=me.workspace_id and status='pending';
 if approval.id is null then raise exception 'Pending approval not found'; end if;
 update sav_ai_crm.ai_agent_approvals set status=p_decision,reviewed_by=me.id,reason=p_reason,reviewed_at=now() where id=approval.id;
 update sav_ai_crm.ai_agent_actions set status=p_decision,updated_at=now() where id=a.id;
 insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id,metadata)
 values(me.workspace_id,auth.uid(),'agent.action.'||p_decision,'ai_agent_action',a.id,jsonb_build_object('reason',p_reason));
end $$;

-- Low/medium controlled execution for implemented internal actions only.
create or replace function public.sav_ai_crm_execute_agent_action(p_action_id uuid)
returns jsonb language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; a sav_ai_crm.ai_agent_actions; agent sav_ai_crm.ai_agents; task_id uuid; lead_rec sav_ai_crm.leads;
begin
 me:=sav_ai_crm.agent_current_member();
 if me.id is null then raise exception 'CRM membership required'; end if;
 select * into a from sav_ai_crm.ai_agent_actions where id=p_action_id and workspace_id=me.workspace_id for update;
 if a.id is null then raise exception 'Action not found'; end if;
 if a.approval_required and a.status<>'approved' then raise exception 'Human approval required'; end if;
 if a.status not in ('approved','pending') then raise exception 'Action is not executable'; end if;
 select * into agent from sav_ai_crm.ai_agents where id=a.agent_id and workspace_id=me.workspace_id;
 if agent.status<>'active' then raise exception 'Agent is not active'; end if;

 update sav_ai_crm.ai_agent_actions set status='executing',updated_at=now() where id=a.id;

 if a.action in ('CREATE_TASK','CREATE_FOLLOWUP') then
   if a.target_type<>'lead' or a.target_id is null then raise exception 'Task creation requires a lead target'; end if;
   select * into lead_rec from sav_ai_crm.leads where id=a.target_id and workspace_id=me.workspace_id;
   if lead_rec.id is null then raise exception 'Lead not found'; end if;
   insert into sav_ai_crm.tasks(
     workspace_id,lead_id,title,description,task_type,followup_type,status,priority,due_at,reminder_at,
     assigned_agent_id,notes
   ) values(
     me.workspace_id,lead_rec.id,
     coalesce(nullif(a.payload->>'title',''),agent.display_name||' follow-up'),
     nullif(a.payload->>'description',''),'followup',
     case when a.action='CREATE_FOLLOWUP' then coalesce(nullif(a.payload->>'followup_type',''),'general') else 'general' end,
     'pending',coalesce(nullif(a.payload->>'priority',''),'medium'),
     nullif(a.payload->>'due_at','')::timestamptz,nullif(a.payload->>'reminder_at','')::timestamptz,
     agent.id,
     'Created by: '||agent.display_name
   ) returning id into task_id;
   insert into sav_ai_crm.activities(workspace_id,lead_id,task_id,activity_type,title,description,metadata)
   values(me.workspace_id,lead_rec.id,task_id,
     case when a.action='CREATE_FOLLOWUP' then 'agent_followup_created' else 'agent_task_created' end,
     agent.display_name||' created task',coalesce(a.payload->>'title','Follow-up task'),
     jsonb_build_object('agent_id',agent.id,'agent_name',agent.display_name,'action_id',a.id));
 elsif a.action='CREATE_NOTE' then
   if a.target_type<>'lead' or a.target_id is null then raise exception 'Note requires a lead target'; end if;
   update sav_ai_crm.leads set notes=concat_ws(E'\n',notes,'['||agent.display_name||'] '||coalesce(a.payload->>'note','')),
     updated_at=now() where id=a.target_id and workspace_id=me.workspace_id;
   if not found then raise exception 'Lead not found'; end if;
   insert into sav_ai_crm.activities(workspace_id,lead_id,activity_type,title,description,metadata)
   values(me.workspace_id,a.target_id,'agent_note_created',agent.display_name||' added note',a.payload->>'note',
     jsonb_build_object('agent_id',agent.id,'action_id',a.id));
 elsif a.action='CREATE_ESCALATION' then
   insert into sav_ai_crm.ai_agent_escalations(workspace_id,agent_id,lead_id,conversation_id,task_id,reason,details)
   values(me.workspace_id,agent.id,
     case when a.target_type='lead' then a.target_id else null end,
     case when a.target_type='conversation' then a.target_id else null end,
     case when a.target_type='task' then a.target_id else null end,
     coalesce(nullif(a.payload->>'reason',''),'FAILED_ACTION'),
     a.payload->>'details');
 else
   update sav_ai_crm.ai_agent_actions set status='failed',error='ACTION_ADAPTER_NOT_IMPLEMENTED',updated_at=now(),completed_at=now() where id=a.id;
   raise exception 'Action adapter not implemented';
 end if;

 update sav_ai_crm.ai_agent_actions set status='completed',
   result=jsonb_build_object('task_id',task_id),updated_at=now(),completed_at=now() where id=a.id;

 insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id,metadata)
 values(me.workspace_id,auth.uid(),'agent.action.completed','ai_agent_action',a.id,jsonb_build_object('agent_id',agent.id,'capability',a.action,'task_id',task_id));

 return jsonb_build_object('action_id',a.id,'status','completed','task_id',task_id);
end $$;

-- Execution records used by provider/test console.
create or replace function public.sav_ai_crm_create_agent_execution(p_agent_id uuid,p_command text,p_input jsonb default '{}'::jsonb)
returns uuid language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; agent sav_ai_crm.ai_agents; eid uuid;
begin
 me:=sav_ai_crm.agent_current_member();
 if me.id is null then raise exception 'CRM membership required'; end if;
 select * into agent from sav_ai_crm.ai_agents where id=p_agent_id and workspace_id=me.workspace_id;
 if agent.id is null then raise exception 'Agent not found'; end if;
 if agent.status<>'active' then raise exception 'Agent is not active'; end if;
 insert into sav_ai_crm.ai_agent_executions(workspace_id,agent_id,requested_by,command,input,execution_status)
 values(me.workspace_id,agent.id,me.id,trim(p_command),coalesce(p_input,'{}'),'queued') returning id into eid;
 return eid;
end $$;

create or replace function public.sav_ai_crm_fail_agent_execution(p_execution_id uuid,p_error text,p_output jsonb default null)
returns void language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members;
begin
 me:=sav_ai_crm.agent_current_member();
 if me.id is null then raise exception 'CRM membership required'; end if;
 update sav_ai_crm.ai_agent_executions set execution_status='failed',error=p_error,output=p_output,
   started_at=coalesce(started_at,now()),completed_at=now()
 where id=p_execution_id and workspace_id=me.workspace_id;
 if not found then raise exception 'Execution not found'; end if;
end $$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
revoke all on function public.sav_ai_crm_agent_registry() from public,anon;
revoke all on function public.sav_ai_crm_agent_detail(uuid) from public,anon;
revoke all on function public.sav_ai_crm_agent_metrics() from public,anon;
revoke all on function public.sav_ai_crm_update_agent(uuid,text,text,text[],numeric,jsonb,jsonb,jsonb) from public,anon;
revoke all on function public.sav_ai_crm_set_agent_status(uuid,text) from public,anon;
revoke all on function public.sav_ai_crm_request_agent_action(uuid,text,text,uuid,jsonb) from public,anon;
revoke all on function public.sav_ai_crm_review_agent_action(uuid,text,text) from public,anon;
revoke all on function public.sav_ai_crm_execute_agent_action(uuid) from public,anon;
revoke all on function public.sav_ai_crm_create_agent_execution(uuid,text,jsonb) from public,anon;
revoke all on function public.sav_ai_crm_fail_agent_execution(uuid,text,jsonb) from public,anon;

grant execute on function public.sav_ai_crm_agent_registry() to authenticated;
grant execute on function public.sav_ai_crm_agent_detail(uuid) to authenticated;
grant execute on function public.sav_ai_crm_agent_metrics() to authenticated;
grant execute on function public.sav_ai_crm_update_agent(uuid,text,text,text[],numeric,jsonb,jsonb,jsonb) to authenticated;
grant execute on function public.sav_ai_crm_set_agent_status(uuid,text) to authenticated;
grant execute on function public.sav_ai_crm_request_agent_action(uuid,text,text,uuid,jsonb) to authenticated;
grant execute on function public.sav_ai_crm_review_agent_action(uuid,text,text) to authenticated;
grant execute on function public.sav_ai_crm_execute_agent_action(uuid) to authenticated;
grant execute on function public.sav_ai_crm_create_agent_execution(uuid,text,jsonb) to authenticated;
grant execute on function public.sav_ai_crm_fail_agent_execution(uuid,text,jsonb) to authenticated;

commit;
