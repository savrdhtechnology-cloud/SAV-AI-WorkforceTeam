-- SAVRDH Intelligence Workforce - Tasks / Follow-up module
-- PREPARED ONLY. Do not apply to production until branch UI/build verification passes.
-- Existing sav_ai_crm foundation is preserved; this migration only extends Tasks.

begin;

alter table sav_ai_crm.tasks
  add column if not exists followup_type text,
  add column if not exists reminder_at timestamptz,
  add column if not exists reminder_sent_at timestamptz,
  add column if not exists assigned_agent_id uuid,
  add column if not exists notes text,
  add column if not exists archived_at timestamptz,
  add column if not exists updated_at timestamptz not null default now();

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'tasks_assigned_agent_id_fkey'
      and conrelid = 'sav_ai_crm.tasks'::regclass
  ) then
    alter table sav_ai_crm.tasks
      add constraint tasks_assigned_agent_id_fkey
      foreign key (assigned_agent_id)
      references sav_ai_crm.ai_agents(id)
      on delete set null;
  end if;
end $$;

alter table sav_ai_crm.activities
  add column if not exists task_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'activities_task_id_fkey'
      and conrelid = 'sav_ai_crm.activities'::regclass
  ) then
    alter table sav_ai_crm.activities
      add constraint activities_task_id_fkey
      foreign key (task_id)
      references sav_ai_crm.tasks(id)
      on delete cascade;
  end if;
end $$;

create index if not exists tasks_workspace_status_due_idx
  on sav_ai_crm.tasks(workspace_id, status, due_at)
  where archived_at is null;

create index if not exists tasks_workspace_assignee_idx
  on sav_ai_crm.tasks(workspace_id, assigned_to)
  where archived_at is null;

create index if not exists tasks_workspace_agent_idx
  on sav_ai_crm.tasks(workspace_id, assigned_agent_id)
  where archived_at is null;

create index if not exists tasks_workspace_reminder_idx
  on sav_ai_crm.tasks(workspace_id, reminder_at)
  where reminder_sent_at is null and archived_at is null;

create index if not exists activities_task_created_idx
  on sav_ai_crm.activities(task_id, created_at desc);

create or replace function sav_ai_crm.task_current_member()
returns sav_ai_crm.members
language sql
stable
security definer
set search_path = public, sav_ai_crm
as $$
  select m
  from sav_ai_crm.members m
  where m.user_id = auth.uid()
    and m.is_active = true
  order by m.created_at
  limit 1;
$$;

revoke all on function sav_ai_crm.task_current_member() from public, anon;
grant execute on function sav_ai_crm.task_current_member() to authenticated;

create or replace function sav_ai_crm.task_can_manage_all(p_role text)
returns boolean
language sql
immutable
as $$
  select p_role in ('owner','admin','manager');
$$;

create or replace function public.sav_ai_crm_task_context()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, sav_ai_crm
as $$
declare
  me sav_ai_crm.members;
begin
  me := sav_ai_crm.task_current_member();
  if me.id is null then
    raise exception 'CRM membership required';
  end if;

  return jsonb_build_object(
    'member', jsonb_build_object(
      'id', me.id,
      'role', me.role,
      'full_name', me.full_name,
      'email', me.email
    ),
    'members', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id,
        'full_name', m.full_name,
        'email', m.email,
        'role', m.role
      ) order by coalesce(m.full_name,m.email), m.created_at)
      from sav_ai_crm.members m
      where m.workspace_id = me.workspace_id and m.is_active = true
    ), '[]'::jsonb),
    'agents', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', a.id,
        'name', a.name,
        'role_name', a.role_name,
        'status', a.status
      ) order by a.name)
      from sav_ai_crm.ai_agents a
      where a.workspace_id = me.workspace_id
    ), '[]'::jsonb),
    'leads', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', l.id,
        'title', l.title,
        'company', l.company,
        'status', l.status
      ) order by l.updated_at desc nulls last, l.created_at desc)
      from sav_ai_crm.leads l
      where l.workspace_id = me.workspace_id
      limit 500
    ), '[]'::jsonb),
    'contacts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id,
        'first_name', c.first_name,
        'last_name', c.last_name,
        'company', c.company,
        'email', c.email,
        'phone', c.phone
      ) order by c.updated_at desc nulls last, c.created_at desc)
      from sav_ai_crm.contacts c
      where c.workspace_id = me.workspace_id
      limit 500
    ), '[]'::jsonb),
    'followup_types', jsonb_build_array(
      'general','call','whatsapp','email','meeting','document','payment','proposal','site_visit','support'
    ),
    'permissions', jsonb_build_object(
      'create', me.role <> 'viewer',
      'edit_all', sav_ai_crm.task_can_manage_all(me.role),
      'assign_ai', sav_ai_crm.task_can_manage_all(me.role),
      'delete', me.role in ('owner','admin')
    )
  );
