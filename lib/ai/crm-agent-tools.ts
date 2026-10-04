import type { SupabaseClient } from "@supabase/supabase-js";

export type AgentToolName="getLead"|"updateLeadStatus"|"createTask"|"createFollowup"|"requestApproval";

export type AgentToolResult={
  tool:AgentToolName;
  ok:boolean;
  action_id?:string;
  task_id?:string|null;
  approval_required?:boolean;
  data?:unknown;
  error?:string;
};

const SAFE_LEAD_STATUSES=new Set(["new","contacted","qualified","proposal","negotiation","nurture"]);

function asObject(value:unknown):Record<string,unknown>{
  return value&&typeof value==="object"&&!Array.isArray(value)?value as Record<string,unknown>:{};
}
function nonEmptyString(value:unknown,max=500){
  if(typeof value!=="string") return null;
  const trimmed=value.trim();
  if(!trimmed) return null;
  return trimmed.slice(0,max);
}
function optionalIso(value:unknown){
  const text=nonEmptyString(value,64);
  if(!text) return null;
  const date=new Date(text);
  if(Number.isNaN(date.getTime())) throw new Error("Invalid date/time");
  return date.toISOString();
}

export class CRMToolbox{
  constructor(
    private readonly supabase:SupabaseClient,
    private readonly agentId:string
  ){}

  private async workspaceRole(){
    const {data,error}=await this.supabase.rpc("sav_ai_crm_workspace");
    if(error) throw new Error(error.message);
    const role=asObject(data).role;
    return typeof role==="string"?role:"";
  }

  private async ensureWriteRole(){
    const role=await this.workspaceRole();
    if(!role||role==="viewer") throw new Error("CRM write permission required");
  }

  private async ensureCapability(capability:string){
    const {data,error}=await this.supabase.rpc("sav_ai_crm_agent_detail",{p_agent_id:this.agentId});
    if(error) throw new Error(error.message);
    const detail=asObject(data);
    const rows=Array.isArray(detail.capabilities)?detail.capabilities:[];
    const enabled=rows.some((row)=>{
      const item=asObject(row);
      return item.capability===capability&&item.is_enabled!==false;
    });
    if(!enabled) throw new Error(`Agent capability denied: ${capability}`);
  }

  async getLead(leadId:string):Promise<AgentToolResult>{
    if(!/^[0-9a-f-]{36}$/i.test(leadId)) return {tool:"getLead",ok:false,error:"Invalid lead ID"};
    const {data,error}=await this.supabase.rpc("sav_ai_crm_list_leads",{p_status:null,p_search:null});
    if(error) return {tool:"getLead",ok:false,error:error.message};
    const rows=Array.isArray(data)?data:[];
    const lead=rows.find((row)=>asObject(row).id===leadId);
    if(!lead) return {tool:"getLead",ok:false,error:"Lead not found in workspace"};
    return {tool:"getLead",ok:true,data:lead};
  }

  async updateLeadStatus(leadId:string,status:unknown):Promise<AgentToolResult>{
    try{
      await this.ensureWriteRole();
      await this.ensureCapability("UPDATE_LEAD");
      const next=nonEmptyString(status,32);
      if(!next||!SAFE_LEAD_STATUSES.has(next)) {
        return {tool:"updateLeadStatus",ok:false,error:"Lead status is not permitted for autonomous agent update"};
      }
      const {data,error}=await this.supabase.rpc("sav_ai_crm_update_lead_status",{p_lead_id:leadId,p_status:next});
      if(error) return {tool:"updateLeadStatus",ok:false,error:error.message};
      return {tool:"updateLeadStatus",ok:Boolean(data),data:{status:next}};
    }catch(error){
      return {tool:"updateLeadStatus",ok:false,error:error instanceof Error?error.message:"Lead update failed"};
    }
  }

  private async requestAndExecute(
    tool:"createTask"|"createFollowup",
    capability:"CREATE_TASK"|"CREATE_FOLLOWUP",
    leadId:string,
    rawPayload:unknown
  ):Promise<AgentToolResult>{
    try{
      await this.ensureWriteRole();
      await this.ensureCapability(capability);
      const payload=asObject(rawPayload);
      const title=nonEmptyString(payload.title,160);
      if(!title) return {tool,ok:false,error:"Task title is required"};
      const priority=nonEmptyString(payload.priority,20)||"medium";
      if(!["low","medium","high","urgent"].includes(priority)) return {tool,ok:false,error:"Invalid task priority"};
      const dueAt=optionalIso(payload.due_at);
      const reminderAt=optionalIso(payload.reminder_at);
      const actionPayload={
        title,
        description:nonEmptyString(payload.description,1000),
        priority,
        due_at:dueAt,
        reminder_at:reminderAt,
        followup_type:tool==="createFollowup"?(nonEmptyString(payload.followup_type,40)||"general"):"general"
      };

      const {data,error}=await this.supabase.rpc("sav_ai_crm_request_agent_action",{
        p_agent_id:this.agentId,
        p_action:capability,
        p_target_type:"lead",
        p_target_id:leadId,
        p_payload:actionPayload
      });
      if(error) return {tool,ok:false,error:error.message};
      const requested=asObject(data);
      const actionId=typeof requested.action_id==="string"?requested.action_id:undefined;
      const approvalRequired=requested.approval_required===true;
      if(!actionId) return {tool,ok:false,error:"Agent action request did not return an action ID"};
      if(approvalRequired){
        return {tool,ok:true,action_id:actionId,approval_required:true,data:requested};
      }
      const executed=await this.supabase.rpc("sav_ai_crm_execute_agent_action",{p_action_id:actionId});
      if(executed.error) return {tool,ok:false,action_id:actionId,error:executed.error.message};
      const result=asObject(executed.data);
      return {
        tool,ok:true,action_id:actionId,task_id:typeof result.task_id==="string"?result.task_id:null,
        approval_required:false,data:result
      };
    }catch(error){
      return {tool,ok:false,error:error instanceof Error?error.message:"Agent task action failed"};
    }
  }

  createTask(leadId:string,payload:unknown){
    return this.requestAndExecute("createTask","CREATE_TASK",leadId,payload);
  }

  createFollowup(leadId:string,payload:unknown){
    return this.requestAndExecute("createFollowup","CREATE_FOLLOWUP",leadId,payload);
  }

  async requestApproval(action:string,leadId:string,payload:unknown):Promise<AgentToolResult>{
    try{
      await this.ensureWriteRole();
      const capability=nonEmptyString(action,64);
      if(!capability) return {tool:"requestApproval",ok:false,error:"Capability is required"};
      const {data,error}=await this.supabase.rpc("sav_ai_crm_request_agent_action",{
        p_agent_id:this.agentId,
        p_action:capability,
        p_target_type:"lead",
        p_target_id:leadId,
        p_payload:asObject(payload)
      });
      if(error) return {tool:"requestApproval",ok:false,error:error.message};
      const result=asObject(data);
      return {
        tool:"requestApproval",ok:true,
        action_id:typeof result.action_id==="string"?result.action_id:undefined,
        approval_required:result.approval_required===true,
        data:result
      };
    }catch(error){
      return {tool:"requestApproval",ok:false,error:error instanceof Error?error.message:"Approval request failed"};
    }
  }
}
