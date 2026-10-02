-- SAVRDH Intelligence Workforce - Phase 3 Workflow Engine
-- PREPARED ONLY. DO NOT APPLY TO PRODUCTION AUTOMATICALLY.
-- Apply after Tasks and Phase 2 AI Agents migrations in a safe staging environment.

begin;

-- Registry extension ---------------------------------------------------------
alter table sav_ai_crm.workflows
  add column if not exists description text,
  add column if not exists version integer not null default 1,
  add column if not exists created_by uuid references sav_ai_crm.members(id) on delete set null,
  add column if not exists updated_by uuid references sav_ai_crm.members(id) on delete set null,
  add column if not exists enabled_at timestamptz,
  add column if not exists disabled_at timestamptz,
  add column if not exists archived_at timestamptz;

alter table sav_ai_crm.workflows drop constraint if exists workflows_status_check;
alter table sav_ai_crm.workflows add constraint workflows_status_check
  check (status in ('draft','active','paused','disabled','error','archived'));

create table if not exists sav_ai_crm.workflow_versions (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
  workflow_id uuid not null references sav_ai_crm.workflows(id) on delete cascade,
  version integer not null,
  definition jsonb not null default '{}'::jsonb,
  created_by uuid references sav_ai_crm.members(id) on delete set null,
  created_at timestamptz not null default now(),
  unique(workflow_id,version)
);

create table if not exists sav_ai_crm.workflow_nodes (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
  workflow_id uuid not null references sav_ai_crm.workflows(id) on delete cascade,
  workflow_version integer not null,
  node_key text not null,
  node_type text not null check (node_type in (
    'TRIGGER','CONDITION','AI_AGENT','ACTION','TASK','FOLLOW_UP','WAIT',
    'HUMAN_APPROVAL','ESCALATION','NOTIFICATION','END'
  )),
  label text not null,
  position jsonb not null default '{"x":0,"y":0}'::jsonb,
  config jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(workflow_id,workflow_version,node_key)
);

create table if not exists sav_ai_crm.workflow_edges (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
  workflow_id uuid not null references sav_ai_crm.workflows(id) on delete cascade,
  workflow_version integer not null,
  edge_key text not null,
  source_key text not null,
  target_key text not null,
  branch text,
  condition jsonb,
  created_at timestamptz not null default now(),
  unique(workflow_id,workflow_version,edge_key)
);