end;
$$;

create or replace function public.sav_ai_crm_list_tasks(
  p_scope text default 'all',
  p_status text default null,
  p_priority text default null,
  p_search text default null,
  p_assignee_type text default null,
  p_sort text default 'due_asc'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, sav_ai_crm
as $$
declare
  me sav_ai_crm.members;
  result jsonb;
begin
  me := sav_ai_crm.task_current_member();
  if me.id is null then raise exception 'CRM membership required'; end if;

  if p_scope not in ('all','today','overdue','upcoming','completed') then
    raise exception 'Invalid task scope';
  end if;
  if p_status is not null and p_status not in ('pending','in_progress','completed','cancelled') then
    raise exception 'Invalid task status';
  end if;
  if p_priority is not null and p_priority not in ('low','medium','high','urgent') then
    raise exception 'Invalid task priority';
  end if;
  if p_assignee_type is not null and p_assignee_type not in ('human','ai') then
    raise exception 'Invalid assignee type';
  end if;
  if p_sort not in ('due_asc','due_desc','priority','created_desc') then
    raise exception 'Invalid task sort';
  end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by
    case when p_sort='priority' then
      case x.priority when 'urgent' then 4 when 'high' then 3 when 'medium' then 2 else 1 end
    end desc nulls last,
    case when p_sort='due_asc' then x.due_at end asc nulls last,
    case when p_sort='due_desc' then x.due_at end desc nulls last,
    case when p_sort='created_desc' then x.created_at end desc nulls last,
    x.created_at desc
  ), '[]'::jsonb)
  into result
  from (
    select
      t.id,t.title,t.description,t.task_type,
      coalesce(t.followup_type,t.task_type) as followup_type,
      t.status,t.priority,t.due_at,t.reminder_at,t.reminder_sent_at,
      t.lead_id,t.contact_id,t.assigned_to,t.assigned_agent_id,
      case when t.assigned_agent_id is not null then 'ai' else 'human' end as assignee_type,
      coalesce(a.name,m.full_name,m.email) as assigned_name,
      coalesce(a.role_name,m.role) as assigned_role,
      coalesce(l.title, concat_ws(' ',c.first_name,c.last_name)) as related_name,
      t.notes,t.created_at,t.updated_at,t.completed_at,t.archived_at,
      (t.status not in ('completed','cancelled') and t.due_at is not null and t.due_at < now()) as is_overdue,
      (t.status not in ('completed','cancelled') and t.reminder_at is not null and t.reminder_sent_at is null and t.reminder_at <= now()) as reminder_due
    from sav_ai_crm.tasks t
    left join sav_ai_crm.members m on m.id=t.assigned_to
    left join sav_ai_crm.ai_agents a on a.id=t.assigned_agent_id
    left join sav_ai_crm.leads l on l.id=t.lead_id
    left join sav_ai_crm.contacts c on c.id=t.contact_id
    where t.workspace_id=me.workspace_id
      and t.archived_at is null
      and (p_status is null or t.status=p_status)
      and (p_priority is null or t.priority=p_priority)
      and (p_assignee_type is null or
        (p_assignee_type='human' and t.assigned_agent_id is null) or
        (p_assignee_type='ai' and t.assigned_agent_id is not null)
      )
      and (
        p_scope='all'
        or (p_scope='today' and t.due_at >= date_trunc('day',now()) and t.due_at < date_trunc('day',now()) + interval '1 day' and t.status not in ('completed','cancelled'))
        or (p_scope='overdue' and t.due_at < now() and t.status not in ('completed','cancelled'))
        or (p_scope='upcoming' and t.due_at >= date_trunc('day',now()) + interval '1 day' and t.status not in ('completed','cancelled'))
        or (p_scope='completed' and t.status='completed')
      )
      and (
        p_search is null
        or t.title ilike '%'||p_search||'%'
        or coalesce(t.description,'') ilike '%'||p_search||'%'
        or coalesce(t.notes,'') ilike '%'||p_search||'%'
        or coalesce(l.title,'') ilike '%'||p_search||'%'
        or concat_ws(' ',c.first_name,c.last_name) ilike '%'||p_search||'%'
        or coalesce(c.company,'') ilike '%'||p_search||'%'
        or coalesce(c.email,'') ilike '%'||p_search||'%'
        or coalesce(c.phone,'') ilike '%'||p_search||'%'
        or coalesce(m.full_name,m.email,'') ilike '%'||p_search||'%'
        or coalesce(a.name,'') ilike '%'||p_search||'%'
      )
  ) x;

  return result;
