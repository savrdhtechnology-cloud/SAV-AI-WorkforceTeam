import { NextRequest } from "next/server";
import { getAIProvider } from "../../../../../lib/ai/provider";
import { bearerPresent,jsonError,serverSupabase } from "../../../../../lib/ai/server-supabase";

function isDatabaseNotReady(error:{code?:string|null;message?:string|null}|null|undefined){
 const message=error?.message||"";
 return error?.code==="PGRST202"
   || /Could not find the function .* in the schema cache/i.test(message)
   || /function .* does not exist/i.test(message)
   || /relation .* does not exist/i.test(message)
   || /column .* does not exist/i.test(message);
}

function databaseNotReady(message:string){
 return jsonError(message,503,"DATABASE_NOT_READY");
}

export async function POST(req:NextRequest,{params}:{params:Promise<{id:string}>}){
 if(!bearerPresent(req)) return jsonError("Authentication required",401,"UNAUTHORIZED");
 const {id}=await params;
 const body=await req.json().catch(()=>null) as null|{command?:string;context?:Record<string,unknown>};
 if(!body?.command?.trim()) return jsonError("command is required",422,"VALIDATION_ERROR");
 const supabase=serverSupabase(req);

 const {data:executionId,error:createError}=await supabase.rpc("sav_ai_crm_create_agent_execution",{
   p_agent_id:id,p_command:body.command.trim(),p_input:body.context||{}
 });
 if(createError){
   if(isDatabaseNotReady(createError)) return databaseNotReady(createError.message);
   return jsonError(createError.message,403,"EXECUTION_CREATE_FAILED");
 }

 const result=await getAIProvider().planAction({command:body.command.trim(),context:body.context||{}});
 if(!result.ok){
   const {error:failError}=await supabase.rpc("sav_ai_crm_fail_agent_execution",{
     p_execution_id:executionId,p_error:result.error,p_output:{message:result.message}
   });
   if(failError&&isDatabaseNotReady(failError)) return databaseNotReady(failError.message);
   if(failError) return jsonError(failError.message,500,"EXECUTION_STATE_PERSIST_FAILED");
   return Response.json({execution_id:executionId,error:result.error,message:result.message},{status:503});
 }

 const {error:completeError}=await supabase.rpc("sav_ai_crm_complete_agent_execution",{
   p_execution_id:executionId,p_planned_action:result.data,p_output:{plan:result.data},p_approval_status:"not_required"
 });
 if(completeError){
   if(isDatabaseNotReady(completeError)) return databaseNotReady(completeError.message);
   return jsonError(completeError.message,500,"EXECUTION_COMPLETE_FAILED");
 }
 return Response.json({execution_id:executionId,plan:result.data,status:"completed"});
}
