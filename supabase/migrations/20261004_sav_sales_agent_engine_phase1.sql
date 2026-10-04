-- SAV-Sales controlled tool engine reconciliation.
-- Extends existing Phase 2 action boundary; no new business tables.

create or replace function public.sav_ai_crm_log_agent_tool(
 p_agent_id uuid,
 p_tool text,
 p_success boolean,
 p_target_type text default null,
 p_target_id uuid default null,
 p_error text default null,
 p_metadata jsonb default '{}'::jsonb
) returns void
language plpgsql
security definer
set search_path=public,sav_ai_crm
as $$
declare me sav_ai_crm.members; agent sav_ai_crm.ai_agents;
begin
 me:=sav_ai_crm.agent_current_member();
 if me.id is null then raise exception 'CRM membership required'; end if;
 select * into agent from sav_ai_crm.ai_agents where id=p_agent_id and workspace_id=me.workspace_id;
 if agent.id is null then raise exception 'Agent not found'; end if;
 if nullif(trim(coalesce(p_tool,'')),'') is null then raise exception 'Tool name required'; end if;

 insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id,metadata)
 values(
   me.workspace_id,auth.uid(),
   case when p_success then 'agent.tool.succeeded' else 'agent.tool.failed' end,
   'ai_agent',agent.id,
   jsonb_build_object(
     'tool',left(trim(p_tool),100),
     'target_type',nullif(trim(coalesce(p_target_type,'')),''),
     'target_id',p_target_id,
     'error',case when p_success then null else left(coalesce(p_error,'TOOL_FAILED'),500) end,
     'metadata',coalesce(p_metadata,'{}'::jsonb)
   )
 );
end $$;

revoke all on function public.sav_ai_crm_log_agent_tool(uuid,text,boolean,text,uuid,text,jsonb) from public,anon;
grant execute on function public.sav_ai_crm_log_agent_tool(uuid,text,boolean,text,uuid,text,jsonb) to authenticated;

create or replace function public.sav_ai_crm_execute_agent_action(p_action_id uuid)
returns jsonb language plpgsql security definer
set search_path=public,sav_ai_crm
as $$
declare
 me sav_ai_crm.members;
 a sav_ai_crm.ai_agent_actions;
 agent sav_ai_crm.ai_agents;
 task_id uuid;
 lead_rec sav_ai_crm.leads;
 runtime_agent_id uuid;
 effective_workspace uuid;
 next_status text;
 result_payload jsonb := '{}'::jsonb;