create table if not exists sav_ai_crm.workflow_triggers (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
  workflow_id uuid not null references sav_ai_crm.workflows(id) on delete cascade,
  event text not null check (event in (
    'NEW_LEAD','LEAD_STATUS_CHANGED','PIPELINE_STAGE_CHANGED','TASK_CREATED','TASK_COMPLETED',
    'FOLLOWUP_DUE','REMINDER_DUE','CONVERSATION_RECEIVED','AI_ESCALATION','MANUAL_TRIGGER','SCHEDULED_TRIGGER'
  )),
  conditions jsonb not null default '[]'::jsonb,
  enabled boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists sav_ai_crm.workflow_executions (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
  workflow_id uuid not null references sav_ai_crm.workflows(id) on delete cascade,
  workflow_version integer not null,
  trigger text not null,
  context jsonb not null default '{}'::jsonb,
  current_node_id uuid references sav_ai_crm.workflow_nodes(id) on delete set null,
  execution_state text not null default 'queued'
    check (execution_state in ('queued','running','waiting','waiting_approval','completed','failed','cancelled')),
  scheduled_for timestamptz,
  retry_count integer not null default 0 check (retry_count>=0),
  max_retries integer not null default 3 check (max_retries between 0 and 10),
  retry_delay_seconds integer not null default 60 check (retry_delay_seconds between 0 and 86400),
  depth integer not null default 0 check (depth>=0),
  max_depth integer not null default 50 check (max_depth between 1 and 100),
  idempotency_key text not null,
  started_at timestamptz,
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  error text,
  created_at timestamptz not null default now(),
  unique(workspace_id,idempotency_key)
);

create table if not exists sav_ai_crm.workflow_node_executions (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
  execution_id uuid not null references sav_ai_crm.workflow_executions(id) on delete cascade,
  node_id uuid not null references sav_ai_crm.workflow_nodes(id) on delete cascade,
  node_execution_id text not null,
  attempt integer not null default 0,
  status text not null default 'running'
    check (status in ('queued','running','waiting','waiting_approval','completed','failed','cancelled','retrying')),
  input jsonb not null default '{}'::jsonb,
  output jsonb,
  risk_level text check (risk_level in ('low','medium','high','critical')),
  approval_required boolean not null default false,
  retry_count integer not null default 0,
  max_retries integer not null default 3,
  retry_delay_seconds integer not null default 60,
  last_error text,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  unique(execution_id,node_execution_id,attempt)
);

create table if not exists sav_ai_crm.workflow_approvals (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
  workflow_id uuid not null references sav_ai_crm.workflows(id) on delete cascade,
  execution_id uuid not null references sav_ai_crm.workflow_executions(id) on delete cascade,
  node_id uuid not null references sav_ai_crm.workflow_nodes(id) on delete cascade,
  approver_role text,
  approver_user_id uuid references sav_ai_crm.members(id) on delete set null,
  requested_by uuid references sav_ai_crm.members(id) on delete set null,
  reviewed_by uuid references sav_ai_crm.members(id) on delete set null,
  timeout_at timestamptz,
  approval_reason text,
  risk_level text not null default 'medium' check (risk_level in ('low','medium','high','critical')),
  status text not null default 'pending' check (status in ('pending','approved','rejected','expired','cancelled')),
  metadata jsonb not null default '{}'::jsonb,
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz
);

create table if not exists sav_ai_crm.workflow_templates (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
  template_key text not null,
  name text not null,
  description text,
  trigger_type text not null,
  definition jsonb not null,
  is_system boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(workspace_id,template_key)
);

alter table sav_ai_crm.ai_agent_escalations
  add column if not exists workflow_id uuid references sav_ai_crm.workflows(id) on delete set null,
  add column if not exists workflow_execution_id uuid references sav_ai_crm.workflow_executions(id) on delete set null;

create index if not exists workflows_workspace_status_idx on sav_ai_crm.workflows(workspace_id,status,updated_at desc);
create index if not exists workflow_nodes_current_idx on sav_ai_crm.workflow_nodes(workflow_id,workflow_version,node_type);
create index if not exists workflow_edges_current_idx on sav_ai_crm.workflow_edges(workflow_id,workflow_version,source_key);
create index if not exists workflow_triggers_event_idx on sav_ai_crm.workflow_triggers(workspace_id,event,enabled);
create index if not exists workflow_executions_status_idx on sav_ai_crm.workflow_executions(workspace_id,execution_state,updated_at desc);
create index if not exists workflow_executions_schedule_idx on sav_ai_crm.workflow_executions(workspace_id,scheduled_for) where execution_state='waiting';
create index if not exists workflow_node_exec_timeline_idx on sav_ai_crm.workflow_node_executions(execution_id,started_at);
create index if not exists workflow_approvals_pending_idx on sav_ai_crm.workflow_approvals(workspace_id,status,requested_at);

-- Auth helpers ---------------------------------------------------------------
create or replace function sav_ai_crm.workflow_current_member()
returns sav_ai_crm.members
language sql stable security definer
set search_path=public,sav_ai_crm
as $$
  select m from sav_ai_crm.members m
  where m.user_id=auth.uid() and m.is_active=true
  order by m.created_at limit 1;
$$;

create or replace function sav_ai_crm.workflow_can_manage(p_role text)
returns boolean language sql immutable
as $$ select p_role in ('owner','admin','manager'); $$;

revoke all on function sav_ai_crm.workflow_current_member() from public,anon;
grant execute on function sav_ai_crm.workflow_current_member() to authenticated;

-- RLS ------------------------------------------------------------------------
alter table sav_ai_crm.workflow_versions enable row level security;
alter table sav_ai_crm.workflow_nodes enable row level security;
alter table sav_ai_crm.workflow_edges enable row level security;
alter table sav_ai_crm.workflow_triggers enable row level security;
alter table sav_ai_crm.workflow_executions enable row level security;
alter table sav_ai_crm.workflow_node_executions enable row level security;
alter table sav_ai_crm.workflow_approvals enable row level security;
alter table sav_ai_crm.workflow_templates enable row level security;

drop policy if exists "workspace insert workflows" on sav_ai_crm.workflows;
drop policy if exists "workspace update workflows" on sav_ai_crm.workflows;
drop policy if exists "workspace delete workflows" on sav_ai_crm.workflows;

create policy "workflow managers insert workflows" on sav_ai_crm.workflows
for insert to authenticated with check (
  exists(select 1 from sav_ai_crm.members m where m.user_id=auth.uid() and m.workspace_id=workflows.workspace_id and m.is_active=true and m.role in ('owner','admin','manager'))
);
create policy "workflow managers update workflows" on sav_ai_crm.workflows
for update to authenticated using (
  exists(select 1 from sav_ai_crm.members m where m.user_id=auth.uid() and m.workspace_id=workflows.workspace_id and m.is_active=true and m.role in ('owner','admin','manager'))
) with check (
  exists(select 1 from sav_ai_crm.members m where m.user_id=auth.uid() and m.workspace_id=workflows.workspace_id and m.is_active=true and m.role in ('owner','admin','manager'))
);
create policy "workflow admins delete workflows" on sav_ai_crm.workflows
for delete to authenticated using (
  exists(select 1 from sav_ai_crm.members m where m.user_id=auth.uid() and m.workspace_id=workflows.workspace_id and m.is_active=true and m.role in ('owner','admin'))
);

do $$
declare t text;
begin
  foreach t in array array[
    'workflow_versions','workflow_nodes','workflow_edges','workflow_triggers',
    'workflow_executions','workflow_node_executions','workflow_approvals','workflow_templates'
  ] loop
    execute format('drop policy if exists "workflow workspace read %1$s" on sav_ai_crm.%1$I',t);
    execute format('create policy "workflow workspace read %1$s" on sav_ai_crm.%1$I for select to authenticated using (sav_ai_crm.is_workspace_member(workspace_id))',t);
  end loop;
end $$;

-- Condition evaluation -------------------------------------------------------
create or replace function sav_ai_crm.workflow_condition_match(p_condition jsonb,p_context jsonb)
returns boolean language plpgsql immutable
as $$
declare
  field_path text; op text; actual jsonb; expected jsonb;
  actual_text text; expected_text text;
begin
  field_path:=p_condition->>'field';
  op:=p_condition->>'operator';
  expected:=p_condition->'value';
  if field_path is null or op is null then return false; end if;
  actual:=p_context #> string_to_array(field_path,'.');
  actual_text:=trim(both '"' from coalesce(actual::text,'null'));
  expected_text:=trim(both '"' from coalesce(expected::text,'null'));

  case op
    when 'equals' then return actual=expected;
    when 'not_equals' then return actual is distinct from expected;
    when 'contains' then return position(expected_text in actual_text)>0;
    when 'not_contains' then return position(expected_text in actual_text)=0;
    when 'greater_than' then return nullif(actual_text,'')::numeric > nullif(expected_text,'')::numeric;
    when 'less_than' then return nullif(actual_text,'')::numeric < nullif(expected_text,'')::numeric;
    when 'greater_or_equal' then return nullif(actual_text,'')::numeric >= nullif(expected_text,'')::numeric;
    when 'less_or_equal' then return nullif(actual_text,'')::numeric <= nullif(expected_text,'')::numeric;
    when 'is_empty' then return actual is null or actual='null'::jsonb or actual='""'::jsonb or actual='[]'::jsonb;
    when 'is_not_empty' then return not (actual is null or actual='null'::jsonb or actual='""'::jsonb or actual='[]'::jsonb);
    when 'in' then return jsonb_typeof(expected)='array' and expected @> jsonb_build_array(actual);
    when 'not_in' then return not (jsonb_typeof(expected)='array' and expected @> jsonb_build_array(actual));
    else return false;
  end case;
exception when others then
  return false;
end $$;

create or replace function sav_ai_crm.workflow_conditions_match(p_conditions jsonb,p_context jsonb)
returns boolean language sql immutable
as $$
 select case when coalesce(jsonb_array_length(p_conditions),0)=0 then true
 else not exists(
   select 1 from jsonb_array_elements(p_conditions) c
   where not sav_ai_crm.workflow_condition_match(c,p_context)
 ) end;
$$;

-- Persist graph helper -------------------------------------------------------
create or replace function sav_ai_crm.workflow_persist_graph(
 p_workspace_id uuid,p_workflow_id uuid,p_version integer,p_graph jsonb
) returns void language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare n jsonb; e jsonb;
begin
  if jsonb_typeof(coalesce(p_graph->'nodes','[]'))<>'array' or jsonb_typeof(coalesce(p_graph->'edges','[]'))<>'array' then
    raise exception 'Workflow graph must contain nodes and edges arrays';
  end if;
  if not exists(select 1 from jsonb_array_elements(p_graph->'nodes') x where x->>'type'='TRIGGER') then raise exception 'Workflow requires a TRIGGER node'; end if;
  if not exists(select 1 from jsonb_array_elements(p_graph->'nodes') x where x->>'type'='END') then raise exception 'Workflow requires an END node'; end if;

  for n in select * from jsonb_array_elements(p_graph->'nodes') loop
    if n->>'id' is null or n->>'type' is null or n->>'label' is null then raise exception 'Each workflow node requires id, type and label'; end if;
    insert into sav_ai_crm.workflow_nodes(workspace_id,workflow_id,workflow_version,node_key,node_type,label,position,config)
    values(p_workspace_id,p_workflow_id,p_version,n->>'id',n->>'type',n->>'label',coalesce(n->'position','{"x":0,"y":0}'::jsonb),coalesce(n->'config','{}'::jsonb));
  end loop;

  for e in select * from jsonb_array_elements(p_graph->'edges') loop
    if e->>'id' is null or e->>'source' is null or e->>'target' is null then raise exception 'Each workflow edge requires id, source and target'; end if;
    if not exists(select 1 from sav_ai_crm.workflow_nodes where workflow_id=p_workflow_id and workflow_version=p_version and node_key=e->>'source') then raise exception 'Workflow edge source is missing'; end if;
    if not exists(select 1 from sav_ai_crm.workflow_nodes where workflow_id=p_workflow_id and workflow_version=p_version and node_key=e->>'target') then raise exception 'Workflow edge target is missing'; end if;
    if e->>'source'=e->>'target' then raise exception 'Workflow edge cannot self-reference'; end if;
    insert into sav_ai_crm.workflow_edges(workspace_id,workflow_id,workflow_version,edge_key,source_key,target_key,branch,condition)
    values(p_workspace_id,p_workflow_id,p_version,e->>'id',e->>'source',e->>'target',e->>'branch',e->'condition');
  end loop;
end $$;

-- Internal helpers are not callable directly from API roles.
revoke all on function sav_ai_crm.workflow_condition_match(jsonb,jsonb) from public,anon,authenticated;
revoke all on function sav_ai_crm.workflow_conditions_match(jsonb,jsonb) from public,anon,authenticated;
revoke all on function sav_ai_crm.workflow_persist_graph(uuid,uuid,integer,jsonb) from public,anon,authenticated;

-- Registry CRUD --------------------------------------------------------------
create or replace function public.sav_ai_crm_workflow_registry()
returns jsonb language plpgsql stable security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members;
begin
 me:=sav_ai_crm.workflow_current_member();
 if me.id is null then raise exception 'CRM membership required'; end if;
 return coalesce((
   select jsonb_agg(jsonb_build_object(
     'id',w.id,'name',w.name,'description',w.description,'status',w.status,'trigger_type',w.trigger_type,
     'version',w.version,'created_at',w.created_at,'updated_at',w.updated_at,'enabled_at',w.enabled_at,'disabled_at',w.disabled_at,
     'run_count',w.run_count,'success_count',w.success_count,'last_run_at',w.last_run_at
   ) order by w.updated_at desc)
   from sav_ai_crm.workflows w
   where w.workspace_id=me.workspace_id and w.archived_at is null and w.status<>'archived'
 ),'[]'::jsonb);
end $$;

create or replace function public.sav_ai_crm_workflow_metrics()
returns jsonb language plpgsql stable security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members;
begin
 me:=sav_ai_crm.workflow_current_member();
 if me.id is null then raise exception 'CRM membership required'; end if;
 return jsonb_build_object(
  'active_workflows',(select count(*) from sav_ai_crm.workflows where workspace_id=me.workspace_id and status='active' and archived_at is null),
  'executions_today',(select count(*) from sav_ai_crm.workflow_executions where workspace_id=me.workspace_id and created_at>=date_trunc('day',now())),
  'successful',(select count(*) from sav_ai_crm.workflow_executions where workspace_id=me.workspace_id and execution_state='completed'),
  'failed',(select count(*) from sav_ai_crm.workflow_executions where workspace_id=me.workspace_id and execution_state='failed'),
  'waiting',(select count(*) from sav_ai_crm.workflow_executions where workspace_id=me.workspace_id and execution_state='waiting'),
  'approval_pending',(select count(*) from sav_ai_crm.workflow_approvals where workspace_id=me.workspace_id and status='pending'),
  'average_execution_seconds',(select coalesce(avg(extract(epoch from (completed_at-started_at))),0) from sav_ai_crm.workflow_executions where workspace_id=me.workspace_id and completed_at is not null and started_at is not null),
  'most_triggered',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from (select name,run_count from sav_ai_crm.workflows where workspace_id=me.workspace_id order by run_count desc limit 5)x),
  'most_failed',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from (
    select w.name,count(*) failures from sav_ai_crm.workflow_executions e join sav_ai_crm.workflows w on w.id=e.workflow_id
    where e.workspace_id=me.workspace_id and e.execution_state='failed' group by w.name order by failures desc limit 5
  )x)
 );
end $$;

create or replace function public.sav_ai_crm_workflow_templates()
returns jsonb language plpgsql stable security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members;
begin
 me:=sav_ai_crm.workflow_current_member();
 if me.id is null then raise exception 'CRM membership required'; end if;
 return coalesce((select jsonb_agg(to_jsonb(t) order by t.name) from sav_ai_crm.workflow_templates t where t.workspace_id=me.workspace_id),'[]'::jsonb);
end $$;

