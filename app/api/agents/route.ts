import { NextRequest } from "next/server";
import { bearerPresent, jsonError, serverSupabase } from "../../../lib/ai/server-supabase";

export async function GET(req:NextRequest){
  if(!bearerPresent(req)) return jsonError("Authentication required",401,"UNAUTHORIZED");
  const supabase=serverSupabase(req);
  const [{data:agents,error},{data:metrics,error:metricError}] = await Promise.all([
    supabase.rpc("sav_ai_crm_agent_registry"),
    supabase.rpc("sav_ai_crm_agent_metrics")
  ]);
  if(error) return jsonError(error.message,403,"AGENT_REGISTRY_FAILED");
  if(metricError) return jsonError(metricError.message,403,"AGENT_METRICS_FAILED");
  return Response.json({agents:agents||[],metrics:metrics||{}});
}

export async function POST(req:NextRequest){
  if(!bearerPresent(req)) return jsonError("Authentication required",401,"UNAUTHORIZED");
  const body=await req.json().catch(()=>null) as null|{name?:string;slug?:string;role_name?:string;description?:string};
  if(!body?.name || !body.slug || !body.role_name) return jsonError("name, slug and role_name are required",422,"VALIDATION_ERROR");
  const supabase=serverSupabase(req);
  const {data,error}=await supabase.rpc("sav_ai_crm_create_agent",{
    p_name:body.name,p_slug:body.slug,p_role_name:body.role_name,p_description:body.description||null
  });
  if(error) return jsonError(error.message,403,"AGENT_CREATE_FAILED");
  return Response.json({id:data},{status:201});
}
