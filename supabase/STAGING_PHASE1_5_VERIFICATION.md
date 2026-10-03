# SAVRDH Intelligence Workforce — Phase 1–5 Staging Verification Gate

## Scope and hard stops

This procedure verifies the SAVRDH AI CRM database chain without changing production.

**Approved staging project ref:** `gsudlmrmrefqqodpdeug`

Current verification uses Vercel Preview only. Do not run the app locally or execute the migration procedure below without separate authorization.

Hard rules:

- Never run these migration files against any production project.
- Never create a billable Supabase branch without explicit approval.
- Use either Supabase Local or an already-approved, non-production Supabase project.
- Do not use a blanket `supabase db push` on the current migration directory. The legacy Phase 1–5 filenames are not lexically ordered by phase.
- Apply the files below explicitly and stop immediately on the first SQL error.
- Phase 6 is out of scope.

## Canonical dependency map

Apply exactly in this order:

1. Base CRM foundation  
   `supabase/migrations/20261002095012_sav_ai_crm_isolated_foundation.sql`
2. Base public RPC facade  
   `supabase/migrations/20261002095133_sav_ai_crm_public_rpc_facade.sql`
3. Base operational reads  
   `supabase/migrations/20261002095224_sav_ai_crm_operational_reads.sql`
4. Phase 1 Tasks / Follow-up  
   `supabase/migrations/20261002_tasks_followup_module.sql`
5. Phase 2 AI Agents  
   `supabase/migrations/20261002_zz_ai_agents_phase2.sql`
6. Phase 3 Workflow Engine  
   `supabase/migrations/20261002_zzz_workflow_engine_phase3.sql`
7. Phase 4 Inbox / Channels  
   `supabase/migrations/20261002_aaaa_inbox_channels_phase4.sql`
8. Phase 5 Notifications  
   `supabase/migrations/20261002_bbbb_notifications_phase5.sql`

Dependency reasoning:

- The base foundation owns `workspaces`, `members`, `contacts`, `leads`, `tasks`, `activities`, `conversations`, `messages`, `ai_agents`, `workflows`, `integrations`, `audit_logs`, base RLS, and `sav_ai_crm.is_workspace_member`.
- Phase 1 extends the existing `tasks` and `activities` tables and adds the controlled task RPC boundary.
- Phase 2 requires Phase 1 because agent actions create/assign tasks and reference `tasks.assigned_agent_id`; it adds execution/action/approval/escalation tables.
- Phase 3 requires Phase 2 because AI workflow nodes delegate through the Phase 2 agent action boundary and workflow escalation links to Phase 2 records.
- Phase 4 reuses and alters the base `conversations` and `messages` tables; it depends on Phase 1 task RPCs, Phase 2 agents/actions/escalations, and Phase 3 workflow dispatch.
- Phase 5 reuses Phase 1 tasks, Phase 2 agents/actions, Phase 3 workflows/executions, and Phase 4 conversations/channel accounts.

Cross-phase `create or replace` overrides that are intentional:

- Phase 4 replaces `sav_ai_crm_create_workflow`, `sav_ai_crm_update_workflow`, and `sav_ai_crm_dispatch_workflow_event` with signature-compatible versions that recognize Inbox events.
- Phase 5 replaces `sav_ai_crm_run_workflow_execution(uuid)` with a signature-compatible runner that executes Phase 5 `NOTIFICATION` nodes.
- These are ordered overrides, not separate engines.

## Staging setup

### Option A — Supabase Local

Use a local Supabase stack with Docker/CLI. Do not link the repository to production.

Example:

```bash
supabase start
export STAGING_DB_URL='postgresql://postgres:postgres@127.0.0.1:54322/postgres'
```

### Option B — existing non-production Supabase project

Use an already-approved development project and its direct database URL.

Before running anything, verify the target manually. The target project ref **must** be `gsudlmrmrefqqodpdeug`.

Recommended shell guard:

```bash
if ! printf '%s' "$STAGING_DB_URL" | grep -q 'gsudlmrmrefqqodpdeug'; then
  echo "REFUSING: approved staging project not identified"
  exit 1
fi
```

Do not rely only on the guard: confirm the project in the Supabase dashboard too.

## Explicit migration execution