end;
$$;

create or replace function public.sav_ai_crm_task_detail(p_task_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, sav_ai_crm
as $$
declare
  me sav_ai_crm.members;
  task_json jsonb;
begin
  me := sav_ai_crm.task_current_member();
  if me.id is null then raise exception 'CRM membership required'; end if;

  select to_jsonb(x) into task_json
  from (
    select
      t.id,t.title,t.description,t.task_type,coalesce(t.followup_type,t.task_type) as followup_type,
      t.status,t.priority,t.due_at,t.reminder_at,t.reminder_sent_at,
      t.lead_id,t.contact_id,t.assigned_to,t.assigned_agent_id,
      case when t.assigned_agent_id is not null then 'ai' else 'human' end as assignee_type,
      coalesce(a.name,m.full_name,m.email) as assigned_name,
      coalesce(a.role_name,m.role) as assigned_role,
      coalesce(l.title, concat_ws(' ',c.first_name,c.last_name)) as related_name,
      t.notes,t.created_at,t.updated_at,t.completed_at,t.archived_at,
      (t.status not in ('completed','cancelled') and t.due_at is not null and t.due_at < now()) as is_overdue,
      (t.status not in ('completed','cancelled') and t.reminder_at is not null and t.reminder_sent_at is null and t.reminder_at <= now()) as reminder_due
    from sav_ai_crm.tasks t
    left join sav_ai_crm.members m on m.id=t.assigned_to
    left join sav_ai_crm.ai_agents a on a.id=t.assigned_agent_id
    left join sav_ai_crm.leads l on l.id=t.lead_id
    left join sav_ai_crm.contacts c on c.id=t.contact_id
    where t.id=p_task_id and t.workspace_id=me.workspace_id
  ) x;

  if task_json is null then raise exception 'Task not found'; end if;

  return jsonb_build_object(
    'task', task_json,
    'activity', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',ac.id,
        'activity_type',ac.activity_type,
        'title',ac.title,
        'description',ac.description,
        'created_at',ac.created_at,
        'actor_name',coalesce(am.full_name,am.email),
        'metadata',ac.metadata
      ) order by ac.created_at desc)
      from sav_ai_crm.activities ac
      left join sav_ai_crm.members am on am.id=ac.actor_member_id
      where ac.task_id=p_task_id and ac.workspace_id=me.workspace_id
    ),'[]'::jsonb)
  );
end;
$$;

