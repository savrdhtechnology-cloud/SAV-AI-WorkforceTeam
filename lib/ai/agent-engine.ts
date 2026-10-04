import type { SupabaseClient } from "@supabase/supabase-js";
import { getAIProvider } from "./provider";
import { CRMToolbox, type AgentToolResult } from "./crm-agent-tools";

export type AgentMode="analyze"|"execute";

export type SalesDecision={
  lead_id:string;
  qualification:"hot"|"warm"|"cold"|"unqualified";
  summary:string;
  recommended_product:string|null;
  next_action:string;
  follow_up_required:boolean;
  proposed_actions:Array<{tool:string;payload:Record<string,unknown>}>;
  confidence:number;
};

export type AgentEngineResult={
  decision:SalesDecision;
  actions_taken:AgentToolResult[];
  approval_required:boolean;
  errors:string[];
};

function object(value:unknown):Record<string,unknown>{
  return value&&typeof value==="object"&&!Array.isArray(value)?value as Record<string,unknown>:{};
}
function stringValue(value:unknown,max=1000){
  return typeof value==="string"?value.trim().slice(0,max):"";
}
function booleanValue(value:unknown){
  return value===true;
}

function normalizeDecision(leadId:string,plan:{payload:Record<string,unknown>;confidence:number}):SalesDecision{
  const payload=object(plan.payload);
  const rawQualification=stringValue(payload.qualification||payload.qualification_status,32).toLowerCase();
  const qualification=(["hot","warm","cold","unqualified"].includes(rawQualification)?rawQualification:"cold") as SalesDecision["qualification"];
  const actions=Array.isArray(payload.proposed_actions)?payload.proposed_actions:[];
  const proposed_actions=actions.slice(0,5).map((raw)=>{
    const item=object(raw);
    return {tool:stringValue(item.tool,64),payload:object(item.payload)};
  }).filter((item)=>item.tool);
  const recommended=stringValue(payload.recommended_product,160);
  return {
    lead_id:leadId,
    qualification,
    summary:stringValue(payload.summary||payload.lead_requirement,1500),
    recommended_product:recommended||null,
    next_action:stringValue(payload.next_action||payload.next_best_action,500),
    follow_up_required:booleanValue(payload.follow_up_required)||Boolean(stringValue(payload.recommended_follow_up,500)),
    proposed_actions,
    confidence:Math.max(0,Math.min(1,Number(plan.confidence)||0))
  };
}

export async function runSalesAgentEngine(input:{
  supabase:SupabaseClient;
  agentId:string;
  leadId:string;
  command:string;
  mode:AgentMode;
}){
  const tools=new CRMToolbox(input.supabase,input.agentId);
  const leadResult=await tools.getLead(input.leadId);
  if(!leadResult.ok) return {ok:false,error:"LEAD_READ_FAILED",message:leadResult.error||"Lead could not be read"} as const;

  const provider=await getAIProvider().planAction({
    command:input.command,
    context:{
      lead:leadResult.data,
      mode:input.mode,
      constraints:{
        analyze_writes:false,
        no_external_communication:true,
        no_financial_actions:true,
        never_mark_won:true,
        permitted_execute_tools:["updateLeadStatus","createTask","createFollowup","requestApproval"]
      }
    }
  });
  if(!provider.ok) return provider;

  const decision=normalizeDecision(input.leadId,provider.data);
  const result:AgentEngineResult={decision,actions_taken:[],approval_required:false,errors:[]};

  if(input.mode==="analyze") return {ok:true,data:result,provider:provider.provider} as const;

  for(const proposed of decision.proposed_actions){
    let toolResult:AgentToolResult;
    if(proposed.tool==="updateLeadStatus"){
      toolResult=await tools.updateLeadStatus(input.leadId,proposed.payload.status);
    }else if(proposed.tool==="createTask"){
      toolResult=await tools.createTask(input.leadId,proposed.payload);
    }else if(proposed.tool==="createFollowup"){
      toolResult=await tools.createFollowup(input.leadId,proposed.payload);
    }else if(proposed.tool==="requestApproval"){
      toolResult=await tools.requestApproval(stringValue(proposed.payload.capability,64),input.leadId,proposed.payload);
    }else{
      toolResult={tool:"requestApproval",ok:false,error:`Unsupported agent tool: ${proposed.tool}`};
    }
    result.actions_taken.push(toolResult);
    if(toolResult.approval_required) result.approval_required=true;
    if(!toolResult.ok&&toolResult.error) result.errors.push(toolResult.error);
  }

  return {ok:true,data:result,provider:provider.provider} as const;
}
