-- SAVRDH Intelligence Workforce - Phase 5 Notifications
-- SOURCE ONLY. DO NOT APPLY TO PRODUCTION AUTOMATICALLY.
begin;

create table if not exists sav_ai_crm.notifications(
 id uuid primary key default gen_random_uuid(),
 workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
 recipient_member_id uuid references sav_ai_crm.members(id) on delete set null,
 recipient_address text,
 notification_type text not null,
 title text not null,
 body text not null,
 priority text not null default 'medium' check(priority in ('low','medium','high','urgent','critical')),
 channel text not null check(channel in ('in_app','email','whatsapp','sms','push','webhook')),
 status text not null default 'QUEUED' check(status in ('QUEUED','SCHEDULED','SENDING','SENT','DELIVERED','READ','FAILED','CANCELLED','WAITING_APPROVAL','RETRYING')),
 source_type text not null default 'system',
 source_id uuid,
 deep_link text,
 lead_id uuid references sav_ai_crm.leads(id) on delete set null,
 contact_id uuid references sav_ai_crm.contacts(id) on delete set null,
 task_id uuid references sav_ai_crm.tasks(id) on delete set null,
 workflow_id uuid references sav_ai_crm.workflows(id) on delete set null,
 workflow_execution_id uuid references sav_ai_crm.workflow_executions(id) on delete set null,
 conversation_id uuid references sav_ai_crm.conversations(id) on delete set null,
 agent_id uuid references sav_ai_crm.ai_agents(id) on delete set null,
 scheduled_at timestamptz,
 next_attempt_at timestamptz,
 retry_count integer not null default 0 check(retry_count>=0),
 max_retries integer not null default 3 check(max_retries between 0 and 20),
 sent_at timestamptz,
 delivered_at timestamptz,
 read_at timestamptz,
 failed_at timestamptz,
 error_code text,
 error_message text,
 metadata jsonb not null default '{}'::jsonb,
 idempotency_key text not null,
 created_by uuid references sav_ai_crm.members(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(workspace_id,idempotency_key)
);

create table if not exists sav_ai_crm.notification_recipients(
 id uuid primary key default gen_random_uuid(),
 workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
 notification_id uuid not null references sav_ai_crm.notifications(id) on delete cascade,
 member_id uuid references sav_ai_crm.members(id) on delete cascade,
 external_address text,
 channel text not null check(channel in ('in_app','email','whatsapp','sms','push','webhook')),
 delivery_enabled boolean not null default true,
 created_at timestamptz not null default now(),
 check(member_id is not null or external_address is not null),
 unique(notification_id,member_id,channel)
);

create table if not exists sav_ai_crm.notification_deliveries(
 id uuid primary key default gen_random_uuid(),
 workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
 notification_id uuid not null references sav_ai_crm.notifications(id) on delete cascade,
 channel text not null check(channel in ('in_app','email','whatsapp','sms','push','webhook')),
 status text not null check(status in ('QUEUED','SCHEDULED','SENDING','SENT','DELIVERED','READ','FAILED','CANCELLED','WAITING_APPROVAL','RETRYING')),
 provider text,
 provider_message_id text,
 attempt_number integer not null default 1 check(attempt_number>0),
 error_code text,
 error_message text,
 raw_metadata jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table if not exists sav_ai_crm.notification_preferences(
 id uuid primary key default gen_random_uuid(),
 workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
 member_id uuid not null references sav_ai_crm.members(id) on delete cascade,
 category text not null,
 enabled boolean not null default true,
 preferred_channel text not null default 'in_app' check(preferred_channel in ('in_app','email','whatsapp','sms','push','webhook')),
 quiet_hours_start time,
 quiet_hours_end time,
 digest_frequency text not null default 'none' check(digest_frequency in ('none','daily','weekly')),
 metadata jsonb not null default '{}'::jsonb,
 updated_at timestamptz not null default now(),
 unique(workspace_id,member_id,category)
);

create table if not exists sav_ai_crm.notification_templates(
 id uuid primary key default gen_random_uuid(),
 workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
 name text not null,
 notification_type text not null,
 channel text not null check(channel in ('in_app','email','whatsapp','sms','push','webhook')),
 subject text,
 body text not null,
 variables text[] not null default '{}'::text[],
 is_active boolean not null default true,
 version integer not null default 1 check(version>0),
 created_by uuid references sav_ai_crm.members(id) on delete set null,
 updated_by uuid references sav_ai_crm.members(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(workspace_id,name,version)
);

create table if not exists sav_ai_crm.notification_events(
 id uuid primary key default gen_random_uuid(),
 workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
 notification_id uuid references sav_ai_crm.notifications(id) on delete cascade,
 event_type text not null,
 actor_member_id uuid references sav_ai_crm.members(id) on delete set null,
 actor_agent_id uuid references sav_ai_crm.ai_agents(id) on delete set null,
 details jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);

create table if not exists sav_ai_crm.notification_schedules(
 id uuid primary key default gen_random_uuid(),
 workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
 notification_type text not null,
 channel text not null check(channel in ('in_app','email','whatsapp','sms','push','webhook')),
 recipient_member_id uuid references sav_ai_crm.members(id) on delete cascade,
 recipient_address text,
 title text not null,
 body text not null,
 priority text not null default 'medium' check(priority in ('low','medium','high','urgent','critical')),
 scheduled_at timestamptz not null,
 next_run_at timestamptz,
 recurrence_rule text,
 status text not null default 'active' check(status in ('active','paused','cancelled','completed')),
 source_type text not null default 'schedule',
 source_id uuid,
 deep_link text,
 metadata jsonb not null default '{}'::jsonb,
 idempotency_prefix text not null,
 created_by uuid references sav_ai_crm.members(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table if not exists sav_ai_crm.notification_digests(
 id uuid primary key default gen_random_uuid(),
 workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
 member_id uuid not null references sav_ai_crm.members(id) on delete cascade,
 digest_type text not null check(digest_type in ('daily','task','lead','ai_activity','workflow')),
 enabled boolean not null default false,
 preferred_channel text not null default 'in_app' check(preferred_channel in ('in_app','email','whatsapp','sms','push','webhook')),
 schedule_expression text,
 next_run_at timestamptz,
 updated_at timestamptz not null default now(),
 unique(workspace_id,member_id,digest_type)
);

create table if not exists sav_ai_crm.notification_devices(
 id uuid primary key default gen_random_uuid(),
 workspace_id uuid not null references sav_ai_crm.workspaces(id) on delete cascade,
 member_id uuid not null references sav_ai_crm.members(id) on delete cascade,
 device_token_hash text not null,
 encrypted_device_ref text not null,
 platform text not null,
 status text not null default 'active' check(status in ('active','revoked','error')),
 metadata jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(workspace_id,member_id,device_token_hash)
);

create index if not exists notifications_workspace_recipient_idx on sav_ai_crm.notifications(workspace_id,recipient_member_id,created_at desc);
create index if not exists notifications_workspace_status_idx on sav_ai_crm.notifications(workspace_id,status,created_at desc);
create index if not exists notifications_schedule_idx on sav_ai_crm.notifications(workspace_id,scheduled_at,next_attempt_at) where status in ('SCHEDULED','RETRYING');
create index if not exists notifications_source_idx on sav_ai_crm.notifications(workspace_id,source_type,source_id);
create index if not exists notification_delivery_notification_idx on sav_ai_crm.notification_deliveries(notification_id,created_at desc);
create index if not exists notification_events_notification_idx on sav_ai_crm.notification_events(notification_id,created_at desc);
create index if not exists notification_schedules_next_run_idx on sav_ai_crm.notification_schedules(workspace_id,next_run_at) where status='active';

alter table sav_ai_crm.notifications enable row level security;
alter table sav_ai_crm.notification_recipients enable row level security;
alter table sav_ai_crm.notification_deliveries enable row level security;
alter table sav_ai_crm.notification_preferences enable row level security;
alter table sav_ai_crm.notification_templates enable row level security;
alter table sav_ai_crm.notification_events enable row level security;
alter table sav_ai_crm.notification_schedules enable row level security;
alter table sav_ai_crm.notification_digests enable row level security;
alter table sav_ai_crm.notification_devices enable row level security;

create or replace function sav_ai_crm.notification_current_member()
returns sav_ai_crm.members language sql stable security definer
set search_path=public,sav_ai_crm
as $$ select m from sav_ai_crm.members m where m.user_id=auth.uid() and m.is_active=true order by m.created_at limit 1 $$;
revoke all on function sav_ai_crm.notification_current_member() from public,anon;
grant execute on function sav_ai_crm.notification_current_member() to authenticated;

create or replace function sav_ai_crm.notification_can_manage(p_role text)
returns boolean language sql immutable as $$ select p_role in ('owner','admin','manager') $$;
create or replace function sav_ai_crm.notification_can_create(p_role text)
returns boolean language sql immutable as $$ select p_role in ('owner','admin','manager','sales','support','operations') $$;
revoke all on function sav_ai_crm.notification_can_manage(text) from public,anon,authenticated;
revoke all on function sav_ai_crm.notification_can_create(text) from public,anon,authenticated;

do $$
declare t text;
begin
 foreach t in array array['notifications','notification_recipients','notification_deliveries','notification_preferences','notification_templates','notification_events','notification_schedules','notification_digests','notification_devices'] loop
  execute format('drop policy if exists "notification read %1$s" on sav_ai_crm.%1$I',t);
  execute format('create policy "notification read %1$s" on sav_ai_crm.%1$I for select to authenticated using (sav_ai_crm.is_workspace_member(workspace_id))',t);
 end loop;
end $$;

-- No direct authenticated writes to notification tables.
do $$
declare t text;
begin
 foreach t in array array['notifications','notification_recipients','notification_deliveries','notification_preferences','notification_templates','notification_events','notification_schedules','notification_digests','notification_devices'] loop
  execute format('drop policy if exists "notification insert %1$s" on sav_ai_crm.%1$I',t);
  execute format('drop policy if exists "notification update %1$s" on sav_ai_crm.%1$I',t);
  execute format('drop policy if exists "notification delete %1$s" on sav_ai_crm.%1$I',t);
  execute format('create policy "notification deny insert %1$s" on sav_ai_crm.%1$I for insert to authenticated with check(false)',t);
  execute format('create policy "notification deny update %1$s" on sav_ai_crm.%1$I for update to authenticated using(false) with check(false)',t);
  execute format('create policy "notification deny delete %1$s" on sav_ai_crm.%1$I for delete to authenticated using(false)',t);
 end loop;
end $$;

create or replace function sav_ai_crm.notification_category_for_type(p_type text)
returns text language sql immutable as $
 select case
  when p_type in ('TASK_NOTIFICATION','TASK_REMINDER','OVERDUE_REMINDER') then 'task_reminders'
  when p_type in ('FOLLOWUP_NOTIFICATION','FOLLOWUP_REMINDER') then 'followups'
  when p_type like 'AI_%' then 'ai_alerts'
  when p_type like 'WORKFLOW_%' then 'workflow_alerts'
  when p_type in ('NEW_CONVERSATION','NEW_INBOUND_MESSAGE','MESSAGE_DELIVERY_UPDATE','CONVERSATION_ASSIGNMENT') then 'inbox_alerts'
  when p_type in ('ESCALATION_NOTIFICATION','CONVERSATION_ESCALATION') then 'escalation_alerts'
  when p_type='SECURITY_NOTIFICATION' then 'system_security'
  else 'system_alerts' end
$;
revoke all on function sav_ai_crm.notification_category_for_type(text) from public,anon,authenticated;

create or replace function public.sav_ai_crm_notification_context()
returns jsonb language plpgsql stable security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members;
begin
 me:=sav_ai_crm.notification_current_member();
 if me.id is null then raise exception 'CRM membership required'; end if;
 return jsonb_build_object(
  'member',jsonb_build_object('id',me.id,'role',me.role,'full_name',me.full_name,'email',me.email),
  'members',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'full_name',m.full_name,'email',m.email,'role',m.role) order by coalesce(m.full_name,m.email)) from sav_ai_crm.members m where m.workspace_id=me.workspace_id and m.is_active),'[]'::jsonb),
  'agents',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'display_name',a.display_name,'name',a.name,'status',a.status,'capabilities',a.capabilities) order by a.display_name) from sav_ai_crm.ai_agents a where a.workspace_id=me.workspace_id),'[]'::jsonb),
  'workflows',coalesce((select jsonb_agg(jsonb_build_object('id',w.id,'name',w.name,'status',w.status) order by w.name) from sav_ai_crm.workflows w where w.workspace_id=me.workspace_id and w.archived_at is null),'[]'::jsonb),
  'permissions',jsonb_build_object('manage',sav_ai_crm.notification_can_manage(me.role),'create',sav_ai_crm.notification_can_create(me.role),'templates',me.role in ('owner','admin'),'channels',me.role in ('owner','admin'),'read_only',me.role='viewer')
 );
