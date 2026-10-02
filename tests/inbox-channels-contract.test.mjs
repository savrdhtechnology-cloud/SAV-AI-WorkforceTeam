import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const migration=readFileSync(new URL("../supabase/migrations/20261002_aaaa_inbox_channels_phase4.sql",import.meta.url),"utf8");
const adapter=readFileSync(new URL("../lib/channels/adapter.ts",import.meta.url),"utf8");
const registry=readFileSync(new URL("../lib/channels/server-registry.ts",import.meta.url),"utf8");
const dispatch=readFileSync(new URL("../lib/channels/message-dispatch.ts",import.meta.url),"utf8");
const inboxTypes=readFileSync(new URL("../app/crm/inbox/inbox-types.ts",import.meta.url),"utf8");
const inboxUi=readFileSync(new URL("../app/crm/inbox/InboxModule.tsx",import.meta.url),"utf8");
const inboxService=readFileSync(new URL("../app/crm/inbox/inbox-service.ts",import.meta.url),"utf8");
const webhook=readFileSync(new URL("../app/api/inbox/webhooks/[channel]/route.ts",import.meta.url),"utf8");
const messageApi=readFileSync(new URL("../app/api/inbox/messages/route.ts",import.meta.url),"utf8");
const channelsApi=readFileSync(new URL("../app/api/inbox/channels/route.ts",import.meta.url),"utf8");
const workflowTypes=readFileSync(new URL("../app/crm/workflows/workflow-types.ts",import.meta.url),"utf8");

test("Phase 4 migration extends existing conversations and messages in-place",()=>{
  assert.match(migration,/alter table sav_ai_crm\.conversations/);
  assert.match(migration,/alter table sav_ai_crm\.messages/);
  for(const field of ["priority","assigned_agent_id","unread_count","last_message_preview","archived_at","updated_at"])assert.match(migration,new RegExp(field));
  for(const field of ["channel","sender","recipient","message_type","is_read","read_at","sent_by_member_id","sent_by_agent_id","error_code","error_message"])assert.match(migration,new RegExp(field));
});

test("Phase 4 creates all required supporting Inbox tables",()=>{
  for(const table of ["conversation_participants","message_attachments","conversation_assignments","conversation_tags","channel_accounts","message_delivery_events","conversation_activity","channel_webhook_events"]){
    assert.match(migration,new RegExp("create table if not exists sav_ai_crm\\."+table));
  }
});

test("typed message model contains required fields and delivery states",()=>{
  for(const field of ["conversation_id","channel","direction","sender","recipient","message_type","provider_message_id","delivery_status","is_read","sent_by_member_id","sent_by_agent_id","error_code","error_message","created_at"])assert.match(inboxTypes,new RegExp(field));
  for(const status of ["QUEUED","SENDING","SENT","DELIVERED","READ","FAILED"]){assert.match(inboxTypes,new RegExp('"'+status+'"'));assert.match(migration,new RegExp("'"+status+"'"));}
});

test("provider-neutral adapter exposes the required five methods",()=>{
  for(const method of ["sendMessage","receiveMessage","getDeliveryStatus","verifyWebhook","normalizeInboundMessage"])assert.match(adapter,new RegExp(method));
  for(const channel of ["whatsapp","email","sms","voice","webchat"])assert.match(adapter,new RegExp('"'+channel+'"'));
});