create or replace function public.sav_ai_crm_create_task(
  p_title text,
  p_description text default null,
  p_followup_type text default 'general',
  p_priority text default 'medium',
  p_status text default 'pending',
  p_due_at timestamptz default null,
  p_reminder_at timestamptz default null,
  p_lead_id uuid default null,
  p_contact_id uuid default null,
  p_notes text default null,
  p_assignee_type text default 'human',
  p_assigned_to uuid default null,
  p_assigned_agent_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, sav_ai_crm
as $$
declare
  me sav_ai_crm.members;
  task_id uuid;
  target_member uuid;
begin
  me := sav_ai_crm.task_current_member();
  if me.id is null or me.role='viewer' then raise exception 'Task creation not permitted'; end if;

  if length(trim(coalesce(p_title,''))) < 3 or length(p_title) > 180 then raise exception 'Invalid task title'; end if;
  if p_priority not in ('low','medium','high','urgent') then raise exception 'Invalid priority'; end if;
  if p_status not in ('pending','in_progress','completed','cancelled') then raise exception 'Invalid status'; end if;
  if p_assignee_type not in ('human','ai') then raise exception 'Invalid assignee type'; end if;
  if p_reminder_at is not null and p_due_at is not null and p_reminder_at > p_due_at then raise exception 'Reminder cannot be after due time'; end if;

  if p_lead_id is not null and p_contact_id is not null then
    raise exception 'A task can be linked to a lead or customer, not both';
  end if;

  if p_lead_id is not null and not exists (
    select 1 from sav_ai_crm.leads where id=p_lead_id and workspace_id=me.workspace_id
  ) then raise exception 'Related lead is outside this workspace'; end if;

  if p_contact_id is not null and not exists (
    select 1 from sav_ai_crm.contacts where id=p_contact_id and workspace_id=me.workspace_id
  ) then raise exception 'Related customer is outside this workspace'; end if;

  if p_assignee_type='human' then
    target_member := coalesce(p_assigned_to,me.id);
    if not exists (select 1 from sav_ai_crm.members where id=target_member and workspace_id=me.workspace_id and is_active=true) then
      raise exception 'Invalid task assignee';
    end if;
    if not sav_ai_crm.task_can_manage_all(me.role) and target_member<>me.id then
      raise exception 'Only managers or admins can assign tasks to other users';
    end if;
    p_assigned_agent_id := null;
  else
    if not sav_ai_crm.task_can_manage_all(me.role) then raise exception 'AI assignment requires manager or admin permission'; end if;
    if p_assigned_agent_id is null or not exists (
      select 1 from sav_ai_crm.ai_agents where id=p_assigned_agent_id and workspace_id=me.workspace_id
    ) then raise exception 'Invalid AI agent'; end if;
    target_member := null;
  end if;

  insert into sav_ai_crm.tasks(
    workspace_id,lead_id,contact_id,title,description,task_type,followup_type,status,priority,
    due_at,reminder_at,assigned_to,assigned_agent_id,created_by,notes,completed_at,updated_at
  ) values (
    me.workspace_id,p_lead_id,p_contact_id,trim(p_title),nullif(trim(coalesce(p_description,'')),''),
    'followup',coalesce(nullif(trim(p_followup_type),''),'general'),p_status,p_priority,
    p_due_at,p_reminder_at,target_member,p_assigned_agent_id,me.id,
    nullif(trim(coalesce(p_notes,'')),''),
    case when p_status='completed' then now() else null end,now()
  ) returning id into task_id;

  insert into sav_ai_crm.activities(workspace_id,lead_id,contact_id,task_id,actor_member_id,activity_type,title,description,metadata)
  values (
    me.workspace_id,p_lead_id,p_contact_id,task_id,me.id,'task_created','Task created',
    trim(p_title),
    jsonb_build_object('priority',p_priority,'assignee_type',p_assignee_type,'followup_type',p_followup_type)
  );

  insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id,metadata)
  values (me.workspace_id,auth.uid(),'task.create','task',task_id,jsonb_build_object('status',p_status,'priority',p_priority));

  return task_id;
end;
$$;