end $$;

create or replace function public.sav_ai_crm_notifications(
 p_search text default null,p_channel text default null,p_type text default null,p_status text default null,p_priority text default null,
 p_recipient uuid default null,p_source text default null,p_agent uuid default null,p_workflow uuid default null,p_read_state text default null,
 p_date_from timestamptz default null,p_date_to timestamptz default null
) returns jsonb language plpgsql stable security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; is_manager boolean;
begin
 me:=sav_ai_crm.notification_current_member(); if me.id is null then raise exception 'CRM membership required'; end if;
 is_manager:=sav_ai_crm.notification_can_manage(me.role) or me.role='viewer';
 return coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (
  select n.*,
    coalesce(m.full_name,m.email,n.recipient_address) recipient_name,
    coalesce(a.display_name,a.name) agent_name,
    w.name workflow_name
  from sav_ai_crm.notifications n
  left join sav_ai_crm.members m on m.id=n.recipient_member_id
  left join sav_ai_crm.ai_agents a on a.id=n.agent_id
  left join sav_ai_crm.workflows w on w.id=n.workflow_id
  where n.workspace_id=me.workspace_id
    and (is_manager or n.recipient_member_id=me.id or n.created_by=me.id)
    and (p_search is null or n.title ilike '%'||p_search||'%' or n.body ilike '%'||p_search||'%')
    and (p_channel is null or n.channel=p_channel)
    and (p_type is null or n.notification_type=p_type)
    and (p_status is null or n.status=p_status)
    and (p_priority is null or n.priority=p_priority)
    and (p_recipient is null or n.recipient_member_id=p_recipient)
    and (p_source is null or n.source_type=p_source)
    and (p_agent is null or n.agent_id=p_agent)
    and (p_workflow is null or n.workflow_id=p_workflow)
    and (p_read_state is null or (p_read_state='read' and n.read_at is not null) or (p_read_state='unread' and n.read_at is null))
    and (p_date_from is null or n.created_at>=p_date_from)
    and (p_date_to is null or n.created_at<=p_date_to)
  limit 500
 )x),'[]'::jsonb);
end $$;

create or replace function public.sav_ai_crm_notification_metrics()
returns jsonb language plpgsql stable security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; is_manager boolean;
begin
 me:=sav_ai_crm.notification_current_member(); if me.id is null then raise exception 'CRM membership required'; end if;
 is_manager:=sav_ai_crm.notification_can_manage(me.role) or me.role='viewer';
 return (select jsonb_build_object(
  'total',count(*),'unread',count(*) filter(where read_at is null),'read',count(*) filter(where read_at is not null),
  'scheduled',count(*) filter(where status='SCHEDULED'),'sent',count(*) filter(where status='SENT'),
  'delivered',count(*) filter(where status='DELIVERED'),'failed',count(*) filter(where status='FAILED'),
  'cancelled',count(*) filter(where status='CANCELLED'),'pending_approval',count(*) filter(where status='WAITING_APPROVAL')
 ) from sav_ai_crm.notifications n where n.workspace_id=me.workspace_id and (is_manager or n.recipient_member_id=me.id or n.created_by=me.id));
end $$;

create or replace function public.sav_ai_crm_notification_upcoming()
returns jsonb language plpgsql stable security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; is_manager boolean;
begin
 me:=sav_ai_crm.notification_current_member(); if me.id is null then raise exception 'CRM membership required'; end if;
 is_manager:=sav_ai_crm.notification_can_manage(me.role) or me.role='viewer';
 return coalesce((select jsonb_agg(to_jsonb(x) order by x.scheduled_at) from (
  select * from sav_ai_crm.notifications n where n.workspace_id=me.workspace_id and n.status='SCHEDULED' and n.scheduled_at>=now()
    and (is_manager or n.recipient_member_id=me.id or n.created_by=me.id) order by n.scheduled_at limit 50
 )x),'[]'::jsonb);
end $$;

create or replace function public.sav_ai_crm_notification_detail(p_notification_id uuid)
returns jsonb language plpgsql stable security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; n sav_ai_crm.notifications;
begin
 me:=sav_ai_crm.notification_current_member(); if me.id is null then raise exception 'CRM membership required'; end if;
 select * into n from sav_ai_crm.notifications where id=p_notification_id and workspace_id=me.workspace_id
   and (sav_ai_crm.notification_can_manage(me.role) or me.role='viewer' or recipient_member_id=me.id or created_by=me.id);
 if n.id is null then raise exception 'Notification not found'; end if;
 return jsonb_build_object(
  'notification',to_jsonb(n),
  'deliveries',coalesce((select jsonb_agg(to_jsonb(d) order by d.created_at) from sav_ai_crm.notification_deliveries d where d.notification_id=n.id),'[]'::jsonb),
  'events',coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at) from sav_ai_crm.notification_events e where e.notification_id=n.id),'[]'::jsonb)
 );
