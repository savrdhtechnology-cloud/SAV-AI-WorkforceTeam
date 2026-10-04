import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const migration=readFileSync(new URL("../supabase/migrations/20261002_bbbb_notifications_phase5.sql",import.meta.url),"utf8");
const types=readFileSync(new URL("../app/crm/notifications/notification-types.ts",import.meta.url),"utf8");
const service=readFileSync(new URL("../app/crm/notifications/notification-service.ts",import.meta.url),"utf8");
const ui=readFileSync(new URL("../app/crm/notifications/NotificationsModule.tsx",import.meta.url),"utf8");
const bell=readFileSync(new URL("../app/crm/notifications/NotificationBell.tsx",import.meta.url),"utf8");
const detail=readFileSync(new URL("../app/crm/notifications/NotificationDetailView.tsx",import.meta.url),"utf8");
const dispatch=readFileSync(new URL("../lib/notifications/dispatch.ts",import.meta.url),"utf8");
const push=readFileSync(new URL("../lib/notifications/push-adapter.ts",import.meta.url),"utf8");
const webhook=readFileSync(new URL("../lib/notifications/webhook-adapter.ts",import.meta.url),"utf8");
const channelAdapter=readFileSync(new URL("../lib/channels/adapter.ts",import.meta.url),"utf8");
const agentTypes=readFileSync(new URL("../app/crm/agents/agent-types.ts",import.meta.url),"utf8");
const workflowTypes=readFileSync(new URL("../app/crm/workflows/workflow-types.ts",import.meta.url),"utf8");
const workflowUi=readFileSync(new URL("../app/crm/workflows/WorkflowsModule.tsx",import.meta.url),"utf8");
const crmPage=readFileSync(new URL("../app/crm/page.tsx",import.meta.url),"utf8");
const inbound=readFileSync(new URL("../app/api/inbox/webhooks/[channel]/route.ts",import.meta.url),"utf8");
const delivery=readFileSync(new URL("../app/api/inbox/webhooks/[channel]/delivery/route.ts",import.meta.url),"utf8");

test("Phase 5 creates the required notification persisted structures",()=>{
 for(const table of ["notifications","notification_recipients","notification_deliveries","notification_preferences","notification_templates","notification_events","notification_schedules","notification_digests","notification_devices"]){
  assert.match(migration,new RegExp("create table if not exists sav_ai_crm\\."+table));
 }
});

test("notification record supports required identity, source, relation and timing fields",()=>{
 for(const field of ["workspace_id","recipient_member_id","recipient_address","notification_type","title","body","priority","channel","status","source_type","source_id","lead_id","contact_id","task_id","workflow_id","workflow_execution_id","conversation_id","agent_id","scheduled_at","next_attempt_at","retry_count","sent_at","delivered_at","read_at","failed_at","error_code","error_message","metadata","idempotency_key","created_at","updated_at"])assert.match(migration,new RegExp(field));
});

test("typed notification registry covers system CRM AI workflow inbox and reminders",()=>{
 for(const type of ["SYSTEM_NOTIFICATION","SECURITY_NOTIFICATION","ACCOUNT_NOTIFICATION","LEAD_NOTIFICATION","CUSTOMER_NOTIFICATION","TASK_NOTIFICATION","FOLLOWUP_NOTIFICATION","ASSIGNMENT_NOTIFICATION","ESCALATION_NOTIFICATION","AI_AGENT_NOTIFICATION","AI_ACTION_NOTIFICATION","AI_APPROVAL_REQUEST","AI_ACTION_COMPLETED","AI_ACTION_FAILED","WORKFLOW_STARTED","WORKFLOW_COMPLETED","WORKFLOW_FAILED","WORKFLOW_APPROVAL_REQUIRED","WORKFLOW_RETRY","WORKFLOW_ESCALATION","NEW_CONVERSATION","NEW_INBOUND_MESSAGE","MESSAGE_DELIVERY_UPDATE","CONVERSATION_ASSIGNMENT","CONVERSATION_ESCALATION","TASK_REMINDER","FOLLOWUP_REMINDER","SCHEDULED_REMINDER","OVERDUE_REMINDER"]){
  assert.match(types,new RegExp('"'+type+'"'));
 }
});

test("all Phase 5 channels and delivery states are explicit",()=>{
 for(const channel of ["in_app","email","whatsapp","sms","push","webhook"])assert.match(types,new RegExp('"'+channel+'"'));
 for(const status of ["QUEUED","SCHEDULED","SENDING","SENT","DELIVERED","READ","FAILED","CANCELLED","WAITING_APPROVAL","RETRYING"]){assert.match(types,new RegExp('"'+status+'"'));assert.match(migration,new RegExp("'"+status+"'"));}
});

test("in-app notification center supports unread list, mark read/unread and mark all read",()=>{
 assert.match(bell,/read=unread/);assert.match(bell,/markNotificationRead/);assert.match(bell,/markAllNotificationsRead/);
 assert.match(service,/markNotificationUnread/);assert.match(service,/markAllNotificationsRead/);
 assert.match(migration,/sav_ai_crm_notification_mark_read/);assert.match(migration,/sav_ai_crm_notifications_mark_all_read/);
});

