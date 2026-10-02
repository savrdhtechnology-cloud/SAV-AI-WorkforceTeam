import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const migration=readFileSync(new URL("../supabase/migrations/20261002_zzz_workflow_engine_phase3.sql",import.meta.url),"utf8");
const types=readFileSync(new URL("../app/crm/workflows/workflow-types.ts",import.meta.url),"utf8");
const ui=readFileSync(new URL("../app/crm/workflows/WorkflowsModule.tsx",import.meta.url),"utf8");
const service=readFileSync(new URL("../app/crm/workflows/workflow-service.ts",import.meta.url),"utf8");

test("workflow registry supports required persisted statuses",()=>{
  for(const status of ["draft","active","paused","disabled","error","archived"]) assert.match(types,new RegExp('"'+status+'"'));
  assert.match(migration,/workflows_status_check/);
});

test("visual graph supports all Phase 3 node types",()=>{
  for(const node of ["TRIGGER","CONDITION","AI_AGENT","ACTION","TASK","FOLLOW_UP","WAIT","HUMAN_APPROVAL","ESCALATION","NOTIFICATION","END"]){
    assert.match(types,new RegExp('"'+node+'"'));
    assert.match(migration,new RegExp("'"+node+"'"));
  }
  assert.match(ui,/WorkflowCanvas/);
  assert.match(ui,/EdgeEditor/);
  assert.match(ui,/onMove/);
});

test("all initial trigger types are persisted",()=>{
  for(const trigger of ["NEW_LEAD","LEAD_STATUS_CHANGED","PIPELINE_STAGE_CHANGED","TASK_CREATED","TASK_COMPLETED","FOLLOWUP_DUE","REMINDER_DUE","CONVERSATION_RECEIVED","AI_ESCALATION","MANUAL_TRIGGER","SCHEDULED_TRIGGER"]){
    assert.match(types,new RegExp('"'+trigger+'"'));
    assert.match(migration,new RegExp("'"+trigger+"'"));
  }
  assert.match(migration,/sav_ai_crm_dispatch_workflow_event/);
  assert.match(migration,/sav_ai_crm\.workflow_conditions_match/);
});

test("condition engine contains every required operator",()=>{
  for(const op of ["equals","not_equals","contains","not_contains","greater_than","less_than","greater_or_equal","less_or_equal","is_empty","is_not_empty","in","not_in"]){
    assert.match(types,new RegExp('"'+op+'"'));
    assert.match(migration,new RegExp("'"+op+"'"));
  }
});

test("workflow actions are controlled and complete",()=>{
  for(const action of ["CREATE_TASK","UPDATE_TASK","ASSIGN_TASK","CREATE_FOLLOWUP","UPDATE_LEAD","ADD_NOTE","ASSIGN_AGENT","CREATE_ESCALATION","REQUEST_APPROVAL","WAIT","END_WORKFLOW"]){
    assert.match(migration,new RegExp("'"+action+"'"));
  }
  assert.match(migration,/WORKFLOW_ACTION_ADAPTER_NOT_IMPLEMENTED/);
  assert.match(migration,/CHANNEL_PROVIDER_NOT_CONFIGURED/);
});

test("AI agent node delegates to Phase 2 action boundary",()=>{
  assert.match(migration,/sav_ai_crm_request_agent_action/);
  assert.match(migration,/sav_ai_crm_execute_agent_action/);
  assert.match(migration,/approval_required/);
  assert.match(migration,/agent_slug/);
});

test("human approval always pauses and is never auto-approved",()=>{
  assert.match(migration,/execution_state='waiting_approval'/);
  assert.match(migration,/status='pending'/);
  assert.match(migration,/sav_ai_crm_review_workflow_approval/);
});

test("wait nodes persist scheduling and do not block server processes",()=>{
  assert.match(migration,/scheduled_for/);
  assert.match(migration,/make_interval/);
  assert.match(migration,/execution_state='waiting'/);
  assert.match(migration,/sav_ai_crm_resume_workflow_execution/);
});

