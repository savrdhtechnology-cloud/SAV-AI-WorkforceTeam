import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const migration=readFileSync(new URL("../supabase/migrations/20261002_zz_ai_agents_phase2.sql",import.meta.url),"utf8");
const types=readFileSync(new URL("../app/crm/agents/agent-types.ts",import.meta.url),"utf8");
const provider=readFileSync(new URL("../lib/ai/provider.ts",import.meta.url),"utf8");
const moduleUi=readFileSync(new URL("../app/crm/agents/AgentsModule.tsx",import.meta.url),"utf8");
const actionApi=readFileSync(new URL("../app/api/agent-actions/route.ts",import.meta.url),"utf8");

test("canonical eight agents are seeded",()=>{
  for(const slug of ["sav-sales","sav-bde","sav-sales-manager","sav-finance","sav-credit","sav-document","sav-followup","sav-support"]){
    assert.match(migration,new RegExp("'"+slug+"'"));
  }
});

test("registry persists required management fields",()=>{
  for(const field of [
    "display_name","avatar_icon","allowed_actions","knowledge_scopes","workflow_access",
    "task_permissions","escalation_rules","working_hours","daily_limits","confidence_threshold"
  ]) assert.match(migration,new RegExp(field));
});

test("agent lifecycle states include required operational states",()=>{
  for(const state of ["active","paused","disabled","error"]) assert.match(migration,new RegExp("'"+state+"'"));
});

test("risk classification is explicit and sensitive actions are critical/high",()=>{
  assert.match(types,/FINANCIAL_ACTION:"critical"/);
  assert.match(types,/CHANGE_PERMISSION:"critical"/);
  assert.match(types,/PERMANENT_DELETE_TASK:"critical"/);
  assert.match(types,/SEND_BULK_MESSAGE:"high"/);
  assert.match(types,/risk === "high" \|\| risk === "critical"/);
});

test("provider fails closed instead of faking output",()=>{
  assert.match(provider,/AI_PROVIDER_NOT_CONFIGURED/);
  assert.match(provider,/No AI provider credentials are configured/);
  assert.doesNotMatch(provider,/mock|fake response|dummy/i);
});

test("anonymous access is explicitly revoked from agent RPCs",()=>{
  for(const fn of [
    "sav_ai_crm_agent_registry","sav_ai_crm_agent_detail","sav_ai_crm_agent_metrics",
    "sav_ai_crm_create_agent","sav_ai_crm_update_agent","sav_ai_crm_set_agent_status",
    "sav_ai_crm_request_agent_action","sav_ai_crm_review_agent_action",
    "sav_ai_crm_execute_agent_action","sav_ai_crm_create_agent_execution"
  ]) assert.match(migration,new RegExp("revoke all on function public\\."+fn+"[\\s\\S]*from public,anon"));
});

test("agent identity never uses user-editable user_metadata",()=>{
  assert.doesNotMatch(migration,/user_metadata[^\n]*agent/i);
  assert.match(migration,/auth\.uid\(\)/);
});

test("capability authorization and approval boundaries are server side",()=>{
  assert.match(migration,/Agent capability denied/);
  assert.match(migration,/cap\.risk_level in \('high','critical'\)/);
  assert.match(migration,/Human approval required/);
  assert.match(migration,/Approval review not permitted/);
});

test("sensitive actions have no automatic execution adapter",()=>{
  assert.match(migration,/ACTION_ADAPTER_NOT_IMPLEMENTED/);
  assert.doesNotMatch(migration,/elsif a\.action='FINANCIAL_ACTION'/);
  assert.doesNotMatch(migration,/elsif a\.action='CHANGE_PERMISSION'/);
  assert.doesNotMatch(migration,/elsif a\.action='PERMANENT_DELETE_TASK'/);
});

test("AI-created tasks are attributed to the agent and use task permission boundary",()=>{
  assert.match(migration,/Created by: '\|\|agent\.display_name/);
  assert.match(migration,/assigned_agent_id/);
  assert.match(migration,/agent_task_created/);
  assert.match(migration,/agent_followup_created/);
});

test("lead modification and escalation actions are audited",()=>{
  assert.match(migration,/agent_note_created/);
  assert.match(migration,/ai_agent_escalations/);
  assert.match(migration,/agent\.action\.completed/);
  assert.match(migration,/agent\.action\.request/);
});

test("agent UI has required detail states and real test console",()=>{
  for(const label of ["Overview","Role & Instructions","Capabilities","Tasks","Channels","Knowledge","Workflows","Working Hours","Limits","Escalation","Activity","Audit"]){
    assert.match(moduleUi,new RegExp(label.replace(/[&]/g,"&")));
  }
  assert.match(moduleUi,/Agent Test Console/);
  assert.match(moduleUi,/AI_PROVIDER_NOT_CONFIGURED/);
  assert.match(moduleUi,/Loading AI agents/);
});

test("action API executes only after server request boundary",()=>{
  assert.match(actionApi,/sav_ai_crm_request_agent_action/);
  assert.match(actionApi,/approval_required/);
  assert.match(actionApi,/sav_ai_crm_execute_agent_action/);
});