create or replace function public.sav_ai_crm_create_workflow(
 p_name text,p_description text,p_trigger_type text,p_graph jsonb,p_template_id uuid default null
) returns uuid language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; wid uuid; graph jsonb; workflow_id uuid;
begin
 me:=sav_ai_crm.workflow_current_member();
 if me.id is null or not sav_ai_crm.workflow_can_manage(me.role) then raise exception 'Workflow creation not permitted'; end if;
 if length(trim(coalesce(p_name,'')))<3 then raise exception 'Workflow name must be at least 3 characters'; end if;
 if p_trigger_type not in ('NEW_LEAD','LEAD_STATUS_CHANGED','PIPELINE_STAGE_CHANGED','TASK_CREATED','TASK_COMPLETED','FOLLOWUP_DUE','REMINDER_DUE','CONVERSATION_RECEIVED','AI_ESCALATION','MANUAL_TRIGGER','SCHEDULED_TRIGGER') then raise exception 'Invalid workflow trigger'; end if;
 wid:=me.workspace_id;
 graph:=p_graph;
 if p_template_id is not null then
   select definition,trigger_type into graph,p_trigger_type from sav_ai_crm.workflow_templates where id=p_template_id and workspace_id=wid;
   if graph is null then raise exception 'Workflow template not found'; end if;
 end if;

 insert into sav_ai_crm.workflows(workspace_id,name,description,trigger_type,status,definition,version,created_by,updated_by)
 values(wid,trim(p_name),nullif(trim(coalesce(p_description,'')),''),p_trigger_type,'draft',graph,1,me.id,me.id)
 returning id into workflow_id;

 perform sav_ai_crm.workflow_persist_graph(wid,workflow_id,1,graph);
 insert into sav_ai_crm.workflow_versions(workspace_id,workflow_id,version,definition,created_by) values(wid,workflow_id,1,graph,me.id);
 insert into sav_ai_crm.workflow_triggers(workspace_id,workflow_id,event,conditions,enabled)
 values(wid,workflow_id,p_trigger_type,coalesce((select n.config->'conditions' from sav_ai_crm.workflow_nodes n where n.workflow_id=workflow_id and n.workflow_version=1 and n.node_type='TRIGGER' limit 1),'[]'::jsonb),true);
 insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id,metadata)
 values(wid,auth.uid(),'workflow.create','workflow',workflow_id,jsonb_build_object('trigger',p_trigger_type,'version',1));
 return workflow_id;
end $$;

create or replace function public.sav_ai_crm_update_workflow(
 p_workflow_id uuid,p_name text,p_description text,p_trigger_type text,p_graph jsonb
) returns integer language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; w sav_ai_crm.workflows; next_version integer;
begin
 me:=sav_ai_crm.workflow_current_member();
 if me.id is null or not sav_ai_crm.workflow_can_manage(me.role) then raise exception 'Workflow update not permitted'; end if;
 select * into w from sav_ai_crm.workflows where id=p_workflow_id and workspace_id=me.workspace_id and archived_at is null;
 if w.id is null then raise exception 'Workflow not found'; end if;
 if p_trigger_type not in ('NEW_LEAD','LEAD_STATUS_CHANGED','PIPELINE_STAGE_CHANGED','TASK_CREATED','TASK_COMPLETED','FOLLOWUP_DUE','REMINDER_DUE','CONVERSATION_RECEIVED','AI_ESCALATION','MANUAL_TRIGGER','SCHEDULED_TRIGGER') then raise exception 'Invalid workflow trigger'; end if;
 next_version:=w.version+1;
 perform sav_ai_crm.workflow_persist_graph(me.workspace_id,w.id,next_version,p_graph);
 insert into sav_ai_crm.workflow_versions(workspace_id,workflow_id,version,definition,created_by) values(me.workspace_id,w.id,next_version,p_graph,me.id);
 update sav_ai_crm.workflows set name=trim(p_name),description=nullif(trim(coalesce(p_description,'')),''),trigger_type=p_trigger_type,
   definition=p_graph,version=next_version,updated_by=me.id,updated_at=now() where id=w.id;
 update sav_ai_crm.workflow_triggers set event=p_trigger_type,
   conditions=coalesce((select config->'conditions' from sav_ai_crm.workflow_nodes where workflow_id=w.id and workflow_version=next_version and node_type='TRIGGER' limit 1),'[]'::jsonb)
 where workflow_id=w.id;
 insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id,metadata)
 values(me.workspace_id,auth.uid(),'workflow.update','workflow',w.id,jsonb_build_object('version',next_version));
 return next_version;
end $$;

create or replace function public.sav_ai_crm_workflow_detail(p_workflow_id uuid)
returns jsonb language plpgsql stable security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; w sav_ai_crm.workflows;
begin
 me:=sav_ai_crm.workflow_current_member();
 if me.id is null then raise exception 'CRM membership required'; end if;
 select * into w from sav_ai_crm.workflows where id=p_workflow_id and workspace_id=me.workspace_id and archived_at is null;
 if w.id is null then raise exception 'Workflow not found'; end if;
 return jsonb_build_object(
  'workflow',to_jsonb(w),
  'nodes',coalesce((select jsonb_agg(jsonb_build_object('id',n.node_key,'type',n.node_type,'label',n.label,'position',n.position,'config',n.config) order by n.created_at) from sav_ai_crm.workflow_nodes n where n.workflow_id=w.id and n.workflow_version=w.version),'[]'::jsonb),
  'edges',coalesce((select jsonb_agg(jsonb_build_object('id',e.edge_key,'source',e.source_key,'target',e.target_key,'branch',e.branch,'condition',e.condition) order by e.created_at) from sav_ai_crm.workflow_edges e where e.workflow_id=w.id and e.workflow_version=w.version),'[]'::jsonb),
  'versions',coalesce((select jsonb_agg(jsonb_build_object('version',v.version,'created_at',v.created_at,'created_by',v.created_by) order by v.version desc) from sav_ai_crm.workflow_versions v where v.workflow_id=w.id),'[]'::jsonb),
  'executions',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select * from sav_ai_crm.workflow_executions where workflow_id=w.id order by created_at desc limit 50)x),'[]'::jsonb),
  'approvals',coalesce((select jsonb_agg(to_jsonb(a) order by a.requested_at desc) from sav_ai_crm.workflow_approvals a where a.workflow_id=w.id),'[]'::jsonb),
  'permissions',jsonb_build_object('manage',sav_ai_crm.workflow_can_manage(me.role),'admin',me.role in ('owner','admin'))
 );
end $$;

create or replace function public.sav_ai_crm_set_workflow_status(p_workflow_id uuid,p_status text)
returns void language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; old_status text;
begin
 me:=sav_ai_crm.workflow_current_member();
 if me.id is null or not sav_ai_crm.workflow_can_manage(me.role) then raise exception 'Workflow status change not permitted'; end if;
 if p_status not in ('active','paused','disabled') then raise exception 'Invalid workflow status'; end if;
 select status into old_status from sav_ai_crm.workflows where id=p_workflow_id and workspace_id=me.workspace_id and archived_at is null;
 if old_status is null then raise exception 'Workflow not found'; end if;
 update sav_ai_crm.workflows set status=p_status,updated_by=me.id,updated_at=now(),
   enabled_at=case when p_status='active' then now() else enabled_at end,
   disabled_at=case when p_status='disabled' then now() else disabled_at end
 where id=p_workflow_id;
 insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id,metadata)
 values(me.workspace_id,auth.uid(),'workflow.status','workflow',p_workflow_id,jsonb_build_object('from',old_status,'to',p_status));
end $$;

create or replace function public.sav_ai_crm_duplicate_workflow(p_workflow_id uuid)
returns uuid language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; w sav_ai_crm.workflows; new_id uuid;
begin
 me:=sav_ai_crm.workflow_current_member();
 if me.id is null or not sav_ai_crm.workflow_can_manage(me.role) then raise exception 'Workflow duplication not permitted'; end if;
 select * into w from sav_ai_crm.workflows where id=p_workflow_id and workspace_id=me.workspace_id and archived_at is null;
 if w.id is null then raise exception 'Workflow not found'; end if;
 new_id:=public.sav_ai_crm_create_workflow(w.name||' Copy',w.description,w.trigger_type,w.definition,null);
 return new_id;
end $$;

create or replace function public.sav_ai_crm_archive_workflow(p_workflow_id uuid)
returns void language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members;
begin
 me:=sav_ai_crm.workflow_current_member();
 if me.id is null or me.role not in ('owner','admin') then raise exception 'Workflow archive requires owner or admin permission'; end if;
 update sav_ai_crm.workflows set status='archived',archived_at=now(),updated_by=me.id,updated_at=now()
 where id=p_workflow_id and workspace_id=me.workspace_id and archived_at is null;
 if not found then raise exception 'Workflow not found'; end if;
 insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id)
 values(me.workspace_id,auth.uid(),'workflow.archive','workflow',p_workflow_id);
end $$;

create or replace function public.sav_ai_crm_dispatch_workflow_event(
 p_event text,p_context jsonb,p_event_key text
) returns jsonb language plpgsql security definer
set search_path=public,sav_ai_crm
as $
declare me sav_ai_crm.members; tr record; results jsonb:='[]'::jsonb; eid uuid; run_result jsonb; idem text;
begin
 me:=sav_ai_crm.workflow_current_member();
 if me.id is null or me.role='viewer' then raise exception 'Workflow event dispatch not permitted'; end if;
 if p_event not in ('NEW_LEAD','LEAD_STATUS_CHANGED','PIPELINE_STAGE_CHANGED','TASK_CREATED','TASK_COMPLETED','FOLLOWUP_DUE','REMINDER_DUE','CONVERSATION_RECEIVED','AI_ESCALATION','MANUAL_TRIGGER','SCHEDULED_TRIGGER') then raise exception 'Invalid workflow event'; end if;
 if coalesce(trim(p_event_key),'')='' then raise exception 'Event idempotency key is required'; end if;

 for tr in
   select t.*,w.version,w.status from sav_ai_crm.workflow_triggers t
   join sav_ai_crm.workflows w on w.id=t.workflow_id
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
end $;