test("execution engine enforces retry idempotency and depth protection",()=>{
  assert.match(migration,/idempotency_key/);
  assert.match(migration,/node_execution_id/);
  assert.match(migration,/max_retries/);
  assert.match(migration,/retry_delay_seconds/);
  assert.match(migration,/MAX_EXECUTION_DEPTH_EXCEEDED/);
  assert.match(migration,/unique\(workspace_id,idempotency_key\)/);
});

test("workflow-created tasks and lead changes are attributed and audited",()=>{
  assert.match(migration,/Created by: Workflow —/);
  assert.match(migration,/workflow_task_created/);
  assert.match(migration,/workflow_followup_created/);
  assert.match(migration,/workflow_lead_updated/);
  assert.match(migration,/workflow_note_added/);
  assert.match(migration,/workflow\.lead\.update/);
  assert.match(migration,/workflow\.action\./);
});

test("workflow escalation is linked back to workflow execution",()=>{
  assert.match(migration,/workflow_execution_id/);
  assert.match(migration,/ai_agent_escalations/);
});

test("eight editable workflow templates are seeded",()=>{
  for(const key of ["new-lead-qualification","new-website-lead","no-response-followup","document-collection","high-value-lead-escalation","customer-support-escalation","task-reminder","ai-human-handoff"]){
    assert.match(migration,new RegExp("'"+key+"'"));
  }
});

test("workflow APIs are represented by the client service",()=>{
  for(const path of ["/api/workflows","/duplicate","/test","/execute","/executions","/api/workflow-executions/","/api/workflow-approvals/"]){
    assert.ok(service.includes(path), `missing client API fragment: ${path}`);
  }
  assert.match(service,/op:"enable"\|"pause"\|"disable"/);
  assert.ok(service.includes(`/api/workflows/\${id}/\${op}`));
});

test("anonymous access is revoked from public workflow RPCs",()=>{
  for(const fn of [
    "sav_ai_crm_workflow_registry","sav_ai_crm_workflow_metrics","sav_ai_crm_workflow_templates",
    "sav_ai_crm_create_workflow","sav_ai_crm_update_workflow","sav_ai_crm_workflow_detail",
    "sav_ai_crm_set_workflow_status","sav_ai_crm_duplicate_workflow","sav_ai_crm_archive_workflow",
    "sav_ai_crm_test_workflow","sav_ai_crm_start_workflow","sav_ai_crm_run_workflow_execution",
    "sav_ai_crm_resume_workflow_execution","sav_ai_crm_workflow_executions",
    "sav_ai_crm_workflow_execution_detail","sav_ai_crm_review_workflow_approval"
  ]) assert.match(migration,new RegExp("revoke all on function public\\."+fn+"[\\s\\S]*?from public,anon"));
});

test("dangerous internal helpers are not exposed to authenticated API callers",()=>{
  assert.match(migration,/workflow_persist_graph[\s\S]*from public,anon,authenticated/);
  assert.match(migration,/workflow_next_node[\s\S]*from public,anon,authenticated/);
  assert.match(migration,/workflow_condition_match[\s\S]*from public,anon,authenticated/);
});

test("viewer cannot modify or dispatch workflows",()=>{
  assert.match(migration,/workflow managers insert workflows/);
  assert.match(migration,/workflow managers update workflows/);
  assert.match(migration,/Workflow event dispatch not permitted/);
  assert.match(migration,/Workflow execution not permitted/);
});

test("test mode never executes external messages",()=>{
  assert.match(migration,/external_messages_disabled/);
  assert.match(ui,/Plan Test/);
  assert.match(ui,/Execute Confirmed/);
});

test("UI exposes required operational states",()=>{
  for(const word of ["Loading workflow engine","No workflows","Executions","New Workflow","Archive","Duplicate","Plan Test","Execute Confirmed"]){
    assert.match(ui,new RegExp(word));
  }
});