end $$;

create or replace function public.sav_ai_crm_create_notification(
 p_notification_type text,p_title text,p_body text,p_priority text,p_channel text,p_recipient_member_id uuid,
 p_recipient_address text,p_source_type text,p_source_id uuid,p_deep_link text,p_scheduled_at timestamptz,p_agent_id uuid,
 p_lead_id uuid,p_contact_id uuid,p_task_id uuid,p_workflow_id uuid,p_workflow_execution_id uuid,p_conversation_id uuid,
 p_metadata jsonb,p_idempotency_key text,p_requires_approval boolean default false
) returns uuid language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; nid uuid; initial_status text;
begin
 me:=sav_ai_crm.notification_current_member();
 if me.id is null or not sav_ai_crm.notification_can_create(me.role) then raise exception 'Notification creation not permitted'; end if;
 if p_channel not in ('in_app','email','whatsapp','sms','push','webhook') then raise exception 'Invalid notification channel'; end if;
 if p_priority not in ('low','medium','high','urgent','critical') then raise exception 'Invalid priority'; end if;
 if p_recipient_member_id is not null and not exists(select 1 from sav_ai_crm.members where id=p_recipient_member_id and workspace_id=me.workspace_id and is_active) then raise exception 'Recipient outside workspace'; end if;
 if p_recipient_member_id is null and nullif(trim(coalesce(p_recipient_address,'')),'') is not null and me.role not in ('owner','admin') then raise exception 'External recipient requires owner or admin'; end if;
 if p_recipient_member_id is not null and p_channel='email' and nullif(trim(coalesce(p_recipient_address,'')),'') is null then
   select email into p_recipient_address from sav_ai_crm.members where id=p_recipient_member_id and workspace_id=me.workspace_id;
 end if;
 if p_agent_id is not null and not exists(select 1 from sav_ai_crm.ai_agents where id=p_agent_id and workspace_id=me.workspace_id and status='active') then raise exception 'AI agent outside workspace'; end if;
 if p_workflow_id is not null and not exists(select 1 from sav_ai_crm.workflows where id=p_workflow_id and workspace_id=me.workspace_id) then raise exception 'Workflow outside workspace'; end if;
 if p_conversation_id is not null and not exists(select 1 from sav_ai_crm.conversations where id=p_conversation_id and workspace_id=me.workspace_id) then raise exception 'Conversation outside workspace'; end if;
 if p_task_id is not null and not exists(select 1 from sav_ai_crm.tasks where id=p_task_id and workspace_id=me.workspace_id) then raise exception 'Task outside workspace'; end if;
 if coalesce(trim(p_title),'')='' or coalesce(trim(p_body),'')='' then raise exception 'Notification title and body required'; end if;
 if p_recipient_member_id is not null and p_notification_type<>'SECURITY_NOTIFICATION' and exists(
   select 1 from sav_ai_crm.notification_preferences pref
   where pref.workspace_id=me.workspace_id and pref.member_id=p_recipient_member_id
     and pref.category=sav_ai_crm.notification_category_for_type(p_notification_type) and pref.enabled=false
 ) then raise exception 'NOTIFICATION_DISABLED_BY_PREFERENCE'; end if;

 initial_status:=case when p_requires_approval then 'WAITING_APPROVAL' when p_scheduled_at is not null and p_scheduled_at>now() then 'SCHEDULED' else 'QUEUED' end;
 begin
  insert into sav_ai_crm.notifications(workspace_id,recipient_member_id,recipient_address,notification_type,title,body,priority,channel,status,source_type,source_id,deep_link,
    lead_id,contact_id,task_id,workflow_id,workflow_execution_id,conversation_id,agent_id,scheduled_at,next_attempt_at,metadata,idempotency_key,created_by)
  values(me.workspace_id,p_recipient_member_id,nullif(trim(coalesce(p_recipient_address,'')),''),p_notification_type,trim(p_title),p_body,p_priority,p_channel,initial_status,
    coalesce(nullif(trim(p_source_type),''),'manual'),p_source_id,p_deep_link,p_lead_id,p_contact_id,p_task_id,p_workflow_id,p_workflow_execution_id,p_conversation_id,p_agent_id,
    p_scheduled_at,case when initial_status='SCHEDULED' then p_scheduled_at else now() end,coalesce(p_metadata,'{}'),p_idempotency_key,me.id)
  returning id into nid;
 exception when unique_violation then
  select id into nid from sav_ai_crm.notifications where workspace_id=me.workspace_id and idempotency_key=p_idempotency_key;
  return nid;
 end;
 insert into sav_ai_crm.notification_recipients(workspace_id,notification_id,member_id,external_address,channel)
 values(me.workspace_id,nid,p_recipient_member_id,nullif(trim(coalesce(p_recipient_address,'')),''),p_channel);
 insert into sav_ai_crm.notification_deliveries(workspace_id,notification_id,channel,status,attempt_number)
 values(me.workspace_id,nid,p_channel,initial_status,1);
 insert into sav_ai_crm.notification_events(workspace_id,notification_id,event_type,actor_member_id,details)
 values(me.workspace_id,nid,'notification_created',me.id,jsonb_build_object('status',initial_status,'source_type',p_source_type));
 insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id,metadata)
 values(me.workspace_id,auth.uid(),'notification.created','notification',nid,jsonb_build_object('channel',p_channel,'status',initial_status));
 return nid;
end $$;

create or replace function public.sav_ai_crm_update_notification(
 p_notification_id uuid,p_title text default null,p_body text default null,p_priority text default null,p_scheduled_at timestamptz default null,p_metadata jsonb default null
) returns void language plpgsql security definer
set search_path=public,sav_ai_crm
as $
declare me sav_ai_crm.members; n sav_ai_crm.notifications;
begin
 me:=sav_ai_crm.notification_current_member(); if me.id is null or not sav_ai_crm.notification_can_create(me.role) then raise exception 'Notification update not permitted'; end if;
 select * into n from sav_ai_crm.notifications where id=p_notification_id and workspace_id=me.workspace_id for update;
 if n.id is null then raise exception 'Notification not found'; end if;
 if n.created_by<>me.id and not sav_ai_crm.notification_can_manage(me.role) then raise exception 'Notification update not permitted'; end if;
 if n.status not in ('QUEUED','SCHEDULED','WAITING_APPROVAL') then raise exception 'Notification can no longer be edited'; end if;
 if p_priority is not null and p_priority not in ('low','medium','high','urgent','critical') then raise exception 'Invalid priority'; end if;
 update sav_ai_crm.notifications set title=coalesce(nullif(trim(coalesce(p_title,'')),''),title),body=coalesce(p_body,body),
   priority=coalesce(p_priority,priority),scheduled_at=case when p_scheduled_at is not null then p_scheduled_at else scheduled_at end,
   status=case when p_scheduled_at is not null and p_scheduled_at>now() and status<>'WAITING_APPROVAL' then 'SCHEDULED' else status end,
   next_attempt_at=case when p_scheduled_at is not null then p_scheduled_at else next_attempt_at end,
   metadata=case when p_metadata is not null then p_metadata else metadata end,updated_at=now()
 where id=n.id;
 insert into sav_ai_crm.notification_events(workspace_id,notification_id,event_type,actor_member_id) values(me.workspace_id,n.id,'notification_updated',me.id);
 insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id) values(me.workspace_id,auth.uid(),'notification.updated','notification',n.id);
end $;

create or replace function public.sav_ai_crm_notification_due_ids(p_limit integer default 100)
returns jsonb language plpgsql stable security definer
set search_path=public,sav_ai_crm
as $
declare me sav_ai_crm.members;
begin
 me:=sav_ai_crm.notification_current_member(); if me.id is null or me.role not in ('owner','admin','manager') then raise exception 'Notification worker access not permitted'; end if;
 return coalesce((select jsonb_agg(id order by coalesce(next_attempt_at,scheduled_at,created_at)) from (
  select id,next_attempt_at,scheduled_at,created_at from sav_ai_crm.notifications
  where workspace_id=me.workspace_id and (
    status='QUEUED' or (status='SCHEDULED' and scheduled_at<=now()) or (status='RETRYING' and next_attempt_at<=now())
  ) order by coalesce(next_attempt_at,scheduled_at,created_at) limit least(greatest(p_limit,1),500)
 )x),'[]'::jsonb);
end $;

