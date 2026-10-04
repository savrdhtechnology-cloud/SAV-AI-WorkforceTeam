-- Snapshot of existing SAVRDH AI CRM base migration 20261002095224 (sav_ai_crm_operational_reads).
-- Copied read-only from Supabase migration history for reproducible staging verification.
-- Do not edit without reconciling against the original migration history.

create or replace function public.sav_ai_crm_tasks()
returns jsonb
language plpgsql stable security definer
set search_path = public, sav_ai_crm
as $$
declare wid uuid;
begin
 select workspace_id into wid from sav_ai_crm.members where user_id=auth.uid() and is_active=true order by created_at limit 1;
 return coalesce((select jsonb_agg(to_jsonb(x) order by x.due_at nulls last, x.created_at desc) from (
   select id,title,description,task_type,status,priority,due_at,created_at
   from sav_ai_crm.tasks where workspace_id=wid
   order by due_at nulls last, created_at desc limit 200
 ) x),'[]'::jsonb);
end;
$$;

create or replace function public.sav_ai_crm_workflows()
returns jsonb
language plpgsql stable security definer
set search_path = public, sav_ai_crm
as $$
declare wid uuid;
begin
 select workspace_id into wid from sav_ai_crm.members where user_id=auth.uid() and is_active=true order by created_at limit 1;
 return coalesce((select jsonb_agg(to_jsonb(x) order by x.updated_at desc) from (
   select w.id,w.name,w.trigger_type,w.status,w.run_count,w.success_count,w.last_run_at,w.updated_at,
          a.name as agent_name
   from sav_ai_crm.workflows w left join sav_ai_crm.ai_agents a on a.id=w.agent_id
   where w.workspace_id=wid
 ) x),'[]'::jsonb);
end;
$$;

create or replace function public.sav_ai_crm_conversations()
returns jsonb
language plpgsql stable security definer
set search_path = public, sav_ai_crm
as $$
declare wid uuid;
begin
 select workspace_id into wid from sav_ai_crm.members where user_id=auth.uid() and is_active=true order by created_at limit 1;
 return coalesce((select jsonb_agg(to_jsonb(x) order by x.last_message_at desc nulls last, x.created_at desc) from (
   select c.id,c.channel,c.status,c.last_message_at,c.created_at,
          coalesce(ct.first_name || ' ' || ct.last_name, l.title, 'Conversation') as contact_name
   from sav_ai_crm.conversations c
   left join sav_ai_crm.contacts ct on ct.id=c.contact_id
   left join sav_ai_crm.leads l on l.id=c.lead_id
   where c.workspace_id=wid
   order by c.last_message_at desc nulls last, c.created_at desc limit 200
 ) x),'[]'::jsonb);
end;
$$;

revoke all on function public.sav_ai_crm_tasks() from public;
revoke all on function public.sav_ai_crm_workflows() from public;
revoke all on function public.sav_ai_crm_conversations() from public;
grant execute on function public.sav_ai_crm_tasks() to authenticated;
grant execute on function public.sav_ai_crm_workflows() to authenticated;
grant execute on function public.sav_ai_crm_conversations() to authenticated;