Run one file at a time. `ON_ERROR_STOP` is mandatory.

```bash
psql "$STAGING_DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261002095012_sav_ai_crm_isolated_foundation.sql
# run Base verification SQL below

psql "$STAGING_DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261002095133_sav_ai_crm_public_rpc_facade.sql
psql "$STAGING_DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261002095224_sav_ai_crm_operational_reads.sql
# run Base RPC verification SQL below

psql "$STAGING_DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261002_tasks_followup_module.sql
# run Phase 1 checks

psql "$STAGING_DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261002_zz_ai_agents_phase2.sql
# run Phase 2 checks

psql "$STAGING_DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261002_zzz_workflow_engine_phase3.sql
# run Phase 3 checks

psql "$STAGING_DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261002_aaaa_inbox_channels_phase4.sql
# run Phase 4 checks

psql "$STAGING_DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20261002_bbbb_notifications_phase5.sql
# run Phase 5 checks
```

Do not continue to the next phase when any verification query fails.

---

# Verification SQL

## 0. Base foundation

Expected base tables:

```sql
select c.table_name
from information_schema.tables c
where c.table_schema='sav_ai_crm'
  and c.table_name in (
    'workspaces','members','contacts','leads','deals','tasks','activities',
    'conversations','messages','ai_agents','workflows','workflow_runs',
    'integrations','audit_logs'
  )
order by c.table_name;
```

The result must contain all 14 names.

RLS must be enabled:

```sql
select c.relname,c.relrowsecurity
from pg_class c
join pg_namespace n on n.oid=c.relnamespace
where n.nspname='sav_ai_crm'
  and c.relname in (
    'workspaces','members','contacts','leads','deals','tasks','activities',
    'conversations','messages','ai_agents','workflows','workflow_runs',
    'integrations','audit_logs'
  )
order by c.relname;
```

Every `relrowsecurity` value must be `true`.

Base function checks:

```sql
select
  to_regprocedure('sav_ai_crm.is_workspace_member(uuid)') as workspace_member,
  to_regprocedure('public.sav_ai_crm_bootstrap_workspace(text)') as bootstrap,
  to_regprocedure('public.sav_ai_crm_workspace()') as workspace_rpc,
  to_regprocedure('public.sav_ai_crm_dashboard()') as dashboard,
  to_regprocedure('public.sav_ai_crm_list_leads(text,text)') as list_leads,
  to_regprocedure('public.sav_ai_crm_create_lead(text,text,text,text,text,text,numeric)') as create_lead,
  to_regprocedure('public.sav_ai_crm_tasks()') as base_tasks,
  to_regprocedure('public.sav_ai_crm_workflows()') as base_workflows,
  to_regprocedure('public.sav_ai_crm_conversations()') as base_conversations;
```

No field above may be null.

### Authenticated test identity

Create a dedicated staging auth user through Supabase Auth or the local Auth API. Do not reuse production credentials.

Record:

- `TEST_USER_UUID`
- `TEST_USER_EMAIL`

To simulate the authenticated JWT for SQL verification:

```sql
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub','<TEST_USER_UUID>',
    'role','authenticated',
    'email','<TEST_USER_EMAIL>',
    'app_metadata',jsonb_build_object()
  )::text,
  false
);
select set_config('request.jwt.claim.sub','<TEST_USER_UUID>',false);
```

Then bootstrap:

```sql
select public.sav_ai_crm_bootstrap_workspace('SAVRDH Staging Verification');
select public.sav_ai_crm_workspace();
```

Record the returned `workspace_id` as `WORKSPACE_A`.

---

## 1. Phase 1 — Tasks / Follow-up

Column checks:

```sql
select column_name,data_type
from information_schema.columns
where table_schema='sav_ai_crm' and table_name='tasks'
  and column_name in (
    'followup_type','reminder_at','reminder_sent_at','assigned_agent_id',
    'notes','archived_at','updated_at'
  )
order by column_name;

select column_name
from information_schema.columns
where table_schema='sav_ai_crm' and table_name='activities'
  and column_name='task_id';
```

FK/index checks:

```sql
select conname,pg_get_constraintdef(oid)
from pg_constraint
where conrelid in ('sav_ai_crm.tasks'::regclass,'sav_ai_crm.activities'::regclass)
  and conname in ('tasks_assigned_agent_id_fkey','activities_task_id_fkey');

select indexname
from pg_indexes
where schemaname='sav_ai_crm'
  and indexname in (
    'tasks_workspace_status_due_idx','tasks_workspace_assignee_idx',
    'tasks_workspace_agent_idx','tasks_workspace_reminder_idx',
    'activities_task_created_idx'
  )
order by indexname;
```

RPC checks:

```sql
select
 to_regprocedure('public.sav_ai_crm_task_context()'),
 to_regprocedure('public.sav_ai_crm_list_tasks(text,text,text,text,text,text)'),
 to_regprocedure('public.sav_ai_crm_task_detail(uuid)'),
 to_regprocedure('public.sav_ai_crm_create_task(text,text,text,text,text,timestamptz,timestamptz,uuid,uuid,text,text,uuid,uuid)'),
 to_regprocedure('public.sav_ai_crm_update_task(uuid,text,text,text,text,text,timestamptz,timestamptz,uuid,uuid,text,text,uuid,uuid)'),
 to_regprocedure('public.sav_ai_crm_set_task_status(uuid,text)'),
 to_regprocedure('public.sav_ai_crm_archive_task(uuid)'),
 to_regprocedure('public.sav_ai_crm_delete_task(uuid)'),
 to_regprocedure('public.sav_ai_crm_due_task_reminders()'),
 to_regprocedure('public.sav_ai_crm_agent_task_action(uuid,text,text)');
```

Every value must be non-null.

Verify anonymous execution is revoked:

```sql
select
 has_function_privilege('anon','public.sav_ai_crm_create_task(text,text,text,text,text,timestamptz,timestamptz,uuid,uuid,text,text,uuid,uuid)','EXECUTE') as anon_create,
 has_function_privilege('authenticated','public.sav_ai_crm_create_task(text,text,text,text,text,timestamptz,timestamptz,uuid,uuid,text,text,uuid,uuid)','EXECUTE') as authenticated_create;
```

Expected: `anon_create=false`, `authenticated_create=true`.

---

## 2. Phase 2 — AI Agents

Required tables:

```sql
select table_name
from information_schema.tables
where table_schema='sav_ai_crm'
  and table_name in (
    'ai_agents','ai_agent_capabilities','ai_agent_knowledge','ai_agent_workflows',
    'ai_agent_executions','ai_agent_actions','ai_agent_approvals','ai_agent_escalations'
  )
order by table_name;
```

All eight names must be present.

Required `ai_agents` extensions:

```sql
select column_name
from information_schema.columns
where table_schema='sav_ai_crm' and table_name='ai_agents'
  and column_name in (
    'display_name','avatar_icon','allowed_actions','knowledge_scopes','workflow_access',
    'task_permissions','escalation_rules','working_hours','daily_limits','confidence_threshold'
  )
order by column_name;
```

Execution RPC signatures:

```sql
select
 to_regprocedure('public.sav_ai_crm_create_agent_execution(uuid,text,jsonb)') as create_execution,
 to_regprocedure('public.sav_ai_crm_complete_agent_execution(uuid,jsonb,jsonb,text)') as complete_execution,
 to_regprocedure('public.sav_ai_crm_fail_agent_execution(uuid,text,jsonb)') as fail_execution,
 to_regprocedure('public.sav_ai_crm_agent_executions(uuid)') as execution_list,
 to_regprocedure('public.sav_ai_crm_request_agent_action(uuid,text,text,uuid,jsonb)') as request_action,
 to_regprocedure('public.sav_ai_crm_review_agent_action(uuid,text,text)') as review_action,
 to_regprocedure('public.sav_ai_crm_execute_agent_action(uuid)') as execute_action;
```

No value may be null.

Canonical SAV-Sales check:

```sql
select id,workspace_id,slug,name,status
from sav_ai_crm.ai_agents
where workspace_id='<WORKSPACE_A>'::uuid and slug='sav-sales';
```

Exactly one active row is expected.

### Runtime app_metadata identity

Record the SAV-Sales id as `SAV_SALES_AGENT_ID`.