create or replace function public.sav_ai_crm_notification_prepare_send(p_notification_id uuid)
returns jsonb language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; n sav_ai_crm.notifications;
begin
 me:=sav_ai_crm.notification_current_member(); if me.id is null or not sav_ai_crm.notification_can_create(me.role) then raise exception 'Notification send not permitted'; end if;
 select * into n from sav_ai_crm.notifications where id=p_notification_id and workspace_id=me.workspace_id for update;
 if n.id is null then raise exception 'Notification not found'; end if;
 if n.status='WAITING_APPROVAL' then raise exception 'Notification requires approval'; end if;
 if n.status='SCHEDULED' and n.scheduled_at>now() then raise exception 'Notification is scheduled for later'; end if;
 if n.status not in ('QUEUED','FAILED','RETRYING','SCHEDULED') then raise exception 'Notification is not sendable'; end if;
 update sav_ai_crm.notifications set status='SENDING',error_code=null,error_message=null,updated_at=now() where id=n.id;
 update sav_ai_crm.notification_deliveries set status='SENDING',updated_at=now() where notification_id=n.id and attempt_number=(select max(attempt_number) from sav_ai_crm.notification_deliveries where notification_id=n.id);
 insert into sav_ai_crm.notification_events(workspace_id,notification_id,event_type,actor_member_id) values(me.workspace_id,n.id,'notification_sending',me.id);
 return jsonb_build_object('id',n.id,'workspace_id',n.workspace_id,'channel',n.channel,'notification_type',n.notification_type,'title',n.title,'body',n.body,'recipient_member_id',n.recipient_member_id,'recipient_address',n.recipient_address,'deep_link',n.deep_link,'conversation_id',n.conversation_id,'metadata',n.metadata,'retry_count',n.retry_count,'max_retries',n.max_retries);
end $$;

create or replace function public.sav_ai_crm_notification_record_result(
 p_notification_id uuid,p_ok boolean,p_provider text,p_provider_message_id text,p_status text,p_error_code text,p_error_message text,p_raw jsonb,p_retryable boolean default false
) returns void language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; n sav_ai_crm.notifications; final_status text; next_at timestamptz;
begin
 me:=sav_ai_crm.notification_current_member(); if me.id is null or not sav_ai_crm.notification_can_create(me.role) then raise exception 'Notification result not permitted'; end if;
 select * into n from sav_ai_crm.notifications where id=p_notification_id and workspace_id=me.workspace_id for update;
 if n.id is null then raise exception 'Notification not found'; end if;
 if p_ok and p_status not in ('SENT','DELIVERED','READ') then raise exception 'Invalid provider success status'; end if;
 if p_ok and coalesce(p_provider_message_id,'')='' and n.channel<>'in_app' then raise exception 'Provider message ID required'; end if;
 if p_ok then final_status:=p_status; next_at:=null;
 elsif p_retryable and n.retry_count<n.max_retries and coalesce(p_error_code,'') not in ('CHANNEL_PROVIDER_NOT_CONFIGURED','PUSH_PROVIDER_NOT_CONFIGURED','WEBHOOK_PROVIDER_NOT_CONFIGURED') then
   final_status:='RETRYING'; next_at:=now()+make_interval(secs=>least(3600,60*power(2,n.retry_count)::integer));
 else final_status:='FAILED'; next_at:=null; end if;

 update sav_ai_crm.notifications set status=final_status,retry_count=case when not p_ok then retry_count+1 else retry_count end,
   next_attempt_at=next_at,sent_at=case when p_ok and p_status in ('SENT','DELIVERED','READ') then coalesce(sent_at,now()) else sent_at end,
   delivered_at=case when p_ok and p_status in ('DELIVERED','READ') then coalesce(delivered_at,now()) else delivered_at end,
   read_at=case when p_ok and p_status='READ' then coalesce(read_at,now()) else read_at end,
   failed_at=case when final_status='FAILED' then now() else null end,error_code=case when p_ok then null else p_error_code end,error_message=case when p_ok then null else p_error_message end,updated_at=now()
 where id=n.id;

 update sav_ai_crm.notification_deliveries set status=final_status,provider=p_provider,provider_message_id=p_provider_message_id,error_code=case when p_ok then null else p_error_code end,
   error_message=case when p_ok then null else p_error_message end,raw_metadata=coalesce(p_raw,'{}'),updated_at=now()
 where notification_id=n.id and attempt_number=(select max(attempt_number) from sav_ai_crm.notification_deliveries where notification_id=n.id);
 insert into sav_ai_crm.notification_events(workspace_id,notification_id,event_type,actor_member_id,details)
 values(me.workspace_id,n.id,case when final_status='FAILED' then 'notification_failed' when final_status='RETRYING' then 'notification_retried' when final_status='DELIVERED' then 'notification_delivered' else 'notification_sent' end,me.id,
   jsonb_build_object('provider',p_provider,'status',final_status,'error_code',p_error_code));
 insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id,metadata)
 values(me.workspace_id,auth.uid(),'notification.'||lower(final_status),'notification',n.id,jsonb_build_object('provider',p_provider,'error_code',p_error_code));
end $$;

create or replace function public.sav_ai_crm_notification_mark_read(p_notification_id uuid,p_read boolean default true)
returns void language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; n sav_ai_crm.notifications;
begin
 me:=sav_ai_crm.notification_current_member(); if me.id is null then raise exception 'CRM membership required'; end if;
 select * into n from sav_ai_crm.notifications where id=p_notification_id and workspace_id=me.workspace_id and (recipient_member_id=me.id or sav_ai_crm.notification_can_manage(me.role) or me.role='viewer') for update;
 if n.id is null then raise exception 'Notification not found'; end if;
 update sav_ai_crm.notifications set read_at=case when p_read then now() else null end,
   status=case when p_read and channel='in_app' then 'READ' when not p_read and channel='in_app' and status='READ' then 'DELIVERED' else status end,updated_at=now() where id=n.id;
 insert into sav_ai_crm.notification_events(workspace_id,notification_id,event_type,actor_member_id) values(me.workspace_id,n.id,case when p_read then 'notification_read' else 'notification_unread' end,me.id);
end $$;

create or replace function public.sav_ai_crm_notifications_mark_all_read()
returns integer language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; cnt integer;
begin
 me:=sav_ai_crm.notification_current_member(); if me.id is null then raise exception 'CRM membership required'; end if;
 update sav_ai_crm.notifications set read_at=now(),status=case when channel='in_app' then 'READ' else status end,updated_at=now()
 where workspace_id=me.workspace_id and recipient_member_id=me.id and read_at is null;
 get diagnostics cnt=row_count;
 insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,metadata) values(me.workspace_id,auth.uid(),'notification.read_all','notification',jsonb_build_object('count',cnt));
 return cnt;
end $$;

create or replace function public.sav_ai_crm_notification_cancel(p_notification_id uuid)
returns void language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; n sav_ai_crm.notifications;
begin
 me:=sav_ai_crm.notification_current_member(); if me.id is null or not sav_ai_crm.notification_can_create(me.role) then raise exception 'Notification cancellation not permitted'; end if;
 select * into n from sav_ai_crm.notifications where id=p_notification_id and workspace_id=me.workspace_id for update;
 if n.id is null then raise exception 'Notification not found'; end if;
 if n.status not in ('QUEUED','SCHEDULED','RETRYING','WAITING_APPROVAL') then raise exception 'Notification can no longer be cancelled'; end if;
 update sav_ai_crm.notifications set status='CANCELLED',updated_at=now() where id=n.id;
 update sav_ai_crm.notification_deliveries set status='CANCELLED',updated_at=now() where notification_id=n.id and status in ('QUEUED','SCHEDULED','RETRYING','WAITING_APPROVAL');
 insert into sav_ai_crm.notification_events(workspace_id,notification_id,event_type,actor_member_id) values(me.workspace_id,n.id,'notification_cancelled',me.id);
 insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id) values(me.workspace_id,auth.uid(),'notification.cancelled','notification',n.id);
end $$;

create or replace function public.sav_ai_crm_notification_retry(p_notification_id uuid)
returns void language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; n sav_ai_crm.notifications; next_attempt integer;
begin
 me:=sav_ai_crm.notification_current_member(); if me.id is null or not sav_ai_crm.notification_can_create(me.role) then raise exception 'Notification retry not permitted'; end if;
 select * into n from sav_ai_crm.notifications where id=p_notification_id and workspace_id=me.workspace_id for update;
 if n.id is null or n.status not in ('FAILED','RETRYING') then raise exception 'Notification is not retryable'; end if;
 if n.retry_count>=n.max_retries then raise exception 'Notification retry limit exceeded'; end if;
 if coalesce(n.error_code,'') in ('CHANNEL_PROVIDER_NOT_CONFIGURED','PUSH_PROVIDER_NOT_CONFIGURED','WEBHOOK_PROVIDER_NOT_CONFIGURED') then raise exception 'Provider configuration required before retry'; end if;
 next_attempt:=coalesce((select max(attempt_number) from sav_ai_crm.notification_deliveries where notification_id=n.id),0)+1;
 update sav_ai_crm.notifications set status='QUEUED',next_attempt_at=now(),updated_at=now() where id=n.id;
 insert into sav_ai_crm.notification_deliveries(workspace_id,notification_id,channel,status,attempt_number) values(me.workspace_id,n.id,n.channel,'QUEUED',next_attempt);
 insert into sav_ai_crm.notification_events(workspace_id,notification_id,event_type,actor_member_id,details) values(me.workspace_id,n.id,'notification_retried',me.id,jsonb_build_object('attempt',next_attempt));