create or replace function public.sav_ai_crm_update_task(
  p_task_id uuid,
  p_title text,
  p_description text default null,
  p_followup_type text default 'general',
  p_priority text default 'medium',
  p_status text default 'pending',
  p_due_at timestamptz default null,
  p_reminder_at timestamptz default null,
  p_lead_id uuid default null,
  p_notes text default null,
  p_assignee_type text default 'human',
  p_assigned_to uuid default null,
  p_assigned_agent_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public, sav_ai_crm
as $$
declare
  me sav_ai_crm.members;
  old_task sav_ai_crm.tasks;
  target_member uuid;
begin
  me := sav_ai_crm.task_current_member();
  if me.id is null or me.role='viewer' then raise exception 'Task update not permitted'; end if;

  select * into old_task from sav_ai_crm.tasks where id=p_task_id and workspace_id=me.workspace_id and archived_at is null;
  if old_task.id is null then raise exception 'Task not found'; end if;

  if not sav_ai_crm.task_can_manage_all(me.role)
     and old_task.created_by<>me.id
     and coalesce(old_task.assigned_to,'00000000-0000-0000-0000-000000000000'::uuid)<>me.id then
    raise exception 'You can only edit tasks you created or that are assigned to you';
  end if;

  if length(trim(coalesce(p_title,''))) < 3 or length(p_title) > 180 then raise exception 'Invalid task title'; end if;
  if p_priority not in ('low','medium','high','urgent') then raise exception 'Invalid priority'; end if;
  if p_status not in ('pending','in_progress','completed','cancelled') then raise exception 'Invalid status'; end if;
  if p_assignee_type not in ('human','ai') then raise exception 'Invalid assignee type'; end if;
  if p_reminder_at is not null and p_due_at is not null and p_reminder_at > p_due_at then raise exception 'Reminder cannot be after due time'; end if;

  if p_lead_id is not null and p_contact_id is not null then
    raise exception 'A task can be linked to a lead or customer, not both';
  end if;

  if p_lead_id is not null and not exists (
    select 1 from sav_ai_crm.leads where id=p_lead_id and workspace_id=me.workspace_id
  ) then raise exception 'Related lead is outside this workspace'; end if;

  if p_contact_id is not null and not exists (
    select 1 from sav_ai_crm.contacts where id=p_contact_id and workspace_id=me.workspace_id
  ) then raise exception 'Related customer is outside this workspace'; end if;

  if p_assignee_type='human' then
    target_member := coalesce(p_assigned_to,me.id);
    if not exists (select 1 from sav_ai_crm.members where id=target_member and workspace_id=me.workspace_id and is_active=true) then
      raise exception 'Invalid task assignee';
    end if;
    if not sav_ai_crm.task_can_manage_all(me.role) and target_member<>old_task.assigned_to and target_member<>me.id then
      raise exception 'Only managers or admins can reassign tasks to other users';
    end if;
    p_assigned_agent_id := null;
  else
    if not sav_ai_crm.task_can_manage_all(me.role) then raise exception 'AI assignment requires manager or admin permission'; end if;
    if p_assigned_agent_id is null or not exists (
      select 1 from sav_ai_crm.ai_agents where id=p_assigned_agent_id and workspace_id=me.workspace_id
    ) then raise exception 'Invalid AI agent'; end if;
    target_member := null;
  end if;

  update sav_ai_crm.tasks
  set title=trim(p_title),
      description=nullif(trim(coalesce(p_description,'')),''),
      followup_type=coalesce(nullif(trim(p_followup_type),''),'general'),
      priority=p_priority,status=p_status,due_at=p_due_at,reminder_at=p_reminder_at,
      reminder_sent_at=case when reminder_at is distinct from p_reminder_at then null else reminder_sent_at end,
      lead_id=p_lead_id,contact_id=p_contact_id,notes=nullif(trim(coalesce(p_notes,'')),''),
      assigned_to=target_member,assigned_agent_id=p_assigned_agent_id,
      completed_at=case when p_status='completed' then coalesce(completed_at,now()) else null end,
      updated_at=now()
  where id=p_task_id;

  insert into sav_ai_crm.activities(workspace_id,lead_id,contact_id,task_id,actor_member_id,activity_type,title,description,metadata)
  values (
    me.workspace_id,p_lead_id,p_contact_id,p_task_id,me.id,'task_updated','Task updated',trim(p_title),
    jsonb_build_object('from_status',old_task.status,'to_status',p_status,'priority',p_priority,'assignee_type',p_assignee_type)
  );

  insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id,metadata)
  values (me.workspace_id,auth.uid(),'task.update','task',p_task_id,jsonb_build_object('status',p_status,'priority',p_priority));
end;
$$;

create or replace function public.sav_ai_crm_set_task_status(p_task_id uuid,p_status text)
returns void
language plpgsql
security definer
set search_path = public, sav_ai_crm
as $$
declare
  me sav_ai_crm.members;
  t sav_ai_crm.tasks;
