import { NextRequest } from "next/server";
import { bearerPresent,jsonError,serverSupabase } from "@/lib/ai/server-supabase";
export async function GET(req:NextRequest,{params}:{params:Promise<{id:string}>}){
 if(!bearerPresent(req)) return jsonError("Authentication required",401,"UNAUTHORIZED");
 const {id}=await params; const {data,error}=await serverSupabase(req).rpc("sav_ai_crm_agent_executions",{p_agent_id:id});
 if(error) return jsonError(error.message,403,"EXECUTIONS_FAILED"); return Response.json({executions:data||[]});
}