```sql
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub','<TEST_USER_UUID>',
    'role','authenticated',
    'app_metadata',jsonb_build_object('sav_ai_agent_id','<SAV_SALES_AGENT_ID>')
  )::text,
  false
);
select sav_ai_crm.agent_runtime_id() as runtime_agent_id;
```

Expected: `runtime_agent_id = SAV_SALES_AGENT_ID`.

The runtime identity must come from `app_metadata`; no Phase 2 authorization path may depend on user-editable `user_metadata`.

### Workspace isolation

Create a second staging auth user/workspace (`USER_B`, `WORKSPACE_B`) and obtain one agent id from WORKSPACE_B.

Set the JWT back to USER_A and run:

```sql
select set_config('request.jwt.claim.sub','<USER_A_UUID>',false);
select set_config(
 'request.jwt.claims',
 jsonb_build_object('sub','<USER_A_UUID>','role','authenticated','app_metadata',jsonb_build_object())::text,
 false
);

with r as (
  select jsonb_array_elements(public.sav_ai_crm_agent_registry()) as item
)
select coalesce(bool_and((item->>'workspace_id')::uuid='<WORKSPACE_A>'::uuid),true) as isolated
from r;
```

Expected: `isolated=true`.

Calling:

```sql
select public.sav_ai_crm_agent_detail('<WORKSPACE_B_AGENT_ID>'::uuid);
```

must fail with `Agent not found`.

### Authenticated RBAC

Privilege boundary:

```sql
select
 has_function_privilege('anon','public.sav_ai_crm_create_agent_execution(uuid,text,jsonb)','EXECUTE') as anon_execute,
 has_function_privilege('authenticated','public.sav_ai_crm_create_agent_execution(uuid,text,jsonb)','EXECUTE') as authenticated_execute;
```

Expected: `false, true`.

For a staging member temporarily set to `viewer`, `sav_ai_crm_set_agent_status` must reject the operation with `Agent management not permitted`. Run the role change inside a transaction and roll it back after the negative test.

### Execution audit readiness

The Phase 2 migration must log:

- `agent.execution.created`
- `agent.execution.completed`
- `agent.execution.failed`

A lead-scoped completion/failure must create a corresponding CRM activity with `execution_id` and `agent_id` metadata.

---

## 3. Phase 3 — Workflow Engine

Tables:

```sql
select table_name
from information_schema.tables
where table_schema='sav_ai_crm'
  and table_name in (
    'workflows','workflow_versions','workflow_nodes','workflow_edges',
    'workflow_triggers','workflow_executions','workflow_node_executions',
    'workflow_approvals','workflow_templates'
  )
order by table_name;
```

RPCs:

```sql
select
 to_regprocedure('public.sav_ai_crm_workflow_registry()'),
 to_regprocedure('public.sav_ai_crm_workflow_metrics()'),
 to_regprocedure('public.sav_ai_crm_workflow_templates()'),
 to_regprocedure('public.sav_ai_crm_create_workflow(text,text,text,jsonb,uuid)'),
 to_regprocedure('public.sav_ai_crm_update_workflow(uuid,text,text,text,jsonb)'),
 to_regprocedure('public.sav_ai_crm_workflow_detail(uuid)'),
 to_regprocedure('public.sav_ai_crm_set_workflow_status(uuid,text)'),
 to_regprocedure('public.sav_ai_crm_duplicate_workflow(uuid)'),
 to_regprocedure('public.sav_ai_crm_archive_workflow(uuid)'),
 to_regprocedure('public.sav_ai_crm_dispatch_workflow_event(text,jsonb,text)'),
 to_regprocedure('public.sav_ai_crm_start_workflow(uuid,jsonb,text,text)'),
 to_regprocedure('public.sav_ai_crm_run_workflow_execution(uuid)'),
 to_regprocedure('public.sav_ai_crm_resume_workflow_execution(uuid)'),
 to_regprocedure('public.sav_ai_crm_workflow_execution_detail(uuid)'),
 to_regprocedure('public.sav_ai_crm_review_workflow_approval(uuid,text,text)');
```

No value may be null.

Confirm workflow nodes can delegate to the existing Phase 2 action boundary by verifying the Phase 3 source/runtime has `AI_AGENT` node support and `sav_ai_crm_request_agent_action` remains present.

---

