import { NextRequest } from "next/server";
import { bearerPresent,jsonError,serverSupabase } from "../../../../../../lib/ai/server-supabase";

export async function POST(req:NextRequest,{params}:{params:Promise<{id:string}>}){
  if(!bearerPresent(req)) return jsonError("Authentication required",401,"UNAUTHORIZED");
  const {id}=await params;
  const db=serverSupabase(req);
  const {data,error}=await db.rpc("sav_ai_crm_approve_sales_email_draft",{p_draft_id:id});
  if(error) return jsonError(error.message,403,"EMAIL_APPROVAL_FAILED");
  return Response.json({
    approval:data,
    send:{ok:false,error:"ENGAGEX_EMAIL_NOT_CONFIGURED",message:"EngageX email-send capability is not configured."}
  },{status:409});
}