-- Test plan ------------------------------------------------------------------
create or replace function public.sav_ai_crm_test_workflow(p_workflow_id uuid,p_context jsonb)
returns jsonb language plpgsql stable security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; w sav_ai_crm.workflows; plan jsonb;
begin
 me:=sav_ai_crm.workflow_current_member();
 if me.id is null then raise exception 'CRM membership required'; end if;
 select * into w from sav_ai_crm.workflows where id=p_workflow_id and workspace_id=me.workspace_id and archived_at is null;
 if w.id is null then raise exception 'Workflow not found'; end if;
 select coalesce(jsonb_agg(jsonb_build_object(
   'node_id',n.node_key,'type',n.node_type,'label',n.label,'config',n.config,
   'risk',case when n.node_type in ('HUMAN_APPROVAL','NOTIFICATION') then 'high'
               when n.node_type in ('ACTION','AI_AGENT','ESCALATION') then 'medium' else 'low' end,
   'approval_required',case when n.node_type='HUMAN_APPROVAL' then true
                            when n.node_type='NOTIFICATION' then true
                            when n.node_type='AI_AGENT' and coalesce((n.config->>'risk_level') in ('high','critical'),false) then true
                            else false end
 ) order by n.created_at),'[]'::jsonb) into plan
 from sav_ai_crm.workflow_nodes n where n.workflow_id=w.id and n.workflow_version=w.version;
 return jsonb_build_object(
   'workflow_id',w.id,'version',w.version,'trigger',w.trigger_type,'context',coalesce(p_context,'{}'),
   'planned_nodes',plan,'test_mode',true,'external_messages_disabled',true
 );
end $$;

-- Execution helpers ----------------------------------------------------------
create or replace function sav_ai_crm.workflow_next_node(
 p_workflow_id uuid,p_version integer,p_source_key text,p_branch text default null
) returns uuid language sql stable
set search_path=public,sav_ai_crm
as $$
 select n.id
 from sav_ai_crm.workflow_edges e
 join sav_ai_crm.workflow_nodes n on n.workflow_id=e.workflow_id and n.workflow_version=e.workflow_version and n.node_key=e.target_key
 where e.workflow_id=p_workflow_id and e.workflow_version=p_version and e.source_key=p_source_key
   and (p_branch is null or e.branch=p_branch or e.branch is null)
 order by case when e.branch=p_branch then 0 else 1 end,e.created_at
 limit 1;
$$;

revoke all on function sav_ai_crm.workflow_next_node(uuid,integer,text,text) from public,anon,authenticated;

create or replace function public.sav_ai_crm_start_workflow(
 p_workflow_id uuid,p_context jsonb,p_idempotency_key text default null,p_trigger text default 'MANUAL_TRIGGER'
) returns uuid language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; w sav_ai_crm.workflows; eid uuid; first_node uuid; idem text;
begin
 me:=sav_ai_crm.workflow_current_member();
 if me.id is null or me.role='viewer' then raise exception 'Workflow execution not permitted'; end if;
 select * into w from sav_ai_crm.workflows where id=p_workflow_id and workspace_id=me.workspace_id and archived_at is null;
 if w.id is null then raise exception 'Workflow not found'; end if;
 if w.status<>'active' then raise exception 'Workflow is not active'; end if;
 first_node:=(select id from sav_ai_crm.workflow_nodes where workflow_id=w.id and workflow_version=w.version and node_type='TRIGGER' order by created_at limit 1);
 if first_node is null then raise exception 'Workflow has no trigger node'; end if;
 idem:=coalesce(nullif(p_idempotency_key,''),md5(w.id::text||':'||coalesce(p_trigger,'')||':'||coalesce(p_context::text,'{}')||':'||clock_timestamp()::text));
 begin
  insert into sav_ai_crm.workflow_executions(workspace_id,workflow_id,workflow_version,trigger,context,current_node_id,execution_state,idempotency_key,started_at)
  values(me.workspace_id,w.id,w.version,p_trigger,coalesce(p_context,'{}'),first_node,'queued',idem,now())
  returning id into eid;
 exception when unique_violation then
  select id into eid from sav_ai_crm.workflow_executions where workspace_id=me.workspace_id and idempotency_key=idem;
  return eid;
 end;
 update sav_ai_crm.workflows set run_count=run_count+1,last_run_at=now() where id=w.id;
 insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id,metadata)
 values(me.workspace_id,auth.uid(),'workflow.execute.start','workflow_execution',eid,jsonb_build_object('workflow_id',w.id,'version',w.version,'trigger',p_trigger));
 return eid;
end $$;

create or replace function public.sav_ai_crm_run_workflow_execution(p_execution_id uuid)
returns jsonb language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare
 me sav_ai_crm.members; ex sav_ai_crm.workflow_executions; w sav_ai_crm.workflows; n sav_ai_crm.workflow_nodes;
 ne_id uuid; next_id uuid; branch_key text; node_exec_id text; task_id uuid; action_result jsonb;
 delay_seconds integer; approval_id uuid; agent_id uuid; capability text; target_type text; target_id uuid;