begin
 me:=sav_ai_crm.agent_current_member();
 runtime_agent_id:=sav_ai_crm.agent_runtime_id();

 if runtime_agent_id is null and me.id is null then raise exception 'Authenticated CRM or agent identity required'; end if;

 select * into a from sav_ai_crm.ai_agent_actions where id=p_action_id for update;
 if a.id is null then raise exception 'Action not found'; end if;

 if runtime_agent_id is not null then
   if a.agent_id<>runtime_agent_id then raise exception 'Agent identity mismatch'; end if;
   effective_workspace:=a.workspace_id;
 else
   effective_workspace:=me.workspace_id;
   if a.workspace_id<>effective_workspace then raise exception 'Action is outside this workspace'; end if;
 end if;

 if a.approval_required and a.status<>'approved' then raise exception 'Human approval required'; end if;
 if a.status not in ('approved','pending') then raise exception 'Action is not executable'; end if;

 select * into agent from sav_ai_crm.ai_agents where id=a.agent_id and workspace_id=effective_workspace;
 if agent.id is null or agent.status<>'active' then raise exception 'Agent is not active'; end if;

 update sav_ai_crm.ai_agent_actions set status='executing',updated_at=now() where id=a.id;

 if a.action in ('CREATE_TASK','CREATE_FOLLOWUP') then
   if a.target_type<>'lead' or a.target_id is null then raise exception 'Task creation requires a lead target'; end if;
   select * into lead_rec from sav_ai_crm.leads where id=a.target_id and workspace_id=effective_workspace;
   if lead_rec.id is null then raise exception 'Lead not found'; end if;

   insert into sav_ai_crm.tasks(
     workspace_id,lead_id,title,description,task_type,followup_type,status,priority,due_at,reminder_at,
     assigned_agent_id,notes
   ) values(
     effective_workspace,lead_rec.id,
     coalesce(nullif(a.payload->>'title',''),agent.display_name||' follow-up'),
     nullif(a.payload->>'description',''),'followup',
     case when a.action='CREATE_FOLLOWUP' then coalesce(nullif(a.payload->>'followup_type',''),'general') else 'general' end,
     'pending',
     case when a.payload->>'priority' in ('low','medium','high','urgent') then a.payload->>'priority' else 'medium' end,
     nullif(a.payload->>'due_at','')::timestamptz,
     nullif(a.payload->>'reminder_at','')::timestamptz,
     agent.id,
     'Created by: '||agent.display_name
   ) returning id into task_id;

   insert into sav_ai_crm.activities(workspace_id,lead_id,task_id,activity_type,title,description,metadata)
   values(
     effective_workspace,lead_rec.id,task_id,
     case when a.action='CREATE_FOLLOWUP' then 'agent_followup_created' else 'agent_task_created' end,
     agent.display_name||' created task',
     coalesce(a.payload->>'title','Follow-up task'),
     jsonb_build_object('agent_id',agent.id,'agent_name',agent.display_name,'action_id',a.id)
   );
   result_payload:=jsonb_build_object('task_id',task_id);

 elsif a.action='UPDATE_LEAD' then
   if a.target_type<>'lead' or a.target_id is null then raise exception 'Lead update requires a lead target'; end if;
   next_status:=nullif(trim(coalesce(a.payload->>'status','')),'');
   if next_status is null then raise exception 'Lead status is required'; end if;
   if next_status not in ('new','contacted','qualified','proposal','negotiation','nurture') then
     raise exception 'Lead status is not permitted for autonomous agent update';
   end if;

   update sav_ai_crm.leads
   set status=next_status,updated_at=now()
   where id=a.target_id and workspace_id=effective_workspace;
   if not found then raise exception 'Lead not found'; end if;

   insert into sav_ai_crm.activities(workspace_id,lead_id,activity_type,title,description,channel,metadata)
   values(
     effective_workspace,a.target_id,'agent_lead_status_updated',
     agent.display_name||' updated lead status',next_status,'crm',
     jsonb_build_object('agent_id',agent.id,'action_id',a.id,'status',next_status)
   );
   result_payload:=jsonb_build_object('lead_id',a.target_id,'status',next_status);

 elsif a.action='CREATE_NOTE' then
   if a.target_type<>'lead' or a.target_id is null then raise exception 'Note requires a lead target'; end if;
   update sav_ai_crm.leads
   set notes=concat_ws(E'\n',notes,'['||agent.display_name||'] '||coalesce(a.payload->>'note','')),
       updated_at=now()
   where id=a.target_id and workspace_id=effective_workspace;
   if not found then raise exception 'Lead not found'; end if;
   insert into sav_ai_crm.activities(workspace_id,lead_id,activity_type,title,description,metadata)
   values(
     effective_workspace,a.target_id,'agent_note_created',
     agent.display_name||' added note',a.payload->>'note',
     jsonb_build_object('agent_id',agent.id,'action_id',a.id)
   );
   result_payload:=jsonb_build_object('lead_id',a.target_id);

 elsif a.action='CREATE_ESCALATION' then
   insert into sav_ai_crm.ai_agent_escalations(workspace_id,agent_id,lead_id,conversation_id,task_id,reason,details)
   values(
     effective_workspace,agent.id,
     case when a.target_type='lead' then a.target_id else null end,
     case when a.target_type='conversation' then a.target_id else null end,
     case when a.target_type='task' then a.target_id else null end,
     coalesce(nullif(a.payload->>'reason',''),'FAILED_ACTION'),
     a.payload->>'details'
   );
   result_payload:=jsonb_build_object('escalation_created',true);

 else
   update sav_ai_crm.ai_agent_actions
   set status='failed',error='ACTION_ADAPTER_NOT_IMPLEMENTED',updated_at=now(),completed_at=now()
   where id=a.id;
   raise exception 'Action adapter not implemented';
 end if;

 update sav_ai_crm.ai_agent_actions
 set status='completed',result=result_payload,updated_at=now(),completed_at=now()
 where id=a.id;

 insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id,metadata)
 values(
   effective_workspace,auth.uid(),'agent.action.completed','ai_agent_action',a.id,
   jsonb_build_object('agent_id',agent.id,'capability',a.action,'result',result_payload)
 );

 return jsonb_build_object('action_id',a.id,'status','completed')||result_payload;
end $$;

revoke all on function public.sav_ai_crm_execute_agent_action(uuid) from public,anon;
grant execute on function public.sav_ai_crm_execute_agent_action(uuid) to authenticated;