end $$;

create or replace function public.sav_ai_crm_notification_preferences()
returns jsonb language plpgsql stable security definer set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members;
begin
 me:=sav_ai_crm.notification_current_member(); if me.id is null then raise exception 'CRM membership required'; end if;
 return coalesce((select jsonb_agg(to_jsonb(p) order by p.category) from sav_ai_crm.notification_preferences p where p.workspace_id=me.workspace_id and p.member_id=me.id),'[]'::jsonb);
end $$;

create or replace function public.sav_ai_crm_update_notification_preference(p_category text,p_enabled boolean,p_preferred_channel text,p_quiet_hours_start time,p_quiet_hours_end time,p_digest_frequency text)
returns uuid language plpgsql security definer set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; pid uuid;
begin
 me:=sav_ai_crm.notification_current_member(); if me.id is null then raise exception 'CRM membership required'; end if;
 if p_preferred_channel not in ('in_app','email','whatsapp','sms','push','webhook') then raise exception 'Invalid channel'; end if;
 if p_digest_frequency not in ('none','daily','weekly') then raise exception 'Invalid digest frequency'; end if;
 if p_category='system_security' and p_enabled=false then raise exception 'Critical security notifications cannot be disabled'; end if;
 insert into sav_ai_crm.notification_preferences(workspace_id,member_id,category,enabled,preferred_channel,quiet_hours_start,quiet_hours_end,digest_frequency,updated_at)
 values(me.workspace_id,me.id,p_category,p_enabled,p_preferred_channel,p_quiet_hours_start,p_quiet_hours_end,p_digest_frequency,now())
 on conflict(workspace_id,member_id,category) do update set enabled=excluded.enabled,preferred_channel=excluded.preferred_channel,quiet_hours_start=excluded.quiet_hours_start,quiet_hours_end=excluded.quiet_hours_end,digest_frequency=excluded.digest_frequency,updated_at=now()
 returning id into pid;
 insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id,metadata) values(me.workspace_id,auth.uid(),'notification.preference.changed','notification_preference',pid,jsonb_build_object('category',p_category));
 return pid;
end $$;

create or replace function public.sav_ai_crm_notification_templates()
returns jsonb language plpgsql stable security definer set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members;
begin
 me:=sav_ai_crm.notification_current_member(); if me.id is null then raise exception 'CRM membership required'; end if;
 return coalesce((select jsonb_agg(to_jsonb(t) order by t.name,t.version desc) from sav_ai_crm.notification_templates t where t.workspace_id=me.workspace_id),'[]'::jsonb);
end $$;

create or replace function public.sav_ai_crm_save_notification_template(p_template_id uuid,p_name text,p_notification_type text,p_channel text,p_subject text,p_body text,p_variables text[],p_is_active boolean)
returns uuid language plpgsql security definer set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; tid uuid; next_version integer;
begin
 me:=sav_ai_crm.notification_current_member(); if me.id is null or me.role not in ('owner','admin') then raise exception 'Template management requires owner or admin'; end if;
 if p_body ~ '\{\{[^}]+\([^}]*\)\}\}' or p_body ~ '<script' then raise exception 'Executable template expressions are not allowed'; end if;
 if p_channel not in ('in_app','email','whatsapp','sms','push','webhook') then raise exception 'Invalid template channel'; end if;
 if p_template_id is null then
  insert into sav_ai_crm.notification_templates(workspace_id,name,notification_type,channel,subject,body,variables,is_active,created_by,updated_by)
  values(me.workspace_id,trim(p_name),p_notification_type,p_channel,p_subject,p_body,coalesce(p_variables,'{}'),p_is_active,me.id,me.id) returning id into tid;
 else
  select coalesce(max(version),0)+1 into next_version from sav_ai_crm.notification_templates where workspace_id=me.workspace_id and name=(select name from sav_ai_crm.notification_templates where id=p_template_id and workspace_id=me.workspace_id);
  insert into sav_ai_crm.notification_templates(workspace_id,name,notification_type,channel,subject,body,variables,is_active,version,created_by,updated_by)
  select workspace_id,trim(p_name),p_notification_type,p_channel,p_subject,p_body,coalesce(p_variables,'{}'),p_is_active,next_version,created_by,me.id
  from sav_ai_crm.notification_templates where id=p_template_id and workspace_id=me.workspace_id returning id into tid;
  if tid is null then raise exception 'Template not found'; end if;
 end if;
 insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id) values(me.workspace_id,auth.uid(),'notification.template.changed','notification_template',tid);
 return tid;
end $$;

create or replace function sav_ai_crm.render_notification_template(p_body text,p_variables jsonb)
returns text language plpgsql immutable
set search_path=public,sav_ai_crm
as $$
declare result text:=p_body; kv record;
begin
 if p_body is null then return null; end if;
 for kv in select key,value from jsonb_each_text(coalesce(p_variables,'{}')) loop
  if kv.key !~ '^[A-Za-z0-9_.-]+$' then raise exception 'Invalid template variable'; end if;
  result:=replace(result,'{{'||kv.key||'}}',kv.value);
 end loop;
 if result ~ '\{\{[^}]+\}\}' then raise exception 'Template contains unresolved variables'; end if;
 return result;
end $$;
revoke all on function sav_ai_crm.render_notification_template(text,jsonb) from public,anon,authenticated;

create or replace function public.sav_ai_crm_notification_schedules()
returns jsonb language plpgsql stable security definer set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members;
begin
 me:=sav_ai_crm.notification_current_member(); if me.id is null then raise exception 'CRM membership required'; end if;
 return coalesce((select jsonb_agg(to_jsonb(s) order by s.scheduled_at) from sav_ai_crm.notification_schedules s where s.workspace_id=me.workspace_id and (sav_ai_crm.notification_can_manage(me.role) or s.recipient_member_id=me.id or s.created_by=me.id)),'[]'::jsonb);
end $$;

create or replace function public.sav_ai_crm_save_notification_schedule(p_schedule_id uuid,p_notification_type text,p_channel text,p_recipient_member_id uuid,p_recipient_address text,p_title text,p_body text,p_priority text,p_scheduled_at timestamptz,p_recurrence_rule text,p_source_type text,p_source_id uuid,p_deep_link text,p_metadata jsonb)
returns uuid language plpgsql security definer set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; sid uuid;
begin
 me:=sav_ai_crm.notification_current_member(); if me.id is null or not sav_ai_crm.notification_can_create(me.role) then raise exception 'Schedule management not permitted'; end if;
 if p_scheduled_at<=now() then raise exception 'Schedule must be in the future'; end if;
 if p_recipient_member_id is not null and not exists(select 1 from sav_ai_crm.members where id=p_recipient_member_id and workspace_id=me.workspace_id) then raise exception 'Recipient outside workspace'; end if;
 if p_schedule_id is null then
  insert into sav_ai_crm.notification_schedules(workspace_id,notification_type,channel,recipient_member_id,recipient_address,title,body,priority,scheduled_at,next_run_at,recurrence_rule,source_type,source_id,deep_link,metadata,idempotency_prefix,created_by)
  values(me.workspace_id,p_notification_type,p_channel,p_recipient_member_id,p_recipient_address,p_title,p_body,p_priority,p_scheduled_at,p_scheduled_at,p_recurrence_rule,p_source_type,p_source_id,p_deep_link,coalesce(p_metadata,'{}'),'schedule:'||gen_random_uuid()::text,me.id)
  returning id into sid;
 else
  update sav_ai_crm.notification_schedules set notification_type=p_notification_type,channel=p_channel,recipient_member_id=p_recipient_member_id,recipient_address=p_recipient_address,title=p_title,body=p_body,priority=p_priority,scheduled_at=p_scheduled_at,next_run_at=p_scheduled_at,recurrence_rule=p_recurrence_rule,source_type=p_source_type,source_id=p_source_id,deep_link=p_deep_link,metadata=coalesce(p_metadata,'{}'),updated_at=now()
  where id=p_schedule_id and workspace_id=me.workspace_id returning id into sid;
  if sid is null then raise exception 'Schedule not found'; end if;
 end if;
 insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id) values(me.workspace_id,auth.uid(),'notification.schedule.changed','notification_schedule',sid);
 return sid;
end $$;

