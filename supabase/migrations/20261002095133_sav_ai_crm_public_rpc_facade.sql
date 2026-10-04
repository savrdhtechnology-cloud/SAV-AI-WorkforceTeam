-- Snapshot of existing SAVRDH AI CRM base migration 20261002095133 (sav_ai_crm_public_rpc_facade).
-- Copied read-only from Supabase migration history for reproducible staging verification.
-- Do not edit without reconciling against the original migration history.

create or replace function public.sav_ai_crm_bootstrap_workspace(p_company_name text default 'Savrdh Technology')
returns jsonb
language plpgsql
security definer
set search_path = public, sav_ai_crm
as $$
declare
  uid uuid := auth.uid();
  wid uuid;
  existing_wid uuid;
begin
  if uid is null then
    raise exception 'Authentication required';
  end if;

  select workspace_id into existing_wid
  from sav_ai_crm.members
  where user_id = uid and is_active = true
  order by created_at asc
  limit 1;

  if existing_wid is not null then
    return jsonb_build_object('workspace_id', existing_wid, 'created', false);
  end if;

  insert into sav_ai_crm.workspaces(name, slug, company_name)
  values (
    coalesce(nullif(trim(p_company_name),''), 'SAV AI Workspace'),
    'sav-ai-' || substr(replace(gen_random_uuid()::text,'-',''),1,10),
    coalesce(nullif(trim(p_company_name),''), 'SAV AI Workspace')
  )
  returning id into wid;

  insert into sav_ai_crm.members(workspace_id,user_id,role,email,full_name)
  values (wid,uid,'owner',coalesce(auth.jwt()->>'email',''),coalesce(auth.jwt()->>'email','Workspace Owner'));

  insert into sav_ai_crm.ai_agents(workspace_id,name,slug,role_name,description,status,channels,autonomy_level,approval_required)
  values
    (wid,'SAV-Sales','sav-sales','Sales & Follow-up Agent','Qualifies leads, executes follow-ups and keeps opportunities moving.','active',array['whatsapp','email','voice'],'assisted',true),
    (wid,'SAV-Support','sav-support','Customer Support Agent','Handles routine customer conversations and escalates exceptions.','active',array['whatsapp','email','webchat'],'assisted',true),
    (wid,'SAV-Operations','sav-operations','Workflow Operations Agent','Coordinates repeatable operational tasks across connected systems.','active',array['crm','email'],'assisted',true)
  on conflict do nothing;

  insert into sav_ai_crm.integrations(workspace_id,provider,display_name,status)
  values
    (wid,'whatsapp','WhatsApp Business','disconnected'),
    (wid,'email','Transactional Email','disconnected'),
    (wid,'voice','Voice Telephony','disconnected'),
    (wid,'supabase','Supabase Data','connected')
  on conflict do nothing;

  insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id)
  values (wid,uid,'workspace_bootstrap','workspace',wid);

  return jsonb_build_object('workspace_id', wid, 'created', true);
end;
$$;

create or replace function public.sav_ai_crm_workspace()
returns jsonb
language sql
stable
security definer
set search_path = public, sav_ai_crm
as $$
  select to_jsonb(x)
  from (
    select w.id,w.name,w.slug,w.company_name,w.website,w.status,m.role,m.full_name,m.email
    from sav_ai_crm.members m
    join sav_ai_crm.workspaces w on w.id=m.workspace_id
    where m.user_id=auth.uid() and m.is_active=true
    order by m.created_at asc
    limit 1
  ) x;
$$;

create or replace function public.sav_ai_crm_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, sav_ai_crm
as $$
declare wid uuid;
begin
  select workspace_id into wid from sav_ai_crm.members where user_id=auth.uid() and is_active=true order by created_at limit 1;
  if wid is null then return null; end if;

  return jsonb_build_object(
    'workspace_id',wid,
    'lead_total',(select count(*) from sav_ai_crm.leads where workspace_id=wid),
    'lead_new',(select count(*) from sav_ai_crm.leads where workspace_id=wid and status='new'),
    'lead_qualified',(select count(*) from sav_ai_crm.leads where workspace_id=wid and status='qualified'),
    'pipeline_value',(select coalesce(sum(amount),0) from sav_ai_crm.deals where workspace_id=wid and stage not in ('won','lost')),
    'won_value',(select coalesce(sum(amount),0) from sav_ai_crm.deals where workspace_id=wid and stage='won'),
    'tasks_pending',(select count(*) from sav_ai_crm.tasks where workspace_id=wid and status in ('pending','in_progress')),
    'conversations_open',(select count(*) from sav_ai_crm.conversations where workspace_id=wid and status<>'closed'),
    'agents_active',(select count(*) from sav_ai_crm.ai_agents where workspace_id=wid and status='active'),
    'workflows_active',(select count(*) from sav_ai_crm.workflows where workspace_id=wid and status='active'),
    'recent_activity',coalesce((
      select jsonb_agg(to_jsonb(a) order by a.created_at desc)
      from (
        select id,activity_type,title,description,channel,created_at
        from sav_ai_crm.activities
        where workspace_id=wid
        order by created_at desc
        limit 8
      ) a
    ),'[]'::jsonb)
  );
end;
$$;