test("notification dashboard exposes requested metrics, filters, recent and upcoming states",()=>{
 for(const label of ["Total","Unread","Read","Scheduled","Sent","Delivered","Failed","Cancelled","Approval","Recent Notifications","Upcoming"])assert.match(ui,new RegExp(label));
 for(const filter of ["All channels","All types","All status","All priority","All recipients","All AI agents","All workflows","Read \\+ unread"])assert.match(ui,new RegExp(filter));
 assert.match(ui,/type="date"/);
});

test("scheduling is persisted and worker-based with no server sleeps",()=>{
 assert.match(migration,/notification_schedules/);assert.match(migration,/scheduled_at/);assert.match(migration,/next_attempt_at/);assert.match(migration,/recurrence_rule/);
 assert.match(migration,/sav_ai_crm_notification_due_ids/);assert.match(migration,/sav_ai_crm_notification_due_worker/);
 assert.doesNotMatch(migration,/pg_sleep|sleep\(/i);assert.doesNotMatch(dispatch,/setTimeout\(/);
 assert.match(service,/runDueWorker/);
});

test("task and follow-up reminders reuse existing tasks table rather than duplicate task logic",()=>{
 assert.match(migration,/sync_task_notification_trigger/);assert.match(migration,/on sav_ai_crm\.tasks/);
 assert.match(migration,/TASK_REMINDER/);assert.match(migration,/FOLLOWUP_REMINDER/);assert.match(migration,/OVERDUE_REMINDER/);
 assert.match(migration,/sav_ai_crm_sync_task_notifications/);
 assert.doesNotMatch(migration,/create table if not exists sav_ai_crm\.notification_tasks/);
});

test("workflow NOTIFICATION node is wired into the existing Phase 3 runner",()=>{
 assert.match(workflowTypes,/"NOTIFICATION"/);assert.match(workflowUi,/type==="NOTIFICATION"/);
 assert.match(migration,/workflow_create_notification/);assert.match(migration,/n\.node_type='NOTIFICATION'/);assert.match(migration,/sav_ai_crm_run_workflow_execution/);
 assert.doesNotMatch(migration,/create table if not exists sav_ai_crm\.notification_workflows/);
});

test("Inbox events create Phase 5 notifications without duplicating conversation infrastructure",()=>{
 assert.match(inbound,/create_notification_system/);assert.match(inbound,/NEW_CONVERSATION/);assert.match(inbound,/NEW_INBOUND_MESSAGE/);
 assert.match(delivery,/MESSAGE_DELIVERY_UPDATE/);assert.match(delivery,/create_notification_system/);
 assert.doesNotMatch(migration,/create table if not exists sav_ai_crm\.notification_conversations/);
});

test("AI notification requests use server-controlled Phase 2 capability and approval path",()=>{
 assert.match(agentTypes,/"SEND_NOTIFICATION"/);assert.match(agentTypes,/SEND_NOTIFICATION:"high"/);
 assert.match(migration,/ai_agent_capabilities/);assert.match(migration,/SEND_NOTIFICATION/);assert.match(migration,/queue_approved_agent_notification/);assert.match(migration,/Human approval required/);
 assert.match(migration,/sav_ai_crm_request_agent_action|ai_agent_actions/);
 assert.doesNotMatch(migration,/user_metadata/);assert.doesNotMatch(agentTypes,/user_metadata/);
});

test("Email WhatsApp and SMS reuse Phase 4 channel adapter",()=>{
 assert.match(dispatch,/resolveChannelAdapter/);assert.match(dispatch,/adapter\.sendMessage/);
 for(const channel of ["email","whatsapp","sms"])assert.match(channelAdapter,new RegExp('"'+channel+'"'));
});

test("external provider absence fails closed and never fabricates success",()=>{
 assert.match(channelAdapter,/CHANNEL_PROVIDER_NOT_CONFIGURED/);
 assert.match(push,/PUSH_PROVIDER_NOT_CONFIGURED/);assert.match(webhook,/WEBHOOK_PROVIDER_NOT_CONFIGURED/);
 assert.match(dispatch,/recordFailure/);assert.match(dispatch,/CHANNEL_PROVIDER_NOT_CONFIGURED/);
 assert.doesNotMatch(dispatch,/providerMessageId:["'](?:fake|mock|demo)/i);
});

test("push adapter has register unregister send and delivery boundaries",()=>{
 for(const method of ["registerDevice","unregisterDevice","sendPush","getDeliveryStatus"])assert.match(push,new RegExp(method));
 assert.match(migration,/notification_devices/);assert.match(migration,/device_token_hash/);assert.match(migration,/encrypted_device_ref/);
});

test("webhook notification adapter has signature, idempotency and failure boundaries",()=>{
 assert.match(webhook,/createSignature/);assert.match(webhook,/sendWebhook/);assert.match(webhook,/getDeliveryStatus/);
 assert.match(migration,/idempotency_key/);assert.match(migration,/unique\(workspace_id,idempotency_key\)/);
 assert.doesNotMatch(webhook,/secret\s*:/i);
});

test("retry policy is bounded and provider configuration failures do not loop",()=>{
 assert.match(migration,/max_retries/);assert.match(migration,/retry_count/);assert.match(migration,/next_attempt_at/);assert.match(migration,/Notification retry limit exceeded/);
 assert.match(migration,/Provider configuration required before retry/);
 assert.match(migration,/CHANNEL_PROVIDER_NOT_CONFIGURED/);assert.match(migration,/PUSH_PROVIDER_NOT_CONFIGURED/);assert.match(migration,/WEBHOOK_PROVIDER_NOT_CONFIGURED/);
});

test("template system is versioned and rendering forbids executable expressions",()=>{
 assert.match(migration,/notification_templates/);assert.match(migration,/version integer/);assert.match(migration,/render_notification_template/);
 assert.match(migration,/Executable template expressions are not allowed/);assert.match(migration,/Invalid template variable/);assert.match(migration,/unresolved variables/);
 assert.match(ui,/\{\{task\.title\}\}/);
});

test("preferences support categories channels quiet hours digests and critical security protection",()=>{
 for(const category of ["task_reminders","followups","ai_alerts","workflow_alerts","inbox_alerts","escalation_alerts","system_alerts","system_security"])assert.match(ui,new RegExp(category));
 assert.match(migration,/quiet_hours_start/);assert.match(migration,/quiet_hours_end/);assert.match(migration,/digest_frequency/);
 assert.match(migration,/Critical security notifications cannot be disabled/);assert.match(migration,/NOTIFICATION_DISABLED_BY_PREFERENCE/);
 assert.match(migration,/notification_digests/);
});

test("workspace and recipient authorization are enforced server-side",()=>{
 assert.match(migration,/Recipient outside workspace/);assert.match(migration,/External recipient requires owner or admin/);
 assert.match(migration,/workspace_id=me\.workspace_id/);assert.match(migration,/AI agent outside workspace/);assert.match(migration,/Workflow outside workspace/);assert.match(migration,/Conversation outside workspace/);assert.match(migration,/Task outside workspace/);
});

test("RBAC keeps viewer read-only and management actions constrained",()=>{
 assert.match(migration,/notification_can_manage/);assert.match(migration,/notification_can_create/);
 assert.match(migration,/me\.role not in \('owner','admin'\)/);assert.match(migration,/me\.role='viewer'/);
 assert.match(migration,/Template management requires owner or admin/);
});

test("security-definer public Phase 5 RPCs explicitly revoke anonymous execution",()=>{
 for(const fn of ["sav_ai_crm_notification_context","sav_ai_crm_notifications","sav_ai_crm_notification_metrics","sav_ai_crm_notification_upcoming","sav_ai_crm_notification_detail","sav_ai_crm_create_notification","sav_ai_crm_update_notification","sav_ai_crm_notification_prepare_send","sav_ai_crm_notification_record_result","sav_ai_crm_notification_mark_read","sav_ai_crm_notifications_mark_all_read","sav_ai_crm_notification_cancel","sav_ai_crm_notification_retry","sav_ai_crm_notification_preferences","sav_ai_crm_update_notification_preference","sav_ai_crm_notification_templates","sav_ai_crm_save_notification_template","sav_ai_crm_notification_schedules","sav_ai_crm_save_notification_schedule","sav_ai_crm_notification_channels","sav_ai_crm_notification_due_worker","sav_ai_crm_notification_due_ids","sav_ai_crm_sync_task_notifications","sav_ai_crm_queue_approved_agent_notification","sav_ai_crm_finalize_agent_notification"]){
  assert.match(migration,new RegExp("revoke all on function public\\."+fn+"[\\s\\S]*?from public,anon"));
 }
});

test("system notification helper is service-role only",()=>{
 assert.match(migration,/create_notification_system/);
 assert.match(migration,/from public,anon,authenticated/);
 assert.match(migration,/to service_role/);
});

test("audit logging covers creation queue schedule send delivery read fail retry cancel preferences templates and channel changes",()=>{
 for(const action of ["notification.created","notification.read","notification.retried","notification.cancelled","notification.preference.changed","notification.template.changed","notification.channel.changed"]){
  assert.match(migration,new RegExp(action.replace(".","\\.")));
 }
 assert.match(migration,/notification\.'\|\|lower\(initial_status\)/);assert.match(migration,/notification\.'\|\|lower\(final_status\)/);
});

test("API client exposes requested Phase 5 authenticated routes",()=>{
 for(const frag of ["/api/notifications","/read","/unread","/read-all","/retry","/cancel","/preferences","/templates","/channels","/schedules"])assert.ok(service.includes(frag),"missing "+frag);
});

test("CRM shell exposes Notifications and in-app bell",()=>{
 assert.match(crmPage,/NotificationsModule/);assert.match(crmPage,/NotificationBell/);assert.match(crmPage,/label: "Notifications"/);
 assert.match(detail,/Delivery Timeline/);assert.match(detail,/Open related CRM object/);
});