create or replace function public.sav_ai_crm_notification_channels()
returns jsonb language plpgsql stable security definer set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members;
begin
 me:=sav_ai_crm.notification_current_member(); if me.id is null then raise exception 'CRM membership required'; end if;
 return jsonb_build_array(
  jsonb_build_object('channel','in_app','status','connected','provider','internal'),
  jsonb_build_object('channel','email','status',case when exists(select 1 from sav_ai_crm.channel_accounts where workspace_id=me.workspace_id and channel='email' and status='connected') then 'configured' else 'not_configured' end),
  jsonb_build_object('channel','whatsapp','status',case when exists(select 1 from sav_ai_crm.channel_accounts where workspace_id=me.workspace_id and channel='whatsapp' and status='connected') then 'configured' else 'not_configured' end),
  jsonb_build_object('channel','sms','status',case when exists(select 1 from sav_ai_crm.channel_accounts where workspace_id=me.workspace_id and channel='sms' and status='connected') then 'configured' else 'not_configured' end),
  jsonb_build_object('channel','push','status','not_configured'),
  jsonb_build_object('channel','webhook','status','not_configured')
 );
end $$;

create or replace function public.sav_ai_crm_notification_due_worker(p_limit integer default 100)
returns jsonb language plpgsql security definer set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; r record; created integer:=0; nid uuid;
begin
 me:=sav_ai_crm.notification_current_member(); if me.id is null or me.role not in ('owner','admin','manager') then raise exception 'Notification worker run not permitted'; end if;
 for r in select * from sav_ai_crm.notification_schedules where workspace_id=me.workspace_id and status='active' and next_run_at<=now() order by next_run_at limit least(greatest(p_limit,1),500) for update skip locked loop
   nid:=public.sav_ai_crm_create_notification(r.notification_type,r.title,r.body,r.priority,r.channel,r.recipient_member_id,r.recipient_address,r.source_type,r.source_id,r.deep_link,null,null,null,null,null,null,null,null,r.metadata,r.idempotency_prefix||':'||extract(epoch from r.next_run_at)::bigint,false);
   created:=created+1;
   if r.recurrence_rule is null then update sav_ai_crm.notification_schedules set status='completed',next_run_at=null,updated_at=now() where id=r.id;
   elsif r.recurrence_rule='DAILY' then update sav_ai_crm.notification_schedules set next_run_at=next_run_at+interval '1 day',updated_at=now() where id=r.id;
   elsif r.recurrence_rule='WEEKLY' then update sav_ai_crm.notification_schedules set next_run_at=next_run_at+interval '7 days',updated_at=now() where id=r.id;
   else update sav_ai_crm.notification_schedules set status='paused',updated_at=now() where id=r.id;
   end if;
 end loop;
 return jsonb_build_object('created',created);
end $$;

create or replace function sav_ai_crm.sync_task_notification_trigger()
returns trigger language plpgsql security definer
set search_path=public,sav_ai_crm
as $
declare recipient uuid; notify_at timestamptz; ntype text; nid uuid; current_status text;
begin
 update sav_ai_crm.notifications set status='CANCELLED',updated_at=now()
 where workspace_id=new.workspace_id and task_id=new.id and status in ('QUEUED','SCHEDULED','RETRYING')
   and idempotency_key like 'task-auto:'||new.id::text||':%';

 if new.archived_at is not null or new.status in ('completed','cancelled') then return new; end if;
 recipient:=new.assigned_to;
 if recipient is null then
   select id into recipient from sav_ai_crm.members where workspace_id=new.workspace_id and is_active and role in ('owner','admin','manager')
   order by case role when 'owner' then 0 when 'admin' then 1 else 2 end,created_at limit 1;
 end if;
 if recipient is null then return new; end if;
 notify_at:=coalesce(new.reminder_at,case when new.due_at is not null then new.due_at-interval '1 day' else null end);
 if notify_at is null then return new; end if;
 ntype:=case when new.due_at is not null and new.due_at<now() then 'OVERDUE_REMINDER'
             when coalesce(new.followup_type,'general')<>'general' then 'FOLLOWUP_REMINDER' else 'TASK_REMINDER' end;
 current_status:=case when notify_at>now() then 'SCHEDULED' else 'QUEUED' end;

 insert into sav_ai_crm.notifications(workspace_id,recipient_member_id,notification_type,title,body,priority,channel,status,source_type,source_id,deep_link,
   task_id,lead_id,contact_id,agent_id,scheduled_at,next_attempt_at,metadata,idempotency_key)
 values(new.workspace_id,recipient,ntype,case when ntype='OVERDUE_REMINDER' then 'Task overdue' when ntype='FOLLOWUP_REMINDER' then 'Follow-up reminder' else 'Task reminder' end,
   new.title,new.priority,'in_app',current_status,'task',new.id,'/crm/tasks?task='||new.id::text,new.id,new.lead_id,new.contact_id,new.assigned_agent_id,
   case when notify_at>now() then notify_at else null end,notify_at,jsonb_build_object('due_at',new.due_at,'reminder_at',new.reminder_at,'followup_type',new.followup_type),
   'task-auto:'||new.id::text||':'||extract(epoch from notify_at)::bigint::text)
 on conflict(workspace_id,idempotency_key) do update set status=excluded.status,scheduled_at=excluded.scheduled_at,next_attempt_at=excluded.next_attempt_at,updated_at=now()
 returning id into nid;

 insert into sav_ai_crm.notification_recipients(workspace_id,notification_id,member_id,channel)
 values(new.workspace_id,nid,recipient,'in_app') on conflict(notification_id,member_id,channel) do nothing;
 insert into sav_ai_crm.notification_deliveries(workspace_id,notification_id,channel,status,attempt_number)
 select new.workspace_id,nid,'in_app',current_status,1 where not exists(select 1 from sav_ai_crm.notification_deliveries where notification_id=nid);
 insert into sav_ai_crm.notification_events(workspace_id,notification_id,event_type,details)
 values(new.workspace_id,nid,'task_notification_scheduled',jsonb_build_object('task_id',new.id,'scheduled_at',notify_at));
 return new;
end $;

drop trigger if exists trg_task_notification_sync on sav_ai_crm.tasks;
create trigger trg_task_notification_sync
after insert or update of due_at,reminder_at,assigned_to,assigned_agent_id,status,archived_at,followup_type
on sav_ai_crm.tasks for each row execute function sav_ai_crm.sync_task_notification_trigger();

revoke all on function sav_ai_crm.sync_task_notification_trigger() from public,anon,authenticated;

create or replace function public.sav_ai_crm_sync_task_notifications()
returns jsonb language plpgsql security definer set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; r record; created integer:=0; nid uuid; ntype text; deep text;
begin
 me:=sav_ai_crm.notification_current_member(); if me.id is null or not sav_ai_crm.notification_can_create(me.role) then raise exception 'Task reminder sync not permitted'; end if;
 for r in
  select t.* from sav_ai_crm.tasks t where t.workspace_id=me.workspace_id and t.archived_at is null and t.status not in ('completed','cancelled')
    and (t.reminder_at<=now()+interval '24 hours' or t.due_at<=now()+interval '24 hours')
  order by coalesce(t.reminder_at,t.due_at) limit 250
 loop
  ntype:=case when r.followup_type is not null and r.followup_type<>'general' then 'FOLLOWUP_REMINDER' else 'TASK_REMINDER' end;
  if r.due_at<now() then ntype:='OVERDUE_REMINDER'; end if;
  deep:='/crm/tasks?task='||r.id::text;
  nid:=public.sav_ai_crm_create_notification(ntype,case when r.due_at<now() then 'Task overdue' else 'Task reminder' end,r.title,r.priority,'in_app',
    coalesce(r.assigned_to,me.id),null,'task',r.id,deep,case when r.reminder_at>now() then r.reminder_at else null end,r.assigned_agent_id,r.lead_id,r.contact_id,r.id,null,null,null,'{}'::jsonb,
    'task-reminder:'||r.id::text||':'||coalesce(extract(epoch from r.reminder_at)::bigint::text,extract(epoch from r.due_at)::bigint::text,'0'),false);
  created:=created+1;
 end loop;
 return jsonb_build_object('created',created);
end $$;