test("unconfigured adapters fail closed and never fabricate delivery",()=>{
  assert.match(adapter,/CHANNEL_PROVIDER_NOT_CONFIGURED/);
  assert.match(adapter,/UnconfiguredChannelAdapter/);
  assert.doesNotMatch(adapter,/providerMessageId:["'](?:fake|demo|mock)/i);
  assert.match(dispatch,/sav_ai_crm_record_message_result/);
  assert.match(dispatch,/MESSAGE_FAILED/);
});

test("channel registry is server-only and frontend cannot inject raw credentials",()=>{
  assert.match(registry,/import "server-only"/);
  assert.match(registry,/getChannelAdapter/);
  assert.match(channelsApi,/RAW_CREDENTIALS_FORBIDDEN/);
  assert.match(channelsApi,/"credentials" in b/);
  assert.match(channelsApi,/"apiKey" in b/);
  assert.match(migration,/secret_ref/);
});

test("webhook verifies signature before normalization and persistence",()=>{
  const verify=webhook.indexOf("verifyWebhook");
  const normalize=webhook.indexOf("normalizeInboundMessage");
  const persist=webhook.indexOf("sav_ai_crm_persist_inbound_message");
  assert.ok(verify>=0&&normalize>verify&&persist>normalize);
  assert.match(webhook,/WEBHOOK_SIGNATURE_INVALID/);
  assert.match(webhook,/serverAdminSupabase/);
  assert.match(webhook,/dispatch_workflow_event_system/);
});

test("webhook and delivery persistence are idempotent",()=>{
  assert.match(migration,/unique\(workspace_id,provider,provider_event_id\)/);
  assert.match(migration,/delivery_events_provider_event_uq/);
  assert.match(migration,/provider_message_id/);
  assert.match(migration,/duplicate/);
  assert.match(migration,/on conflict\(workspace_id,provider,provider_event_id\) do nothing/);
});

test("workspace isolation and employee conversation scoping are server enforced",()=>{
  assert.match(migration,/inbox_current_member/);
  assert.match(migration,/inbox_can_access/);
  assert.match(migration,/c\.workspace_id=me\.workspace_id/);
  assert.match(migration,/p_member_id.*p_assigned_to/s);
  assert.match(migration,/Lead outside workspace/);
  assert.match(migration,/Contact outside workspace/);
});

test("RBAC keeps viewer read-only and channel management owner-admin only",()=>{
  assert.match(migration,/inbox_can_write/);
  assert.match(migration,/me\.role='viewer'/);
  assert.match(migration,/me\.role not in \('owner','admin'\)/);
  assert.match(migration,/Conversation assignment not permitted/);
  assert.match(migration,/Channel management requires owner or admin/);
});

test("AI identity and send approval use Phase 2 capability boundary",()=>{
  assert.match(migration,/sav_ai_crm_request_agent_action\(agent\.id,'SEND_MESSAGE'/);
  assert.match(migration,/AI agent lacks channel SEND_MESSAGE capability/);
  assert.match(migration,/Human approval required/);
  assert.match(migration,/sav_ai_crm_queue_approved_agent_message/);
  assert.match(migration,/sav_ai_crm_finalize_agent_message_action/);
  assert.doesNotMatch(migration,/user_metadata/);
  assert.doesNotMatch(messageApi,/user_metadata/);
});

test("AI drafts cannot silently send and provider absence is explicit",()=>{
  assert.match(migration,/send_requires_approval/);
  assert.match(messageApi,/approval_required/);
  assert.match(inboxUi,/Send Approved AI Reply/);
  assert.match(inboxUi,/AI draft created\. Sending remains separately controlled/);
});

test("Inbox task and follow-up creation reuse Phase 1 task RPC",()=>{
  assert.match(migration,/sav_ai_crm_inbox_create_task/);
  assert.match(migration,/public\.sav_ai_crm_create_task/);
  assert.match(inboxService,/\/api\/inbox\/tasks/);
  assert.match(inboxService,/\/api\/inbox\/followups/);
});

test("Inbox channel events extend the existing Phase 3 workflow engine",()=>{
  for(const event of ["CONVERSATION_CREATED","CONVERSATION_ASSIGNED","MESSAGE_RECEIVED","MESSAGE_DELIVERED","MESSAGE_FAILED","CONVERSATION_CLOSED","CONVERSATION_REOPENED"]){
    assert.match(migration,new RegExp("'"+event+"'"));
    assert.match(workflowTypes,new RegExp('"'+event+'"'));
  }
  assert.match(migration,/sav_ai_crm_dispatch_workflow_event/);
  assert.match(migration,/workflow_executions/);
  assert.doesNotMatch(migration,/create table if not exists sav_ai_crm\.inbox_workflows/);
});

test("conversation escalation reuses Phase 2 escalation records",()=>{
  assert.match(migration,/sav_ai_crm_escalate_conversation/);
  assert.match(migration,/ai_agent_escalations/);
  assert.match(migration,/CUSTOMER_REQUESTED_HUMAN/);
});

test("audit and activity records cover required Inbox operations",()=>{
  for(const action of ["conversation_created","message_received","message_sent","provider_failure","assignment","ai_assignment","escalation","conversation_archived","task_created","followup_created"]){
    assert.match(migration,new RegExp(action));
  }
  assert.match(migration,/'conversation_'\|\|p_action/);
  assert.match(migration,/inbox\.conversation\.'\|\|p_action/);
  assert.match(migration,/inbox\.message\.queued/);
  assert.match(migration,/inbox\.delivery\.update/);
  assert.match(migration,/inbox\.channel\.configure/);
});

test("public Inbox RPCs revoke anonymous execution",()=>{
  for(const fn of [
    "sav_ai_crm_inbox_context","sav_ai_crm_inbox_conversations","sav_ai_crm_inbox_conversation_detail",
    "sav_ai_crm_create_conversation","sav_ai_crm_update_conversation","sav_ai_crm_assign_conversation",
    "sav_ai_crm_set_conversation_state","sav_ai_crm_escalate_conversation","sav_ai_crm_queue_outbound_message",
    "sav_ai_crm_queue_approved_agent_message","sav_ai_crm_finalize_agent_message_action","sav_ai_crm_mark_message_sending",
    "sav_ai_crm_record_message_result","sav_ai_crm_mark_message_read","sav_ai_crm_add_internal_note",
    "sav_ai_crm_inbox_create_task","sav_ai_crm_request_conversation_ai","sav_ai_crm_ai_draft_context",
    "sav_ai_crm_channel_accounts","sav_ai_crm_upsert_channel_account"
  ]) assert.match(migration,new RegExp("revoke all on function public\\."+fn+"[\\s\\S]*?from public,anon"));
});

test("private webhook mutation RPCs are not available to authenticated clients",()=>{
  assert.match(migration,/sav_ai_crm_resolve_channel_account[\s\S]*from public,anon,authenticated/);
  assert.match(migration,/sav_ai_crm_persist_inbound_message[\s\S]*from public,anon,authenticated/);
  assert.match(migration,/sav_ai_crm_apply_delivery_event[\s\S]*from public,anon,authenticated/);
  assert.match(migration,/dispatch_workflow_event_system[\s\S]*from public,anon,authenticated/);
  assert.match(migration,/to service_role/);
});

test("authenticated Inbox API surface is complete",()=>{
  for(const fragment of [
    "/api/inbox/conversations","/assign","/close","/reopen","/escalate","/api/inbox/messages",
    "/retry","/read","/draft","/api/inbox/tasks","/api/inbox/followups"
  ]) assert.ok(inboxService.includes(fragment),`missing client API fragment: ${fragment}`);
});

test("Inbox UI exposes required operator controls and states",()=>{
  for(const text of ["Search conversations","All channels","Unread","Assign human","Assign AI","Follow-up","Escalate","Link lead","Link customer/contact","Add internal note","AI Draft","Send","Conversation Activity","Channels"]){
    assert.match(inboxUi,new RegExp(text.replace(/[.*+?^$()|[\]{}]/g,"\\$&")));
  }
  assert.match(inboxUi,/CHANNEL_PROVIDER_NOT_CONFIGURED|External delivery is only confirmed/);
});
