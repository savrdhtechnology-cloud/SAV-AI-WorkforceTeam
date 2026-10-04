import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";

const root=process.cwd();
const read=(p)=>fs.readFileSync(path.join(root,p),"utf8");

const engine=read("lib/ai/agent-engine.ts");
const toolbox=read("lib/ai/crm-agent-tools.ts");
const provider=read("lib/ai/provider.ts");
const route=read("app/api/agents/[id]/execute/route.ts");
const ui=read("app/crm/agents/AgentsModule.tsx");
const migration=read("supabase/migrations/20261004_sav_sales_agent_engine_phase1.sql");

test("SAV-Sales analyze and execute modes are separate",()=>{
  assert.match(engine,/analyzeSalesLead/);
  assert.match(engine,/executeSalesDecision/);
  assert.match(route,/mode==="execute"/);
  assert.match(ui,/Analyze & Plan/);
  assert.match(ui,/Execute Approved Actions/);
  assert.match(engine,/analyze_writes:false/);
});

test("SAV-Sales only exposes controlled CRM tools",()=>{
  for(const tool of ["getLead","updateLeadStatus","createTask","createFollowup","requestApproval"]){
    assert.match(toolbox,new RegExp(tool));
  }
  assert.doesNotMatch(toolbox,/from\(["'`]audit_logs["'`]\)|\.sql\(|execute_sql/i);
  assert.match(engine,/permitted_execute_tools|available_tools/);
  assert.match(engine,/no_arbitrary_sql:true/);
});

test("autonomous lead updates cannot mark won or modify financial state",()=>{
  assert.match(toolbox,/SAFE_LEAD_STATUSES/);
  assert.doesNotMatch(toolbox,/SAFE_LEAD_STATUSES[^\n]*won/i);
  assert.match(migration,/not in \('new','contacted','qualified','proposal','negotiation','nurture'\)/);
  assert.doesNotMatch(migration,/next_status[^\n]*won/i);
  assert.match(engine,/never_mark_won:true/);
  assert.match(engine,/no_financial_actions:true/);
  assert.match(engine,/no_external_communication:true/);
});

test("writes go through capability and action RPC boundaries",()=>{
  assert.match(toolbox,/sav_ai_crm_agent_detail/);
  assert.match(toolbox,/sav_ai_crm_request_agent_action/);
  assert.match(toolbox,/sav_ai_crm_execute_agent_action/);
  assert.match(toolbox,/sav_ai_crm_log_agent_tool/);
  assert.match(migration,/agent\.tool\.succeeded/);
  assert.match(migration,/agent\.tool\.failed/);
});

test("provider remains environment-driven and returns safe diagnostics",()=>{
  assert.match(provider,/process\.env\.AI_PROVIDER/);
  assert.match(provider,/process\.env\.AI_API_KEY/);
  assert.match(provider,/process\.env\.AI_MODEL/);
  assert.doesNotMatch(provider,/NEXT_PUBLIC_.*AI_API_KEY/);
  assert.match(provider,/http_status/);
  assert.match(provider,/request_id/);
  assert.match(provider,/\[REDACTED\]/);
  assert.match(provider,/responses\.create/);
});

test("product recommendation fails closed when no catalog knowledge is provided",()=>{
  assert.match(provider,/recommended_product/);
  assert.match(provider,/set recommended_product to null/);
  assert.match(engine,/sav_ai_crm_active_products/);
  assert.match(engine,/active_products:products/);
  assert.match(engine,/decision\.recommended_product=null/);
});

test("execute mode reuses analyzed decision instead of calling provider again",()=>{
  const executeStart=engine.indexOf("export async function executeSalesDecision");
  assert.ok(executeStart>=0);
  const executeBlock=engine.slice(executeStart);
  assert.doesNotMatch(executeBlock,/getAIProvider\(\)/);
  assert.match(executeBlock,/validateSalesDecision/);
});


test("EngageX sales workflow is repository-backed and fail-closed",()=>{
  const migration=read("supabase/migrations/20261004_engagex_sales_workflow_phase2.sql");
  const webhook=read("app/api/integrations/engagex/webhook/route.ts");
  const draft=read("app/api/sales/email-drafts/route.ts");
  const approve=read("app/api/sales/email-drafts/[id]/approve-send/route.ts");
  assert.match(migration,/engagex_record_id/);
  assert.match(migration,/sav_ai_crm_ingest_engagex_lead/);
  assert.match(migration,/Duplicate email prevented/);
  assert.match(webhook,/ENGAGEX_WEBHOOK_SECRET/);
  assert.match(webhook,/x-engagex-sync-token/);
  assert.match(draft,/EMAIL_CONSENT_MISSING/);
  assert.match(draft,/PRODUCT_FIT_MISSING/);
  assert.match(approve,/EngageX email-send capability is not configured/);
});