begin
 me:=sav_ai_crm.workflow_current_member();
 if me.id is null or me.role='viewer' then raise exception 'Workflow execution not permitted'; end if;
 select * into ex from sav_ai_crm.workflow_executions where id=p_execution_id and workspace_id=me.workspace_id for update;
 if ex.id is null then raise exception 'Workflow execution not found'; end if;
 if ex.execution_state in ('completed','failed','cancelled') then return to_jsonb(ex); end if;
 if ex.execution_state='waiting' and ex.scheduled_for>now() then return to_jsonb(ex); end if;
 if ex.execution_state='waiting_approval' then return to_jsonb(ex); end if;
 select * into w from sav_ai_crm.workflows where id=ex.workflow_id and workspace_id=ex.workspace_id;
 update sav_ai_crm.workflow_executions set execution_state='running',scheduled_for=null,updated_at=now() where id=ex.id;

 loop
   select * into ex from sav_ai_crm.workflow_executions where id=p_execution_id;
   if ex.depth>=ex.max_depth then
     update sav_ai_crm.workflow_executions set execution_state='failed',error='MAX_EXECUTION_DEPTH_EXCEEDED',completed_at=now(),updated_at=now() where id=ex.id;
     return jsonb_build_object('id',ex.id,'status','failed','error','MAX_EXECUTION_DEPTH_EXCEEDED');
   end if;
   if ex.current_node_id is null then
     update sav_ai_crm.workflow_executions set execution_state='completed',completed_at=now(),updated_at=now() where id=ex.id;
     update sav_ai_crm.workflows set success_count=success_count+1 where id=ex.workflow_id;
     return jsonb_build_object('id',ex.id,'status','completed');
   end if;

   select * into n from sav_ai_crm.workflow_nodes where id=ex.current_node_id and workspace_id=ex.workspace_id;
   if n.id is null then
     update sav_ai_crm.workflow_executions set execution_state='failed',error='CURRENT_NODE_NOT_FOUND',completed_at=now(),updated_at=now() where id=ex.id;
     return jsonb_build_object('id',ex.id,'status','failed','error','CURRENT_NODE_NOT_FOUND');
   end if;

   node_exec_id:=ex.id::text||':'||n.id::text||':'||ex.depth::text;
   insert into sav_ai_crm.workflow_node_executions(workspace_id,execution_id,node_id,node_execution_id,input,status)
   values(ex.workspace_id,ex.id,n.id,node_exec_id,ex.context,'running')
   on conflict(execution_id,node_execution_id,attempt) do nothing
   returning id into ne_id;

   if n.node_type='END' then
     update sav_ai_crm.workflow_node_executions set status='completed',output='{"ended":true}'::jsonb,completed_at=now() where execution_id=ex.id and node_execution_id=node_exec_id;
     update sav_ai_crm.workflow_executions set current_node_id=null,execution_state='completed',depth=depth+1,completed_at=now(),updated_at=now() where id=ex.id;
     update sav_ai_crm.workflows set success_count=success_count+1 where id=ex.workflow_id;
     return jsonb_build_object('id',ex.id,'status','completed');

   elsif n.node_type='CONDITION' then
     branch_key:=case when sav_ai_crm.workflow_condition_match(n.config->'condition',ex.context) then 'true' else 'false' end;
     next_id:=sav_ai_crm.workflow_next_node(ex.workflow_id,ex.workflow_version,n.node_key,branch_key);
     update sav_ai_crm.workflow_node_executions set status='completed',output=jsonb_build_object('matched',branch_key='true','branch',branch_key),completed_at=now()
       where execution_id=ex.id and node_execution_id=node_exec_id;

   elsif n.node_type='WAIT' then
     delay_seconds:=greatest(1,least(coalesce((n.config->>'delay_seconds')::integer,60),604800));
     next_id:=sav_ai_crm.workflow_next_node(ex.workflow_id,ex.workflow_version,n.node_key,null);
     update sav_ai_crm.workflow_node_executions set status='waiting',output=jsonb_build_object('delay_seconds',delay_seconds,'scheduled_for',now()+make_interval(secs=>delay_seconds)),completed_at=now()
       where execution_id=ex.id and node_execution_id=node_exec_id;
     update sav_ai_crm.workflow_executions set current_node_id=next_id,execution_state='waiting',scheduled_for=now()+make_interval(secs=>delay_seconds),depth=depth+1,updated_at=now() where id=ex.id;
     return jsonb_build_object('id',ex.id,'status','waiting','scheduled_for',now()+make_interval(secs=>delay_seconds));

   elsif n.node_type='HUMAN_APPROVAL' then
     insert into sav_ai_crm.workflow_approvals(workspace_id,workflow_id,execution_id,node_id,approver_role,approver_user_id,requested_by,timeout_at,approval_reason,risk_level,status)
     values(ex.workspace_id,ex.workflow_id,ex.id,n.id,n.config->>'approver_role',nullif(n.config->>'approver_user_id','')::uuid,me.id,
       case when (n.config->>'timeout_seconds') is not null then now()+make_interval(secs=>(n.config->>'timeout_seconds')::integer) else null end,
       coalesce(n.config->>'reason','Workflow approval required'),coalesce(n.config->>'risk_level','high'),'pending')
     returning id into approval_id;
     next_id:=sav_ai_crm.workflow_next_node(ex.workflow_id,ex.workflow_version,n.node_key,'approved');
     update sav_ai_crm.workflow_node_executions set status='waiting_approval',approval_required=true,risk_level=coalesce(n.config->>'risk_level','high'),output=jsonb_build_object('approval_id',approval_id),completed_at=now()
       where execution_id=ex.id and node_execution_id=node_exec_id;
     update sav_ai_crm.workflow_executions set current_node_id=next_id,execution_state='waiting_approval',depth=depth+1,updated_at=now() where id=ex.id;
     return jsonb_build_object('id',ex.id,'status','waiting_approval','approval_id',approval_id);

   elsif n.node_type in ('TASK','FOLLOW_UP') then
     if n.config->>'lead_id_path' is not null then target_id:=nullif(trim(both '"' from (ex.context #> string_to_array(n.config->>'lead_id_path','.'))::text),'null')::uuid;
     else target_id:=nullif(n.config->>'lead_id','')::uuid; end if;
     if target_id is not null and not exists(select 1 from sav_ai_crm.leads where id=target_id and workspace_id=ex.workspace_id) then raise exception 'Workflow task lead is outside workspace'; end if;
     agent_id:=nullif(n.config->>'assigned_agent_id','')::uuid;
     if agent_id is not null and not exists(select 1 from sav_ai_crm.ai_agents where id=agent_id and workspace_id=ex.workspace_id and status='active') then raise exception 'Workflow task agent is invalid'; end if;
     insert into sav_ai_crm.tasks(workspace_id,lead_id,title,description,task_type,followup_type,status,priority,due_at,reminder_at,assigned_agent_id,created_by,notes)
     values(ex.workspace_id,target_id,coalesce(n.config->>'title',n.label),n.config->>'description','followup',
       case when n.node_type='FOLLOW_UP' then coalesce(n.config->>'followup_type','general') else 'general' end,
       'pending',coalesce(n.config->>'priority','medium'),
       case when (n.config->>'due_in_seconds') is not null then now()+make_interval(secs=>(n.config->>'due_in_seconds')::integer) else null end,
       case when (n.config->>'reminder_in_seconds') is not null then now()+make_interval(secs=>(n.config->>'reminder_in_seconds')::integer) else null end,
       agent_id,me.id,'Created by: Workflow — '||w.name)
     returning id into task_id;
     insert into sav_ai_crm.activities(workspace_id,lead_id,task_id,activity_type,title,description,metadata)
     values(ex.workspace_id,target_id,task_id,case when n.node_type='FOLLOW_UP' then 'workflow_followup_created' else 'workflow_task_created' end,
       'Workflow created task',coalesce(n.config->>'title',n.label),jsonb_build_object('workflow_id',w.id,'execution_id',ex.id,'node_id',n.id));
     update sav_ai_crm.workflow_node_executions set status='completed',output=jsonb_build_object('task_id',task_id),completed_at=now()
       where execution_id=ex.id and node_execution_id=node_exec_id;
     next_id:=sav_ai_crm.workflow_next_node(ex.workflow_id,ex.workflow_version,n.node_key,null);

   elsif n.node_type='AI_AGENT' then
     agent_id:=nullif(n.config->>'agent_id','')::uuid;
     if agent_id is null and nullif(n.config->>'agent_slug','') is not null then
       select id into agent_id from sav_ai_crm.ai_agents where workspace_id=ex.workspace_id and slug=n.config->>'agent_slug' and status='active' limit 1;
     end if;
     capability:=coalesce(n.config->>'action','CREATE_TASK');
     target_type:=coalesce(n.config->>'target_type','lead');
     if n.config->>'target_id_path' is not null then target_id:=nullif(trim(both '"' from (ex.context #> string_to_array(n.config->>'target_id_path','.'))::text),'null')::uuid;
     else target_id:=nullif(n.config->>'target_id','')::uuid; end if;
     if agent_id is null then raise exception 'AI_AGENT node requires agent_id'; end if;
     action_result:=public.sav_ai_crm_request_agent_action(agent_id,capability,target_type,target_id,coalesce(n.config->'payload','{}'::jsonb));
     if coalesce((action_result->>'approval_required')::boolean,false) then
       insert into sav_ai_crm.workflow_approvals(workspace_id,workflow_id,execution_id,node_id,approver_role,requested_by,approval_reason,risk_level,status,metadata)
       values(ex.workspace_id,ex.workflow_id,ex.id,n.id,'manager',me.id,'AI action requires human approval',coalesce(action_result->>'risk_level','high'),'pending',
         jsonb_build_object('agent_action_id',action_result->>'action_id'))
       returning id into approval_id;
       next_id:=sav_ai_crm.workflow_next_node(ex.workflow_id,ex.workflow_version,n.node_key,null);
       update sav_ai_crm.workflow_node_executions set status='waiting_approval',approval_required=true,risk_level=action_result->>'risk_level',output=jsonb_build_object('agent_action',action_result,'approval_id',approval_id),completed_at=now()
         where execution_id=ex.id and node_execution_id=node_exec_id;
       update sav_ai_crm.workflow_executions set current_node_id=next_id,execution_state='waiting_approval',depth=depth+1,updated_at=now() where id=ex.id;
       return jsonb_build_object('id',ex.id,'status','waiting_approval','approval_id',approval_id);
     else
       action_result:=public.sav_ai_crm_execute_agent_action((action_result->>'action_id')::uuid);
       update sav_ai_crm.workflow_node_executions set status='completed',output=action_result,completed_at=now()
         where execution_id=ex.id and node_execution_id=node_exec_id;
       next_id:=sav_ai_crm.workflow_next_node(ex.workflow_id,ex.workflow_version,n.node_key,null);
     end if;

   elsif n.node_type='ACTION' then
     if n.config->>'action' in ('CREATE_TASK','CREATE_FOLLOWUP') then
       target_id:=nullif(trim(both '"' from (ex.context #> string_to_array(coalesce(n.config->>'lead_id_path','lead.id'),'.'))::text),'null')::uuid;
       if target_id is not null and not exists(select 1 from sav_ai_crm.leads where id=target_id and workspace_id=ex.workspace_id) then raise exception 'Lead is outside this workspace'; end if;
       agent_id:=nullif(n.config->>'assigned_agent_id','')::uuid;
       if agent_id is not null and not exists(select 1 from sav_ai_crm.ai_agents where id=agent_id and workspace_id=ex.workspace_id and status='active') then raise exception 'Assigned agent is invalid'; end if;
       insert into sav_ai_crm.tasks(workspace_id,lead_id,title,description,task_type,followup_type,status,priority,due_at,assigned_agent_id,created_by,notes)
       values(ex.workspace_id,target_id,coalesce(n.config->>'title','Workflow task'),n.config->>'description','followup',
         case when n.config->>'action'='CREATE_FOLLOWUP' then coalesce(n.config->>'followup_type','general') else 'general' end,
         'pending',coalesce(n.config->>'priority','medium'),
         case when n.config->>'due_in_seconds' is not null then now()+make_interval(secs=>(n.config->>'due_in_seconds')::integer) else null end,
         agent_id,me.id,'Created by: Workflow — '||w.name) returning id into task_id;
       insert into sav_ai_crm.activities(workspace_id,lead_id,task_id,activity_type,title,description,metadata)
       values(ex.workspace_id,target_id,task_id,case when n.config->>'action'='CREATE_FOLLOWUP' then 'workflow_followup_created' else 'workflow_task_created' end,
         'Workflow action created task',coalesce(n.config->>'title','Workflow task'),jsonb_build_object('workflow_id',w.id,'execution_id',ex.id,'node_id',n.id));
     elsif n.config->>'action' in ('UPDATE_TASK','ASSIGN_TASK') then
       target_id:=nullif(trim(both '"' from (ex.context #> string_to_array(coalesce(n.config->>'task_id_path','task.id'),'.'))::text),'null')::uuid;
       if target_id is null or not exists(select 1 from sav_ai_crm.tasks where id=target_id and workspace_id=ex.workspace_id and archived_at is null) then raise exception 'Task is outside this workspace'; end if;
       if n.config->>'action'='UPDATE_TASK' then
         update sav_ai_crm.tasks set
           status=coalesce(n.config->'values'->>'status',status),
           priority=coalesce(n.config->'values'->>'priority',priority),
           updated_at=now()
         where id=target_id and workspace_id=ex.workspace_id;
       else
         if nullif(n.config->>'assigned_to','') is not null and nullif(n.config->>'assigned_agent_id','') is not null then raise exception 'Task can be assigned to a human or AI agent, not both'; end if;
         if nullif(n.config->>'assigned_to','') is not null and not exists(select 1 from sav_ai_crm.members where id=(n.config->>'assigned_to')::uuid and workspace_id=ex.workspace_id and is_active) then raise exception 'Human task assignee is invalid'; end if;
         if nullif(n.config->>'assigned_agent_id','') is not null and not exists(select 1 from sav_ai_crm.ai_agents where id=(n.config->>'assigned_agent_id')::uuid and workspace_id=ex.workspace_id and status='active') then raise exception 'AI task assignee is invalid'; end if;
         update sav_ai_crm.tasks set assigned_to=nullif(n.config->>'assigned_to','')::uuid,
           assigned_agent_id=nullif(n.config->>'assigned_agent_id','')::uuid,updated_at=now()
         where id=target_id and workspace_id=ex.workspace_id;
       end if;
       insert into sav_ai_crm.activities(workspace_id,task_id,actor_member_id,activity_type,title,description,metadata)
       values(ex.workspace_id,target_id,me.id,'workflow_task_updated','Workflow updated task',w.name,jsonb_build_object('workflow_id',w.id,'execution_id',ex.id,'node_id',n.id,'action',n.config->>'action'));
     elsif n.config->>'action'='ASSIGN_AGENT' then
       agent_id:=nullif(n.config->>'agent_id','')::uuid;
       if agent_id is null or not exists(select 1 from sav_ai_crm.ai_agents where id=agent_id and workspace_id=ex.workspace_id and status='active') then raise exception 'Agent assignment is invalid'; end if;
       update sav_ai_crm.workflow_executions set context=jsonb_set(context,'{assigned_agent_id}',to_jsonb(agent_id::text),true),updated_at=now() where id=ex.id;
     elsif n.config->>'action'='CREATE_ESCALATION' then
       agent_id:=nullif(n.config->>'agent_id','')::uuid;
       if agent_id is null and nullif(n.config->>'agent_slug','') is not null then select id into agent_id from sav_ai_crm.ai_agents where workspace_id=ex.workspace_id and slug=n.config->>'agent_slug' limit 1; end if;
       if agent_id is null then raise exception 'Escalation action requires agent'; end if;
       target_id:=nullif(trim(both '"' from (ex.context #> string_to_array(coalesce(n.config->>'lead_id_path','lead.id'),'.'))::text),'null')::uuid;
       insert into sav_ai_crm.ai_agent_escalations(workspace_id,agent_id,lead_id,workflow_id,workflow_execution_id,reason,status,details)
       values(ex.workspace_id,agent_id,target_id,w.id,ex.id,coalesce(n.config->>'reason','FAILED_ACTION'),'open',n.config->>'details');
     elsif n.config->>'action'='REQUEST_APPROVAL' then
       insert into sav_ai_crm.workflow_approvals(workspace_id,workflow_id,execution_id,node_id,approver_role,approver_user_id,requested_by,approval_reason,risk_level,status)
       values(ex.workspace_id,ex.workflow_id,ex.id,n.id,n.config->>'approver_role',nullif(n.config->>'approver_user_id','')::uuid,me.id,
         coalesce(n.config->>'reason','Workflow action approval required'),coalesce(n.config->>'risk_level','high'),'pending')
       returning id into approval_id;
       next_id:=sav_ai_crm.workflow_next_node(ex.workflow_id,ex.workflow_version,n.node_key,'approved');
       update sav_ai_crm.workflow_node_executions set status='waiting_approval',approval_required=true,risk_level=coalesce(n.config->>'risk_level','high'),output=jsonb_build_object('approval_id',approval_id),completed_at=now()
         where execution_id=ex.id and node_execution_id=node_exec_id;
       update sav_ai_crm.workflow_executions set current_node_id=next_id,execution_state='waiting_approval',depth=depth+1,updated_at=now() where id=ex.id;
       return jsonb_build_object('id',ex.id,'status','waiting_approval','approval_id',approval_id);
     elsif n.config->>'action'='WAIT' then
       delay_seconds:=greatest(1,least(coalesce((n.config->>'delay_seconds')::integer,60),604800));
       next_id:=sav_ai_crm.workflow_next_node(ex.workflow_id,ex.workflow_version,n.node_key,null);
       update sav_ai_crm.workflow_node_executions set status='waiting',output=jsonb_build_object('delay_seconds',delay_seconds),completed_at=now()
         where execution_id=ex.id and node_execution_id=node_exec_id;
       update sav_ai_crm.workflow_executions set current_node_id=next_id,execution_state='waiting',scheduled_for=now()+make_interval(secs=>delay_seconds),depth=depth+1,updated_at=now() where id=ex.id;
       return jsonb_build_object('id',ex.id,'status','waiting','scheduled_for',now()+make_interval(secs=>delay_seconds));
     elsif n.config->>'action'='UPDATE_LEAD' then
       target_id:=nullif(trim(both '"' from (ex.context #> string_to_array(coalesce(n.config->>'lead_id_path','lead.id'),'.'))::text),'null')::uuid;
       if target_id is null or not exists(select 1 from sav_ai_crm.leads where id=target_id and workspace_id=ex.workspace_id) then raise exception 'Lead is outside this workspace'; end if;
       update sav_ai_crm.leads set
         status=coalesce(n.config->'values'->>'status',status),
         priority=coalesce(n.config->'values'->>'priority',priority),
         notes=case when n.config->'values'->>'note' is not null then concat_ws(E'\n',notes,'[Workflow '||w.name||'] '||(n.config->'values'->>'note')) else notes end,
         updated_at=now()
       where id=target_id and workspace_id=ex.workspace_id;
       insert into sav_ai_crm.activities(workspace_id,lead_id,actor_member_id,activity_type,title,description,metadata)
       values(ex.workspace_id,target_id,me.id,'workflow_lead_updated','Workflow updated lead',w.name,jsonb_build_object('workflow_id',w.id,'execution_id',ex.id,'node_id',n.id));
       insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id,metadata)
       values(ex.workspace_id,auth.uid(),'workflow.lead.update','lead',target_id,jsonb_build_object('workflow_id',w.id,'execution_id',ex.id,'node_id',n.id));
     elsif n.config->>'action'='ADD_NOTE' then
       target_id:=nullif(trim(both '"' from (ex.context #> string_to_array(coalesce(n.config->>'lead_id_path','lead.id'),'.'))::text),'null')::uuid;
       update sav_ai_crm.leads set notes=concat_ws(E'\n',notes,'[Workflow '||w.name||'] '||coalesce(n.config->>'note','')),updated_at=now()
       where id=target_id and workspace_id=ex.workspace_id;
       if not found then raise exception 'Lead is outside this workspace'; end if;
       insert into sav_ai_crm.activities(workspace_id,lead_id,actor_member_id,activity_type,title,description,metadata)
       values(ex.workspace_id,target_id,me.id,'workflow_note_added','Workflow added note',coalesce(n.config->>'note',''),
         jsonb_build_object('workflow_id',w.id,'execution_id',ex.id,'node_id',n.id));
     elsif n.config->>'action'='END_WORKFLOW' then
       update sav_ai_crm.workflow_node_executions set status='completed',output='{"ended":true}'::jsonb,completed_at=now() where execution_id=ex.id and node_execution_id=node_exec_id;
       update sav_ai_crm.workflow_executions set current_node_id=null,execution_state='completed',depth=depth+1,completed_at=now(),updated_at=now() where id=ex.id;
       update sav_ai_crm.workflows set success_count=success_count+1 where id=ex.workflow_id;
       return jsonb_build_object('id',ex.id,'status','completed');
     else
       raise exception 'WORKFLOW_ACTION_ADAPTER_NOT_IMPLEMENTED';
     end if;
     insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id,metadata)
     values(ex.workspace_id,auth.uid(),'workflow.action.'||lower(coalesce(n.config->>'action','unknown')),'workflow_execution',ex.id,
       jsonb_build_object('workflow_id',w.id,'node_id',n.id,'target_id',target_id,'task_id',task_id));
     update sav_ai_crm.workflow_node_executions set status='completed',output=jsonb_build_object('action',n.config->>'action','task_id',task_id,'target_id',target_id),completed_at=now()
       where execution_id=ex.id and node_execution_id=node_exec_id;
     next_id:=sav_ai_crm.workflow_next_node(ex.workflow_id,ex.workflow_version,n.node_key,null);

   elsif n.node_type='ESCALATION' then
     agent_id:=nullif(n.config->>'agent_id','')::uuid;
     if agent_id is null and nullif(n.config->>'agent_slug','') is not null then
       select id into agent_id from sav_ai_crm.ai_agents where workspace_id=ex.workspace_id and slug=n.config->>'agent_slug' limit 1;
     end if;
     if agent_id is null or not exists(select 1 from sav_ai_crm.ai_agents where id=agent_id and workspace_id=ex.workspace_id) then raise exception 'Escalation requires a valid agent'; end if;
     target_id:=nullif(trim(both '"' from (ex.context #> string_to_array(coalesce(n.config->>'lead_id_path','lead.id'),'.'))::text),'null')::uuid;
     insert into sav_ai_crm.ai_agent_escalations(workspace_id,agent_id,lead_id,execution_id,workflow_id,workflow_execution_id,reason,status,details)
     values(ex.workspace_id,agent_id,target_id,null,w.id,ex.id,coalesce(n.config->>'reason','FAILED_ACTION'),'open',coalesce(n.config->>'details','Workflow escalation: '||w.name));
     update sav_ai_crm.workflow_node_executions set status='completed',output='{"escalated":true}'::jsonb,completed_at=now()
       where execution_id=ex.id and node_execution_id=node_exec_id;
     next_id:=sav_ai_crm.workflow_next_node(ex.workflow_id,ex.workflow_version,n.node_key,null);

   elsif n.node_type='NOTIFICATION' then
     update sav_ai_crm.workflow_node_executions set status='failed',last_error='CHANNEL_PROVIDER_NOT_CONFIGURED',output=jsonb_build_object('channel',n.config->>'channel'),completed_at=now()
       where execution_id=ex.id and node_execution_id=node_exec_id;
     update sav_ai_crm.workflow_executions set execution_state='failed',error='CHANNEL_PROVIDER_NOT_CONFIGURED',completed_at=now(),updated_at=now() where id=ex.id;
     return jsonb_build_object('id',ex.id,'status','failed','error','CHANNEL_PROVIDER_NOT_CONFIGURED');

   else
     update sav_ai_crm.workflow_node_executions set status='completed',output='{}'::jsonb,completed_at=now()
       where execution_id=ex.id and node_execution_id=node_exec_id;
     next_id:=sav_ai_crm.workflow_next_node(ex.workflow_id,ex.workflow_version,n.node_key,null);
   end if;

   update sav_ai_crm.workflow_executions set current_node_id=next_id,depth=depth+1,updated_at=now() where id=ex.id;
 end loop;
exception when others then
 update sav_ai_crm.workflow_node_executions
 set status=case when retry_count+1>max_retries then 'failed' else 'retrying' end,
     retry_count=retry_count+1,last_error=sqlerrm,completed_at=case when retry_count+1>max_retries then now() else completed_at end
 where execution_id=p_execution_id and status='running';
 update sav_ai_crm.workflow_executions set execution_state='failed',retry_count=retry_count+1,error=sqlerrm,updated_at=now(),
   completed_at=case when retry_count+1>max_retries then now() else completed_at end
 where id=p_execution_id;
 insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id,metadata)
 select workspace_id,auth.uid(),'workflow.execute.failed','workflow_execution',id,jsonb_build_object('error',sqlerrm) from sav_ai_crm.workflow_executions where id=p_execution_id;
 return jsonb_build_object('id',p_execution_id,'status','failed','error',sqlerrm);
end $$;

create or replace function public.sav_ai_crm_resume_workflow_execution(p_execution_id uuid)
returns jsonb language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; ex sav_ai_crm.workflow_executions;
begin
 me:=sav_ai_crm.workflow_current_member();
 if me.id is null or me.role='viewer' then raise exception 'Workflow resume not permitted'; end if;
 select * into ex from sav_ai_crm.workflow_executions where id=p_execution_id and workspace_id=me.workspace_id;
 if ex.id is null then raise exception 'Workflow execution not found'; end if;
 if ex.scheduled_for is not null and ex.scheduled_for>now() then
   return jsonb_build_object('id',ex.id,'status',case when ex.execution_state='waiting' then 'waiting' else 'retrying' end,'scheduled_for',ex.scheduled_for);
 end if;
 if ex.execution_state not in ('waiting','queued','failed') then raise exception 'Workflow execution is not resumable'; end if;
 if ex.execution_state='failed' and ex.retry_count>ex.max_retries then raise exception 'Workflow retry limit exceeded'; end if;
 if ex.execution_state='failed' then
   update sav_ai_crm.workflow_executions set execution_state='queued',scheduled_for=now()+make_interval(secs=>retry_delay_seconds),updated_at=now() where id=ex.id;
   select * into ex from sav_ai_crm.workflow_executions where id=ex.id;
   if ex.scheduled_for>now() then return jsonb_build_object('id',ex.id,'status','retrying','scheduled_for',ex.scheduled_for); end if;
 end if;
 update sav_ai_crm.workflow_executions set execution_state='queued',scheduled_for=null,updated_at=now() where id=ex.id;
 return public.sav_ai_crm_run_workflow_execution(ex.id);
end $$;

create or replace function public.sav_ai_crm_workflow_executions(p_workflow_id uuid default null)
returns jsonb language plpgsql stable security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members;
begin
 me:=sav_ai_crm.workflow_current_member();
 if me.id is null then raise exception 'CRM membership required'; end if;
 return coalesce((select jsonb_agg(to_jsonb(x) order by x.updated_at desc) from (
  select e.*,w.name workflow_name
  from sav_ai_crm.workflow_executions e join sav_ai_crm.workflows w on w.id=e.workflow_id
  where e.workspace_id=me.workspace_id and (p_workflow_id is null or e.workflow_id=p_workflow_id)
  order by e.updated_at desc limit 200
 )x),'[]'::jsonb);
end $$;

create or replace function public.sav_ai_crm_workflow_execution_detail(p_execution_id uuid)
returns jsonb language plpgsql stable security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; ex sav_ai_crm.workflow_executions;
begin
 me:=sav_ai_crm.workflow_current_member();
 if me.id is null then raise exception 'CRM membership required'; end if;
 select * into ex from sav_ai_crm.workflow_executions where id=p_execution_id and workspace_id=me.workspace_id;
 if ex.id is null then raise exception 'Workflow execution not found'; end if;
 return jsonb_build_object(
  'execution',to_jsonb(ex),
  'nodes',coalesce((select jsonb_agg(jsonb_build_object(
    'id',ne.id,'node_id',ne.node_id,'node_execution_id',ne.node_execution_id,'status',ne.status,'input',ne.input,'output',ne.output,
    'risk_level',ne.risk_level,'approval_required',ne.approval_required,'retry_count',ne.retry_count,'last_error',ne.last_error,
    'started_at',ne.started_at,'completed_at',ne.completed_at,'node_label',n.label,'node_type',n.node_type
  ) order by ne.started_at) from sav_ai_crm.workflow_node_executions ne join sav_ai_crm.workflow_nodes n on n.id=ne.node_id where ne.execution_id=ex.id),'[]'::jsonb),
  'approvals',coalesce((select jsonb_agg(to_jsonb(a) order by a.requested_at) from sav_ai_crm.workflow_approvals a where a.execution_id=ex.id),'[]'::jsonb)
 );
end $$;

create or replace function public.sav_ai_crm_review_workflow_approval(p_approval_id uuid,p_decision text,p_reason text default null)
returns jsonb language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; a sav_ai_crm.workflow_approvals; ex sav_ai_crm.workflow_executions; agent_action_id uuid;
begin
 me:=sav_ai_crm.workflow_current_member();
 if me.id is null or not sav_ai_crm.workflow_can_manage(me.role) then raise exception 'Workflow approval review not permitted'; end if;
 if p_decision not in ('approved','rejected') then raise exception 'Invalid approval decision'; end if;
 select * into a from sav_ai_crm.workflow_approvals where id=p_approval_id and workspace_id=me.workspace_id and status='pending';
 if a.id is null then raise exception 'Pending workflow approval not found'; end if;
 if a.approver_role is not null and me.role<>a.approver_role and me.role not in ('owner','admin') then raise exception 'Approver role mismatch'; end if;
 if a.approver_user_id is not null and me.id<>a.approver_user_id and me.role not in ('owner','admin') then raise exception 'Approver user mismatch'; end if;
 update sav_ai_crm.workflow_approvals set status=p_decision,reviewed_by=me.id,approval_reason=concat_ws(E'\n',approval_reason,p_reason),reviewed_at=now() where id=a.id;
 select * into ex from sav_ai_crm.workflow_executions where id=a.execution_id and workspace_id=me.workspace_id;
 agent_action_id:=nullif(a.metadata->>'agent_action_id','')::uuid;
 if p_decision='rejected' then
   if agent_action_id is not null then perform public.sav_ai_crm_review_agent_action(agent_action_id,'rejected',p_reason); end if;
   update sav_ai_crm.workflow_executions set execution_state='cancelled',error='APPROVAL_REJECTED',completed_at=now(),updated_at=now() where id=ex.id;
   return jsonb_build_object('execution_id',ex.id,'status','cancelled');
 end if;
 if agent_action_id is not null then
   perform public.sav_ai_crm_review_agent_action(agent_action_id,'approved',p_reason);
   perform public.sav_ai_crm_execute_agent_action(agent_action_id);
 end if;
 update sav_ai_crm.workflow_executions set execution_state='queued',updated_at=now() where id=ex.id;
 return public.sav_ai_crm_run_workflow_execution(ex.id);
end $$;

-- Templates ------------------------------------------------------------------
with template_data(template_key,name,description,trigger_type,definition) as (
 values
 ('new-lead-qualification','New Lead Qualification','Qualify a new lead with SAV-Sales and create a follow-up task.','NEW_LEAD',
  '{"nodes":[{"id":"trigger","type":"TRIGGER","label":"New Lead","position":{"x":80,"y":120},"config":{"conditions":[]}},{"id":"agent","type":"AI_AGENT","label":"SAV-Sales Qualification","position":{"x":300,"y":120},"config":{"agent_slug":"sav-sales","action":"CREATE_TASK","target_type":"lead","target_id_path":"lead.id","payload":{"title":"Qualify new lead"}}},{"id":"end","type":"END","label":"End","position":{"x":540,"y":120},"config":{}}],"edges":[{"id":"e1","source":"trigger","target":"agent"},{"id":"e2","source":"agent","target":"end"}]}'::jsonb),
 ('new-website-lead','New Website Lead','Route website leads into a qualification task.','NEW_LEAD',
  '{"nodes":[{"id":"trigger","type":"TRIGGER","label":"Website Lead","position":{"x":80,"y":120},"config":{"conditions":[{"field":"lead.source","operator":"equals","value":"website"}]}},{"id":"task","type":"TASK","label":"Create Website Lead Task","position":{"x":320,"y":120},"config":{"lead_id_path":"lead.id","title":"Website lead qualification","priority":"high"}},{"id":"end","type":"END","label":"End","position":{"x":560,"y":120},"config":{}}],"edges":[{"id":"e1","source":"trigger","target":"task"},{"id":"e2","source":"task","target":"end"}]}'::jsonb),
 ('no-response-followup','No Response Follow-up','Wait and create a controlled follow-up.','FOLLOWUP_DUE',
  '{"nodes":[{"id":"trigger","type":"TRIGGER","label":"Follow-up Due","position":{"x":60,"y":120},"config":{"conditions":[]}},{"id":"wait","type":"WAIT","label":"Wait 24 Hours","position":{"x":260,"y":120},"config":{"delay_seconds":86400}},{"id":"follow","type":"FOLLOW_UP","label":"Create Follow-up","position":{"x":470,"y":120},"config":{"lead_id_path":"lead.id","title":"No-response follow-up","priority":"medium"}},{"id":"end","type":"END","label":"End","position":{"x":690,"y":120},"config":{}}],"edges":[{"id":"e1","source":"trigger","target":"wait"},{"id":"e2","source":"wait","target":"follow"},{"id":"e3","source":"follow","target":"end"}]}'::jsonb),
 ('document-collection','Document Collection','Create document collection work for SAV-Document.','LEAD_STATUS_CHANGED',
  '{"nodes":[{"id":"trigger","type":"TRIGGER","label":"Lead Status Changed","position":{"x":60,"y":120},"config":{"conditions":[]}},{"id":"agent","type":"AI_AGENT","label":"SAV-Document","position":{"x":280,"y":120},"config":{"agent_slug":"sav-document","action":"CREATE_TASK","target_type":"lead","target_id_path":"lead.id","payload":{"title":"Collect missing documents"}}},{"id":"end","type":"END","label":"End","position":{"x":520,"y":120},"config":{}}],"edges":[{"id":"e1","source":"trigger","target":"agent"},{"id":"e2","source":"agent","target":"end"}]}'::jsonb),
 ('high-value-lead-escalation','High Value Lead Escalation','Escalate leads over the configured threshold.','NEW_LEAD',
  '{"nodes":[{"id":"trigger","type":"TRIGGER","label":"New Lead","position":{"x":60,"y":120},"config":{"conditions":[]}},{"id":"condition","type":"CONDITION","label":"Value > 500000","position":{"x":260,"y":120},"config":{"condition":{"field":"lead.value","operator":"greater_than","value":500000}}},{"id":"approval","type":"HUMAN_APPROVAL","label":"Manager Approval","position":{"x":480,"y":80},"config":{"approver_role":"manager","reason":"High value lead","risk_level":"high"}},{"id":"end","type":"END","label":"End","position":{"x":700,"y":120},"config":{}}],"edges":[{"id":"e1","source":"trigger","target":"condition"},{"id":"e2","source":"condition","target":"approval","branch":"true"},{"id":"e3","source":"condition","target":"end","branch":"false"},{"id":"e4","source":"approval","target":"end","branch":"approved"}]}'::jsonb),
 ('customer-support-escalation','Customer Support Escalation','Escalate support conversations requiring a human.','CONVERSATION_RECEIVED',
  '{"nodes":[{"id":"trigger","type":"TRIGGER","label":"Conversation Received","position":{"x":60,"y":120},"config":{"conditions":[]}},{"id":"escalate","type":"ESCALATION","label":"Support Escalation","position":{"x":300,"y":120},"config":{"agent_slug":"sav-support","reason":"CUSTOMER_REQUESTED_HUMAN","lead_id_path":"lead.id"}},{"id":"end","type":"END","label":"End","position":{"x":540,"y":120},"config":{}}],"edges":[{"id":"e1","source":"trigger","target":"escalate"},{"id":"e2","source":"escalate","target":"end"}]}'::jsonb),
 ('task-reminder','Task Reminder','Persist a wait and reminder follow-up.','REMINDER_DUE',
  '{"nodes":[{"id":"trigger","type":"TRIGGER","label":"Reminder Due","position":{"x":60,"y":120},"config":{"conditions":[]}},{"id":"follow","type":"FOLLOW_UP","label":"Reminder Follow-up","position":{"x":300,"y":120},"config":{"lead_id_path":"lead.id","title":"Task reminder follow-up"}},{"id":"end","type":"END","label":"End","position":{"x":540,"y":120},"config":{}}],"edges":[{"id":"e1","source":"trigger","target":"follow"},{"id":"e2","source":"follow","target":"end"}]}'::jsonb),
 ('ai-human-handoff','AI-to-Human Handoff','Pause AI work for explicit human approval.','AI_ESCALATION',
  '{"nodes":[{"id":"trigger","type":"TRIGGER","label":"AI Escalation","position":{"x":60,"y":120},"config":{"conditions":[]}},{"id":"approval","type":"HUMAN_APPROVAL","label":"Human Review","position":{"x":300,"y":120},"config":{"approver_role":"manager","reason":"AI-to-human handoff","risk_level":"high"}},{"id":"end","type":"END","label":"End","position":{"x":540,"y":120},"config":{}}],"edges":[{"id":"e1","source":"trigger","target":"approval"},{"id":"e2","source":"approval","target":"end","branch":"approved"}]}'::jsonb)
)
insert into sav_ai_crm.workflow_templates(workspace_id,template_key,name,description,trigger_type,definition)
select w.id,t.template_key,t.name,t.description,t.trigger_type,t.definition from sav_ai_crm.workspaces w cross join template_data t
on conflict(workspace_id,template_key) do update set name=excluded.name,description=excluded.description,trigger_type=excluded.trigger_type,definition=excluded.definition,updated_at=now();

-- Grants ---------------------------------------------------------------------
revoke all on function public.sav_ai_crm_workflow_registry() from public,anon;
revoke all on function public.sav_ai_crm_workflow_metrics() from public,anon;
revoke all on function public.sav_ai_crm_workflow_templates() from public,anon;
revoke all on function public.sav_ai_crm_create_workflow(text,text,text,jsonb,uuid) from public,anon;
revoke all on function public.sav_ai_crm_update_workflow(uuid,text,text,text,jsonb) from public,anon;
revoke all on function public.sav_ai_crm_workflow_detail(uuid) from public,anon;
revoke all on function public.sav_ai_crm_set_workflow_status(uuid,text) from public,anon;
revoke all on function public.sav_ai_crm_duplicate_workflow(uuid) from public,anon;
revoke all on function public.sav_ai_crm_archive_workflow(uuid) from public,anon;
revoke all on function public.sav_ai_crm_dispatch_workflow_event(text,jsonb,text) from public,anon;
revoke all on function public.sav_ai_crm_test_workflow(uuid,jsonb) from public,anon;
revoke all on function public.sav_ai_crm_start_workflow(uuid,jsonb,text,text) from public,anon;
revoke all on function public.sav_ai_crm_run_workflow_execution(uuid) from public,anon;
revoke all on function public.sav_ai_crm_resume_workflow_execution(uuid) from public,anon;
revoke all on function public.sav_ai_crm_workflow_executions(uuid) from public,anon;
revoke all on function public.sav_ai_crm_workflow_execution_detail(uuid) from public,anon;
revoke all on function public.sav_ai_crm_review_workflow_approval(uuid,text,text) from public,anon;

grant execute on function public.sav_ai_crm_workflow_registry() to authenticated;
grant execute on function public.sav_ai_crm_workflow_metrics() to authenticated;
grant execute on function public.sav_ai_crm_workflow_templates() to authenticated;
grant execute on function public.sav_ai_crm_create_workflow(text,text,text,jsonb,uuid) to authenticated;
grant execute on function public.sav_ai_crm_update_workflow(uuid,text,text,text,jsonb) to authenticated;
grant execute on function public.sav_ai_crm_workflow_detail(uuid) to authenticated;
grant execute on function public.sav_ai_crm_set_workflow_status(uuid,text) to authenticated;
grant execute on function public.sav_ai_crm_duplicate_workflow(uuid) to authenticated;
grant execute on function public.sav_ai_crm_archive_workflow(uuid) to authenticated;
grant execute on function public.sav_ai_crm_dispatch_workflow_event(text,jsonb,text) to authenticated;
grant execute on function public.sav_ai_crm_test_workflow(uuid,jsonb) to authenticated;
grant execute on function public.sav_ai_crm_start_workflow(uuid,jsonb,text,text) to authenticated;
grant execute on function public.sav_ai_crm_run_workflow_execution(uuid) to authenticated;
grant execute on function public.sav_ai_crm_resume_workflow_execution(uuid) to authenticated;
grant execute on function public.sav_ai_crm_workflow_executions(uuid) to authenticated;
grant execute on function public.sav_ai_crm_workflow_execution_detail(uuid) to authenticated;
grant execute on function public.sav_ai_crm_review_workflow_approval(uuid,text,text) to authenticated;

commit;