create or replace function sav_ai_crm.create_notification_system(
 p_workspace_id uuid,p_notification_type text,p_title text,p_body text,p_priority text,p_source_type text,p_source_id uuid,
 p_deep_link text,p_conversation_id uuid,p_recipient_member_id uuid,p_idempotency_key text,p_metadata jsonb default '{}'::jsonb
) returns uuid language plpgsql security definer
set search_path=public,sav_ai_crm
as $
declare recipient uuid:=p_recipient_member_id; nid uuid;
begin
 if not exists(select 1 from sav_ai_crm.workspaces where id=p_workspace_id) then raise exception 'Workspace not found'; end if;
 if recipient is not null and not exists(select 1 from sav_ai_crm.members where id=recipient and workspace_id=p_workspace_id and is_active) then raise exception 'Recipient outside workspace'; end if;
 if recipient is null and p_conversation_id is not null then
   select assigned_to into recipient from sav_ai_crm.conversations where id=p_conversation_id and workspace_id=p_workspace_id;
 end if;
 if recipient is null then
   select id into recipient from sav_ai_crm.members where workspace_id=p_workspace_id and is_active and role in ('owner','admin','manager')
   order by case role when 'owner' then 0 when 'admin' then 1 else 2 end,created_at limit 1;
 end if;
 if recipient is null then raise exception 'No workspace notification recipient available'; end if;
 if p_notification_type<>'SECURITY_NOTIFICATION' and exists(
   select 1 from sav_ai_crm.notification_preferences pref
   where pref.workspace_id=p_workspace_id and pref.member_id=recipient
     and pref.category=sav_ai_crm.notification_category_for_type(p_notification_type) and pref.enabled=false
 ) then return null; end if;
 begin
   insert into sav_ai_crm.notifications(workspace_id,recipient_member_id,notification_type,title,body,priority,channel,status,source_type,source_id,deep_link,conversation_id,metadata,idempotency_key)
   values(p_workspace_id,recipient,p_notification_type,p_title,p_body,p_priority,'in_app','DELIVERED',p_source_type,p_source_id,p_deep_link,p_conversation_id,coalesce(p_metadata,'{}'),p_idempotency_key)
   returning id into nid;
 exception when unique_violation then
   select id into nid from sav_ai_crm.notifications where workspace_id=p_workspace_id and idempotency_key=p_idempotency_key;
   return nid;
 end;
 insert into sav_ai_crm.notification_recipients(workspace_id,notification_id,member_id,channel) values(p_workspace_id,nid,recipient,'in_app');
 insert into sav_ai_crm.notification_deliveries(workspace_id,notification_id,channel,status,provider,attempt_number,updated_at)
 values(p_workspace_id,nid,'in_app','DELIVERED','internal',1,now());
 insert into sav_ai_crm.notification_events(workspace_id,notification_id,event_type,details)
 values(p_workspace_id,nid,'system_notification_created',jsonb_build_object('source_type',p_source_type,'source_id',p_source_id));
 insert into sav_ai_crm.audit_logs(workspace_id,action,entity_type,entity_id,metadata)
 values(p_workspace_id,'notification.system.created','notification',nid,jsonb_build_object('source_type',p_source_type));
 return nid;
end $;
revoke all on function sav_ai_crm.create_notification_system(uuid,text,text,text,text,text,uuid,text,uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function sav_ai_crm.create_notification_system(uuid,text,text,text,text,text,uuid,text,uuid,uuid,text,jsonb) to service_role;

-- Phase 2: add a notification capability through existing agent authorization.
alter table sav_ai_crm.ai_agent_capabilities drop constraint if exists ai_agent_capabilities_capability_check;
alter table sav_ai_crm.ai_agent_capabilities add constraint ai_agent_capabilities_capability_check check(capability in (
 'READ_LEAD','UPDATE_LEAD','CREATE_TASK','UPDATE_TASK','CREATE_FOLLOWUP','READ_CONVERSATION','SEND_MESSAGE','CREATE_NOTE','CREATE_ESCALATION',
 'ASSIGN_TASK','READ_KNOWLEDGE','SUMMARIZE_CONVERSATION','SEND_NOTIFICATION',
 'DELETE_LEAD','PERMANENT_DELETE_TASK','FINANCIAL_ACTION','CHANGE_PERMISSION','SEND_BULK_MESSAGE'
));

insert into sav_ai_crm.ai_agent_capabilities(workspace_id,agent_id,capability,risk_level,approval_required,is_enabled,configuration)
select a.workspace_id,a.id,'SEND_NOTIFICATION','high',true,true,'{}'::jsonb
from sav_ai_crm.ai_agents a
where not exists(select 1 from sav_ai_crm.ai_agent_capabilities c where c.agent_id=a.id and c.capability='SEND_NOTIFICATION');

create or replace function public.sav_ai_crm_queue_approved_agent_notification(p_action_id uuid)
returns uuid language plpgsql security definer set search_path=public,sav_ai_crm
as $
declare me sav_ai_crm.members; act sav_ai_crm.ai_agent_actions; agent sav_ai_crm.ai_agents; nid uuid; recipient uuid; channel text;
begin
 me:=sav_ai_crm.notification_current_member();
 if me.id is null or not sav_ai_crm.notification_can_create(me.role) then raise exception 'AI notification queue not permitted'; end if;
 select * into act from sav_ai_crm.ai_agent_actions where id=p_action_id and workspace_id=me.workspace_id for update;
 if act.id is null or act.action<>'SEND_NOTIFICATION' then raise exception 'Approved SEND_NOTIFICATION action not found'; end if;
 if act.status not in ('approved','executing','completed','failed') then raise exception 'Human approval required'; end if;
 if act.status in ('executing','completed','failed') and nullif(act.result->>'notification_id','') is not null then return (act.result->>'notification_id')::uuid; end if;
 select * into agent from sav_ai_crm.ai_agents where id=act.agent_id and workspace_id=me.workspace_id and status='active';
 if agent.id is null then raise exception 'AI agent not available'; end if;
 if not exists(select 1 from sav_ai_crm.ai_agent_capabilities c where c.agent_id=agent.id and c.capability='SEND_NOTIFICATION' and c.is_enabled) then raise exception 'Agent capability denied'; end if;
 recipient:=nullif(act.payload->>'recipient_member_id','')::uuid;
 if recipient is not null and not exists(select 1 from sav_ai_crm.members where id=recipient and workspace_id=me.workspace_id and is_active) then raise exception 'Recipient outside workspace'; end if;
 channel:=coalesce(nullif(act.payload->>'channel',''),'in_app');
 nid:=public.sav_ai_crm_create_notification(
   coalesce(nullif(act.payload->>'notification_type',''),'AI_AGENT_NOTIFICATION'),
   coalesce(nullif(act.payload->>'title',''),agent.display_name||' notification'),
   coalesce(nullif(act.payload->>'body',''),'AI agent notification request'),
   coalesce(nullif(act.payload->>'priority',''),'medium'),channel,recipient,nullif(act.payload->>'recipient_address',''),
   'ai_agent',act.id,nullif(act.payload->>'deep_link',''),nullif(act.payload->>'scheduled_at','')::timestamptz,agent.id,
   nullif(act.payload->>'lead_id','')::uuid,nullif(act.payload->>'contact_id','')::uuid,nullif(act.payload->>'task_id','')::uuid,
   nullif(act.payload->>'workflow_id','')::uuid,nullif(act.payload->>'workflow_execution_id','')::uuid,nullif(act.payload->>'conversation_id','')::uuid,
   coalesce(act.payload->'metadata','{}'::jsonb),'ai-notification:'||act.id::text,false
 );
 update sav_ai_crm.ai_agent_actions set status='executing',result=jsonb_build_object('notification_id',nid),updated_at=now() where id=act.id;
 insert into sav_ai_crm.notification_events(workspace_id,notification_id,event_type,actor_agent_id,details)
 values(me.workspace_id,nid,'ai_notification_queued',agent.id,jsonb_build_object('agent_action_id',act.id));
 return nid;
end $;

create or replace function public.sav_ai_crm_finalize_agent_notification(p_action_id uuid,p_notification_id uuid,p_ok boolean,p_error text default null)
returns void language plpgsql security definer set search_path=public,sav_ai_crm
as $
declare me sav_ai_crm.members; act sav_ai_crm.ai_agent_actions; n sav_ai_crm.notifications;
begin
 me:=sav_ai_crm.notification_current_member(); if me.id is null or not sav_ai_crm.notification_can_create(me.role) then raise exception 'AI notification finalization not permitted'; end if;
 select * into act from sav_ai_crm.ai_agent_actions where id=p_action_id and workspace_id=me.workspace_id for update;
 select * into n from sav_ai_crm.notifications where id=p_notification_id and workspace_id=me.workspace_id;
 if act.id is null or n.id is null or act.agent_id<>n.agent_id then raise exception 'AI notification action mismatch'; end if;
 update sav_ai_crm.ai_agent_actions set status=case when p_ok then 'completed' else 'failed' end,
   result=jsonb_build_object('notification_id',n.id,'status',n.status),error=case when p_ok then null else coalesce(p_error,n.error_message,'NOTIFICATION_FAILED') end,
   completed_at=now(),updated_at=now() where id=act.id;
 insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id,metadata)
 values(me.workspace_id,auth.uid(),case when p_ok then 'notification.ai.completed' else 'notification.ai.failed' end,'ai_agent_action',act.id,jsonb_build_object('notification_id',n.id));
end $;