create or replace function public.sav_ai_crm_list_leads(p_status text default null, p_search text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, sav_ai_crm
as $$
declare wid uuid;
begin
  select workspace_id into wid from sav_ai_crm.members where user_id=auth.uid() and is_active=true order by created_at limit 1;
  if wid is null then return '[]'::jsonb; end if;
  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.created_at desc)
    from (
      select id,title,company,email,phone,source,status,priority,score,value,next_followup_at,created_at
      from sav_ai_crm.leads
      where workspace_id=wid
        and (p_status is null or p_status='' or status=p_status)
        and (p_search is null or p_search='' or title ilike '%'||p_search||'%' or company ilike '%'||p_search||'%' or email ilike '%'||p_search||'%' or phone ilike '%'||p_search||'%')
      order by created_at desc
      limit 250
    ) x
  ),'[]'::jsonb);
end;
$$;

create or replace function public.sav_ai_crm_create_lead(
  p_title text,
  p_company text default null,
  p_email text default null,
  p_phone text default null,
  p_source text default 'manual',
  p_priority text default 'medium',
  p_value numeric default 0
)
returns uuid
language plpgsql
security definer
set search_path = public, sav_ai_crm
as $$
declare wid uuid; lid uuid;
begin
  select workspace_id into wid from sav_ai_crm.members where user_id=auth.uid() and is_active=true order by created_at limit 1;
  if wid is null then raise exception 'Workspace not initialized'; end if;
  if nullif(trim(p_title),'') is null then raise exception 'Lead title required'; end if;

  insert into sav_ai_crm.leads(workspace_id,title,company,email,phone,source,priority,value)
  values(wid,trim(p_title),nullif(trim(p_company),''),nullif(trim(p_email),''),nullif(trim(p_phone),''),coalesce(nullif(trim(p_source),''),'manual'),coalesce(nullif(trim(p_priority),''),'medium'),coalesce(p_value,0))
  returning id into lid;

  insert into sav_ai_crm.activities(workspace_id,lead_id,activity_type,title,description,channel)
  values(wid,lid,'lead_created','New lead created',trim(p_title),'crm');

  insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id)
  values(wid,auth.uid(),'lead_created','lead',lid);

  return lid;
end;
$$;

create or replace function public.sav_ai_crm_update_lead_status(p_lead_id uuid,p_status text)
returns boolean
language plpgsql
security definer
set search_path = public, sav_ai_crm
as $$
declare wid uuid;
begin
  select workspace_id into wid from sav_ai_crm.members where user_id=auth.uid() and is_active=true order by created_at limit 1;
  if wid is null then return false; end if;

  update sav_ai_crm.leads
  set status=p_status, updated_at=now()
  where id=p_lead_id and workspace_id=wid;

  if not found then return false; end if;

  insert into sav_ai_crm.activities(workspace_id,lead_id,activity_type,title,description,channel)
  values(wid,p_lead_id,'lead_status_changed','Lead status updated',p_status,'crm');
  return true;
end;
$$;

create or replace function public.sav_ai_crm_agents()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, sav_ai_crm
as $$
declare wid uuid;
begin
 select workspace_id into wid from sav_ai_crm.members where user_id=auth.uid() and is_active=true order by created_at limit 1;
 return coalesce((select jsonb_agg(to_jsonb(x) order by x.name) from (
   select id,name,slug,role_name,description,status,channels,autonomy_level,approval_required,updated_at
   from sav_ai_crm.ai_agents where workspace_id=wid
 ) x),'[]'::jsonb);
end;
$$;

create or replace function public.sav_ai_crm_integrations()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, sav_ai_crm
as $$
declare wid uuid;
begin
 select workspace_id into wid from sav_ai_crm.members where user_id=auth.uid() and is_active=true order by created_at limit 1;
 return coalesce((select jsonb_agg(to_jsonb(x) order by x.display_name) from (
   select id,provider,display_name,status,connected_at,updated_at from sav_ai_crm.integrations where workspace_id=wid
 ) x),'[]'::jsonb);
end;
$$;

revoke all on function public.sav_ai_crm_bootstrap_workspace(text) from public;
revoke all on function public.sav_ai_crm_workspace() from public;
revoke all on function public.sav_ai_crm_dashboard() from public;
revoke all on function public.sav_ai_crm_list_leads(text,text) from public;
revoke all on function public.sav_ai_crm_create_lead(text,text,text,text,text,text,numeric) from public;
revoke all on function public.sav_ai_crm_update_lead_status(uuid,text) from public;
revoke all on function public.sav_ai_crm_agents() from public;
revoke all on function public.sav_ai_crm_integrations() from public;

grant execute on function public.sav_ai_crm_bootstrap_workspace(text) to authenticated;
grant execute on function public.sav_ai_crm_workspace() to authenticated;
grant execute on function public.sav_ai_crm_dashboard() to authenticated;
grant execute on function public.sav_ai_crm_list_leads(text,text) to authenticated;
grant execute on function public.sav_ai_crm_create_lead(text,text,text,text,text,text,numeric) to authenticated;
grant execute on function public.sav_ai_crm_update_lead_status(uuid,text) to authenticated;
grant execute on function public.sav_ai_crm_agents() to authenticated;
grant execute on function public.sav_ai_crm_integrations() to authenticated;