## 4. Phase 4 — Inbox / Channels

Phase 4 must extend, not replace, the original conversation/message infrastructure.

Base tables must still exist:

```sql
select
 to_regclass('sav_ai_crm.conversations') as conversations,
 to_regclass('sav_ai_crm.messages') as messages;
```

Supporting tables:

```sql
select table_name
from information_schema.tables
where table_schema='sav_ai_crm'
  and table_name in (
    'conversation_participants','message_attachments','conversation_assignments',
    'conversation_tags','channel_accounts','message_delivery_events',
    'conversation_activity','channel_webhook_events'
  )
order by table_name;
```

Core RPCs:

```sql
select
 to_regprocedure('public.sav_ai_crm_inbox_context()'),
 to_regprocedure('public.sav_ai_crm_inbox_conversations(text,text,text,boolean,text)'),
 to_regprocedure('public.sav_ai_crm_inbox_conversation_detail(uuid)'),
 to_regprocedure('public.sav_ai_crm_create_conversation(text,text,uuid,uuid,text,text)'),
 to_regprocedure('public.sav_ai_crm_assign_conversation(uuid,text,uuid,uuid,text)'),
 to_regprocedure('public.sav_ai_crm_queue_outbound_message(uuid,text,text,text,uuid,jsonb)'),
 to_regprocedure('public.sav_ai_crm_inbox_create_task(uuid,text,text,text,text,timestamptz,timestamptz,text,uuid,uuid)'),
 to_regprocedure('public.sav_ai_crm_request_conversation_ai(uuid,uuid,text,text)'),
 to_regprocedure('public.sav_ai_crm_channel_accounts()'),
 to_regprocedure('public.sav_ai_crm_upsert_channel_account(uuid,text,text,text,text,text,text,jsonb,text)');
```

No value may be null.

Webhook mutation helpers must not be callable by anonymous/authenticated user clients unless explicitly designed as a public authenticated RPC. Verify service-only functions with `has_function_privilege`.

No channel provider should report delivery success without a real provider result.

---

## 5. Phase 5 — Notifications

Tables:

```sql
select table_name
from information_schema.tables
where table_schema='sav_ai_crm'
  and table_name in (
    'notifications','notification_recipients','notification_deliveries',
    'notification_preferences','notification_templates','notification_events',
    'notification_schedules','notification_digests','notification_devices'
  )
order by table_name;
```

Cross-boundary FK checks:

```sql
select conrelid::regclass as table_name,conname,pg_get_constraintdef(oid)
from pg_constraint
where contype='f'
  and connamespace='sav_ai_crm'::regnamespace
  and conrelid in (
    'sav_ai_crm.notifications'::regclass,
    'sav_ai_crm.notification_recipients'::regclass,
    'sav_ai_crm.notification_deliveries'::regclass
  )
order by table_name::text,conname;
```

The notification model must reference the already-created workspace/member/task/workflow/workflow-execution/conversation/agent boundaries rather than recreate them.

RPC checks:

```sql
select
 to_regprocedure('public.sav_ai_crm_notification_context()'),
 to_regprocedure('public.sav_ai_crm_notifications(text,text,text,text,text,uuid,text,uuid,uuid,text,timestamptz,timestamptz)'),
 to_regprocedure('public.sav_ai_crm_create_notification(text,text,text,text,text,uuid,text,text,uuid,text,timestamptz,uuid,uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text,boolean)'),
 to_regprocedure('public.sav_ai_crm_notification_prepare_send(uuid)'),
 to_regprocedure('public.sav_ai_crm_notification_record_result(uuid,boolean,text,text,text,text,text,jsonb,boolean)'),
 to_regprocedure('public.sav_ai_crm_notification_retry(uuid)'),
 to_regprocedure('public.sav_ai_crm_sync_task_notifications()'),
 to_regprocedure('public.sav_ai_crm_queue_approved_agent_notification(uuid)'),
 to_regprocedure('public.sav_ai_crm_finalize_agent_notification(uuid,uuid,boolean,text)'),
 to_regprocedure('public.sav_ai_crm_run_workflow_execution(uuid)');
```

Task trigger:

```sql
select tgname
from pg_trigger
where tgrelid='sav_ai_crm.tasks'::regclass
  and not tgisinternal
  and tgname='trg_task_notification_sync';
```

