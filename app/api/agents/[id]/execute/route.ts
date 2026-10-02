import { NextRequest } from "next/server";
import { getAIProvider } from "../../../../../lib/ai/provider";
import { bearerPresent,jsonError,serverSupabase } from "../../../../../lib/ai/server-supabase";

export async function POST(req:NextRequest,{params}:{params:Promise<{id:string}>}){
 if(!bearerPresent(req)) return jsonError("Authentication required",401,"UNAUTHORIZED");
 const {id}=await params;
 const body=await req.json().catch(()=>null) as null|{command?:string;context?:Record<string,unknown>};
 if(!body?.command?.trim()) return jsonError("command is required",422,"VALIDATION_ERROR");
 const supabase=serverSupabase(req);
 const {data:executionId,error:createError}=await supabase.rpc("sav_ai_crm_create_agent_execution",{
   p_agent_id:id,p_command:body.command.trim(),p_input:body.context||{}
 });
 if(createError) return jsonError(createError.message,403,"EXECUTION_CREATE_FAILED");

 const result=await getAIProvider().planAction({command:body.command.trim(),context:body.context||{}});
 if(!result.ok){
   await supabase.rpc("sav_ai_crm_fail_agent_execution",{
     p_execution_id:executionId,p_error:result.error,p_output:{message:result.message}
   });
   return Response.json({execution_id:executionId,error:result.error,message:result.message},{status:503});
 }
 return Response.json({execution_id:executionId,plan:result.data});
}