-- Phase 3: replace notification placeholder with central Phase 5 notification creation.
create or replace function sav_ai_crm.workflow_create_notification(p_execution_id uuid,p_node_id uuid)
returns uuid language plpgsql security definer set search_path=public,sav_ai_crm
as $$
declare ex sav_ai_crm.workflow_executions; n sav_ai_crm.workflow_nodes; w sav_ai_crm.workflows; recipient uuid; agent uuid; nid uuid; channel text; priority text;
begin
 select * into ex from sav_ai_crm.workflow_executions where id=p_execution_id;
 if ex.id is null then raise exception 'Workflow execution not found'; end if;
 select * into n from sav_ai_crm.workflow_nodes where id=p_node_id and workflow_id=ex.workflow_id and workflow_version=ex.workflow_version;
 select * into w from sav_ai_crm.workflows where id=ex.workflow_id;
 if n.id is null or n.node_type<>'NOTIFICATION' then raise exception 'Notification node not found'; end if;
 recipient:=nullif(trim(both '"' from (ex.context #> string_to_array(coalesce(n.config->>'recipient_member_id_path','member.id'),'.'))::text),'null')::uuid;
 if recipient is null then recipient:=nullif(n.config->>'recipient_member_id','')::uuid; end if;
 agent:=nullif(n.config->>'agent_id','')::uuid;
 channel:=coalesce(nullif(n.config->>'channel',''),'in_app');
 priority:=coalesce(nullif(n.config->>'priority',''),'medium');
 -- This internal helper is invoked only by the authenticated workflow execution engine; recipient stays workspace-bound.
 if recipient is not null and not exists(select 1 from sav_ai_crm.members where id=recipient and workspace_id=ex.workspace_id) then raise exception 'Workflow notification recipient outside workspace'; end if;
 insert into sav_ai_crm.notifications(workspace_id,recipient_member_id,recipient_address,notification_type,title,body,priority,channel,status,source_type,source_id,deep_link,workflow_id,workflow_execution_id,agent_id,metadata,idempotency_key)
 values(ex.workspace_id,recipient,nullif(n.config->>'recipient_address',''),coalesce(n.config->>'notification_type','WORKFLOW_STARTED'),coalesce(n.config->>'title',w.name),
   coalesce(n.config->>'body','Workflow notification'),priority,channel,case when coalesce((n.config->>'requires_approval')::boolean,false) then 'WAITING_APPROVAL' else 'QUEUED' end,
   'workflow',w.id,n.config->>'deep_link',w.id,ex.id,agent,coalesce(n.config->'metadata','{}'::jsonb),'workflow:'||ex.id::text||':'||n.id::text)
 on conflict(workspace_id,idempotency_key) do update set updated_at=now()
 returning id into nid;
 insert into sav_ai_crm.notification_recipients(workspace_id,notification_id,member_id,external_address,channel)
 select ex.workspace_id,nid,recipient,nullif(n.config->>'recipient_address',''),channel
 where not exists(select 1 from sav_ai_crm.notification_recipients where notification_id=nid);
 insert into sav_ai_crm.notification_deliveries(workspace_id,notification_id,channel,status)
 select ex.workspace_id,nid,channel,(select status from sav_ai_crm.notifications where id=nid)
 where not exists(select 1 from sav_ai_crm.notification_deliveries where notification_id=nid);
 insert into sav_ai_crm.notification_events(workspace_id,notification_id,event_type,details) values(ex.workspace_id,nid,'workflow_notification_requested',jsonb_build_object('workflow_execution_id',ex.id,'node_id',n.id));
 return nid;
end $$;
revoke all on function sav_ai_crm.workflow_create_notification(uuid,uuid) from public,anon,authenticated;

-- Extend the existing Phase 3 runner in-place: NOTIFICATION nodes now create Phase 5 records.
create or replace function public.sav_ai_crm_run_workflow_execution(p_execution_id uuid)
returns jsonb language plpgsql security definer
set search_path=public,sav_ai_crm
as $
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
     target_id:=sav_ai_crm.workflow_create_notification(ex.id,n.id);
     update sav_ai_crm.workflow_node_executions set status='completed',output=jsonb_build_object('notification_id',target_id),completed_at=now()
       where execution_id=ex.id and node_execution_id=node_exec_id;
     next_id:=sav_ai_crm.workflow_next_node(ex.workflow_id,ex.workflow_version,n.node_key,null);

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
end $;



-- Authenticated API grants / anonymous revocation.
revoke all on function public.sav_ai_crm_notification_context() from public,anon;
revoke all on function public.sav_ai_crm_notifications(text,text,text,text,text,uuid,text,uuid,uuid,text,timestamptz,timestamptz) from public,anon;
revoke all on function public.sav_ai_crm_notification_metrics() from public,anon;
revoke all on function public.sav_ai_crm_notification_upcoming() from public,anon;
revoke all on function public.sav_ai_crm_notification_detail(uuid) from public,anon;
revoke all on function public.sav_ai_crm_create_notification(text,text,text,text,text,uuid,text,text,uuid,text,timestamptz,uuid,uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text,boolean) from public,anon;
revoke all on function public.sav_ai_crm_update_notification(uuid,text,text,text,timestamptz,jsonb) from public,anon;
revoke all on function public.sav_ai_crm_notification_due_ids(integer) from public,anon;
revoke all on function public.sav_ai_crm_notification_prepare_send(uuid) from public,anon;
revoke all on function public.sav_ai_crm_notification_record_result(uuid,boolean,text,text,text,text,text,jsonb,boolean) from public,anon;
revoke all on function public.sav_ai_crm_notification_mark_read(uuid,boolean) from public,anon;
revoke all on function public.sav_ai_crm_notifications_mark_all_read() from public,anon;
revoke all on function public.sav_ai_crm_notification_cancel(uuid) from public,anon;
revoke all on function public.sav_ai_crm_notification_retry(uuid) from public,anon;
revoke all on function public.sav_ai_crm_notification_preferences() from public,anon;
revoke all on function public.sav_ai_crm_update_notification_preference(text,boolean,text,time,time,text) from public,anon;
revoke all on function public.sav_ai_crm_notification_templates() from public,anon;
revoke all on function public.sav_ai_crm_save_notification_template(uuid,text,text,text,text,text,text[],boolean) from public,anon;
revoke all on function public.sav_ai_crm_notification_schedules() from public,anon;
revoke all on function public.sav_ai_crm_save_notification_schedule(uuid,text,text,uuid,text,text,text,text,timestamptz,text,text,uuid,text,jsonb) from public,anon;
revoke all on function public.sav_ai_crm_notification_channels() from public,anon;
revoke all on function public.sav_ai_crm_notification_due_worker(integer) from public,anon;
revoke all on function public.sav_ai_crm_queue_approved_agent_notification(uuid) from public,anon;
revoke all on function public.sav_ai_crm_finalize_agent_notification(uuid,uuid,boolean,text) from public,anon;
revoke all on function public.sav_ai_crm_sync_task_notifications() from public,anon;

grant execute on function public.sav_ai_crm_notification_context() to authenticated;
grant execute on function public.sav_ai_crm_notifications(text,text,text,text,text,uuid,text,uuid,uuid,text,timestamptz,timestamptz) to authenticated;
grant execute on function public.sav_ai_crm_notification_metrics() to authenticated;
grant execute on function public.sav_ai_crm_notification_upcoming() to authenticated;
grant execute on function public.sav_ai_crm_notification_detail(uuid) to authenticated;
grant execute on function public.sav_ai_crm_create_notification(text,text,text,text,text,uuid,text,text,uuid,text,timestamptz,uuid,uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text,boolean) to authenticated;
grant execute on function public.sav_ai_crm_update_notification(uuid,text,text,text,timestamptz,jsonb) to authenticated;
grant execute on function public.sav_ai_crm_notification_due_ids(integer) to authenticated;
grant execute on function public.sav_ai_crm_notification_prepare_send(uuid) to authenticated;
grant execute on function public.sav_ai_crm_notification_record_result(uuid,boolean,text,text,text,text,text,jsonb,boolean) to authenticated;
grant execute on function public.sav_ai_crm_notification_mark_read(uuid,boolean) to authenticated;
grant execute on function public.sav_ai_crm_notifications_mark_all_read() to authenticated;
grant execute on function public.sav_ai_crm_notification_cancel(uuid) to authenticated;
grant execute on function public.sav_ai_crm_notification_retry(uuid) to authenticated;
grant execute on function public.sav_ai_crm_notification_preferences() to authenticated;
grant execute on function public.sav_ai_crm_update_notification_preference(text,boolean,text,time,time,text) to authenticated;
grant execute on function public.sav_ai_crm_notification_templates() to authenticated;
grant execute on function public.sav_ai_crm_save_notification_template(uuid,text,text,text,text,text,text[],boolean) to authenticated;
grant execute on function public.sav_ai_crm_notification_schedules() to authenticated;
grant execute on function public.sav_ai_crm_save_notification_schedule(uuid,text,text,uuid,text,text,text,text,timestamptz,text,text,uuid,text,jsonb) to authenticated;
grant execute on function public.sav_ai_crm_notification_channels() to authenticated;
grant execute on function public.sav_ai_crm_notification_due_worker(integer) to authenticated;
grant execute on function public.sav_ai_crm_queue_approved_agent_notification(uuid) to authenticated;
grant execute on function public.sav_ai_crm_finalize_agent_notification(uuid,uuid,boolean,text) to authenticated;
grant execute on function public.sav_ai_crm_sync_task_notifications() to authenticated;

commit;