Expected: one row.

---

# First controlled SAV-Sales real execution

This test is allowed only after all preceding phases pass in staging.

## Provider preflight

Current source has a provider-neutral interface in `lib/ai/provider.ts`.

The current implementation requires:

1. a server-side `AI_API_KEY`, and
2. a real provider adapter installed behind `getAIProvider()`.

At this gate, a key alone is **not sufficient**: the current fallback deliberately returns `AI_PROVIDER_ERROR` when credentials are present but no real provider adapter is installed.

Expected errors:

- no credential: `AI_PROVIDER_NOT_CONFIGURED`
- credential present but adapter unavailable/provider failure: `AI_PROVIDER_ERROR`
- missing database/RPC objects: `DATABASE_NOT_READY`

Never substitute a fake plan.

## Safe test lead

Use a staging-only lead. Example through the authenticated base RPC:

```sql
select public.sav_ai_crm_create_lead(
  'SAV-Sales Staging Test Lead',
  'Verification Company',
  'staging-test@example.invalid',
  '0000000000',
  'manual',
  'medium',
  0
) as lead_id;
```

Record the returned `LEAD_ID`.

Get SAV-Sales:

```sql
select id
from sav_ai_crm.ai_agents
where workspace_id='<WORKSPACE_A>'::uuid
  and slug='sav-sales'
  and status='active';
```

Record `SAV_SALES_AGENT_ID`.

## Safe command

Use exactly a planning-only command such as:

> Analyze this CRM lead and propose a safe next follow-up plan. Do not send WhatsApp, SMS, email, make financial changes, delete records, or perform any irreversible action.

Call the hosted/staging API with the authenticated staging user:

```http
POST /api/agents/<SAV_SALES_AGENT_ID>/execute
Content-Type: application/json
Authorization: Bearer <STAGING_USER_JWT>

{
  "command": "Analyze this CRM lead and propose a safe next follow-up plan. Do not send WhatsApp, SMS, email, make financial changes, delete records, or perform any irreversible action.",
  "context": {
    "lead_id": "<LEAD_ID>"
  }
}
```

The first real test must not call:

- WhatsApp
- SMS
- Email
- Voice
- financial actions
- delete/archive/permanent-delete actions
- bulk messaging
- any external tool with irreversible effect

## Verify result persistence

After the API returns:

```sql
select id,agent_id,requested_by,command,input,planned_action,approval_status,
       execution_status,output,error,started_at,completed_at,created_at
from sav_ai_crm.ai_agent_executions
where agent_id='<SAV_SALES_AGENT_ID>'::uuid
order by created_at desc
limit 5;
```

Expected successful test:

- one execution for the command
- `execution_status='completed'`
- a real provider-generated `planned_action`
- non-null output
- no external message/action records created by this test

Audit:

```sql
select action,entity_type,entity_id,metadata,created_at
from sav_ai_crm.audit_logs
where entity_type='ai_agent_execution'
order by created_at desc
limit 10;
```

Expected: `agent.execution.created` and `agent.execution.completed`.

Lead activity:

```sql
select activity_type,title,description,channel,metadata,created_at
from sav_ai_crm.activities
where lead_id='<LEAD_ID>'::uuid
  and activity_type in ('agent_execution_completed','agent_execution_failed')
order by created_at desc
limit 10;
```

For a successful plan, expect `agent_execution_completed`.

If provider configuration is missing/unavailable, expect the execution to fail honestly and verify:

- `execution_status='failed'`
- exact provider error persisted
- `agent.execution.failed` audit event
- `agent_execution_failed` lead activity
- no fabricated plan

## Gate completion criteria

The Phase 1–5 database gate is PASS only when:

- every migration applies sequentially in the approved staging environment with `ON_ERROR_STOP`
- every post-phase verification query passes
- anonymous RPC protection is confirmed
- workspace isolation and RBAC negative tests pass
- first SAV-Sales planning-only execution either:
  - succeeds using a real provider and persists execution/audit/activity, or
  - fails with the exact real provider configuration/error state, without mock output
- no external delivery or irreversible action occurs

Only after this gate passes should production migration planning be considered. This document does not authorize production changes.