begin
  me := sav_ai_crm.task_current_member();
  if me.id is null or me.role='viewer' then raise exception 'Task update not permitted'; end if;
  if p_status not in ('pending','in_progress','completed','cancelled') then raise exception 'Invalid status'; end if;

  select * into t from sav_ai_crm.tasks where id=p_task_id and workspace_id=me.workspace_id and archived_at is null;
  if t.id is null then raise exception 'Task not found'; end if;
  if not sav_ai_crm.task_can_manage_all(me.role) and t.created_by<>me.id and coalesce(t.assigned_to,'00000000-0000-0000-0000-000000000000'::uuid)<>me.id then
    raise exception 'Task status update not permitted';
  end if;

  update sav_ai_crm.tasks set status=p_status,completed_at=case when p_status='completed' then coalesce(completed_at,now()) else null end,updated_at=now() where id=p_task_id;

  insert into sav_ai_crm.activities(workspace_id,lead_id,contact_id,task_id,actor_member_id,activity_type,title,description,metadata)
  values (me.workspace_id,t.lead_id,t.contact_id,p_task_id,me.id,'task_status','Task status changed',p_status,jsonb_build_object('from',t.status,'to',p_status));
end;
$$;

create or replace function public.sav_ai_crm_archive_task(p_task_id uuid)
returns void
language plpgsql
security definer
set search_path = public, sav_ai_crm
as $$
declare
  me sav_ai_crm.members;
  t sav_ai_crm.tasks;
begin
  me := sav_ai_crm.task_current_member();
  select * into t from sav_ai_crm.tasks where id=p_task_id and workspace_id=me.workspace_id and archived_at is null;
  if t.id is null then raise exception 'Task not found'; end if;
  if me.id is null or me.role='viewer' or (
    not sav_ai_crm.task_can_manage_all(me.role) and t.created_by<>me.id and coalesce(t.assigned_to,'00000000-0000-0000-0000-000000000000'::uuid)<>me.id
  ) then raise exception 'Task archive not permitted'; end if;

  update sav_ai_crm.tasks set archived_at=now(),updated_at=now() where id=p_task_id;
  insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id)
  values (me.workspace_id,auth.uid(),'task.archive','task',p_task_id);
end;
$$;

create or replace function public.sav_ai_crm_delete_task(p_task_id uuid)
returns void
language plpgsql
security definer
set search_path = public, sav_ai_crm
as $$
declare
  me sav_ai_crm.members;
begin
  me := sav_ai_crm.task_current_member();
  if me.id is null or me.role not in ('owner','admin') then raise exception 'Permanent task deletion requires owner or admin permission'; end if;
  if not exists (select 1 from sav_ai_crm.tasks where id=p_task_id and workspace_id=me.workspace_id) then raise exception 'Task not found'; end if;

  insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id)
  values (me.workspace_id,auth.uid(),'task.delete','task',p_task_id);

  delete from sav_ai_crm.tasks where id=p_task_id and workspace_id=me.workspace_id;
end;
$$;

create or replace function public.sav_ai_crm_due_task_reminders()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, sav_ai_crm
as $$
declare
  me sav_ai_crm.members;
begin
  me := sav_ai_crm.task_current_member();
  if me.id is null then raise exception 'CRM membership required'; end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',t.id,'title',t.title,'reminder_at',t.reminder_at,'due_at',t.due_at,
      'assigned_to',t.assigned_to,'assigned_agent_id',t.assigned_agent_id
    ) order by t.reminder_at)
    from sav_ai_crm.tasks t
    where t.workspace_id=me.workspace_id
      and t.archived_at is null
      and t.status not in ('completed','cancelled')
      and t.reminder_at is not null
      and t.reminder_sent_at is null
      and t.reminder_at<=now()
      and (sav_ai_crm.task_can_manage_all(me.role) or t.assigned_to=me.id or t.created_by=me.id)
  ),'[]'::jsonb);
end;
$$;

create or replace function public.sav_ai_crm_agent_task_action(
  p_task_id uuid,
  p_action text,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public, sav_ai_crm
as $$
declare
  agent_id uuid;
  t sav_ai_crm.tasks;
  next_status text;
begin
  -- Future agents must authenticate with a dedicated Supabase user whose
  -- server-controlled app_metadata contains {"sav_ai_agent_id":"<uuid>"}.
  -- User-editable user_metadata is intentionally never trusted.
  agent_id := nullif(auth.jwt()->'app_metadata'->>'sav_ai_agent_id','')::uuid;
  if auth.uid() is null or agent_id is null then raise exception 'Authenticated SAV agent identity required'; end if;
  if p_action not in ('start','complete','cancel') then raise exception 'Invalid agent action'; end if;

  select * into t from sav_ai_crm.tasks
  where id=p_task_id and assigned_agent_id=agent_id and archived_at is null;

  if t.id is null then raise exception 'Task is not assigned to this agent'; end if;
  if not exists (select 1 from sav_ai_crm.ai_agents where id=agent_id and workspace_id=t.workspace_id and status='active') then
    raise exception 'Agent is not active in this workspace';
  end if;

  next_status := case p_action when 'start' then 'in_progress' when 'complete' then 'completed' else 'cancelled' end;

  update sav_ai_crm.tasks
  set status=next_status,
      completed_at=case when next_status='completed' then now() else null end,
      updated_at=now()
  where id=p_task_id;

  insert into sav_ai_crm.activities(workspace_id,lead_id,contact_id,task_id,activity_type,title,description,metadata)
  values (
    t.workspace_id,t.lead_id,t.contact_id,p_task_id,'agent_task_action','AI agent task action',
    nullif(trim(coalesce(p_note,'')),''),
    jsonb_build_object('agent_id',agent_id,'action',p_action,'from_status',t.status,'to_status',next_status)
  );

  insert into sav_ai_crm.audit_logs(workspace_id,actor_user_id,action,entity_type,entity_id,metadata)
  values (t.workspace_id,auth.uid(),'agent.task.'||p_action,'task',p_task_id,jsonb_build_object('agent_id',agent_id));
end;
$$;

-- Explicit API exposure. These SECURITY DEFINER functions all validate auth.uid(),
-- workspace membership and role/ownership before touching records.
revoke all on function public.sav_ai_crm_task_context() from public, anon;
revoke all on function public.sav_ai_crm_list_tasks(text,text,text,text,text,text) from public, anon;
revoke all on function public.sav_ai_crm_task_detail(uuid) from public, anon;
revoke all on function public.sav_ai_crm_create_task(text,text,text,text,text,timestamptz,timestamptz,uuid,uuid,text,text,uuid,uuid) from public, anon;
revoke all on function public.sav_ai_crm_update_task(uuid,text,text,text,text,text,timestamptz,timestamptz,uuid,uuid,text,text,uuid,uuid) from public, anon;
revoke all on function public.sav_ai_crm_set_task_status(uuid,text) from public, anon;
revoke all on function public.sav_ai_crm_archive_task(uuid) from public, anon;
revoke all on function public.sav_ai_crm_delete_task(uuid) from public, anon;
revoke all on function public.sav_ai_crm_due_task_reminders() from public, anon;
revoke all on function public.sav_ai_crm_agent_task_action(uuid,text,text) from public, anon;

grant execute on function public.sav_ai_crm_task_context() to authenticated;
grant execute on function public.sav_ai_crm_list_tasks(text,text,text,text,text,text) to authenticated;
grant execute on function public.sav_ai_crm_task_detail(uuid) to authenticated;
grant execute on function public.sav_ai_crm_create_task(text,text,text,text,text,timestamptz,timestamptz,uuid,uuid,text,text,uuid,uuid) to authenticated;
grant execute on function public.sav_ai_crm_update_task(uuid,text,text,text,text,text,timestamptz,timestamptz,uuid,uuid,text,text,uuid,uuid) to authenticated;
grant execute on function public.sav_ai_crm_set_task_status(uuid,text) to authenticated;
grant execute on function public.sav_ai_crm_archive_task(uuid) to authenticated;
grant execute on function public.sav_ai_crm_delete_task(uuid) to authenticated;
grant execute on function public.sav_ai_crm_due_task_reminders() to authenticated;
grant execute on function public.sav_ai_crm_agent_task_action(uuid,text,text) to authenticated;

commit;
