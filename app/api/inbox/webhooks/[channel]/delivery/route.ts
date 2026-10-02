import { NextRequest } from "next/server";
import { jsonError,serverAdminSupabase } from "../../../../../../../lib/ai/server-supabase";
import { resolveChannelAdapter } from "../../../../../../../lib/channels/server-registry";

export async function POST(req:NextRequest,{params}:{params:Promise<{channel:string}>}){
  const {channel}=await params;
  let adapter;
  try{adapter=resolveChannelAdapter(channel);}catch{return jsonError("Unsupported channel",404,"WEBHOOK_UNSUPPORTED");}

  const raw=await req.text();
  let body:unknown=raw;
  try{body=JSON.parse(raw);}catch{}
  const headers:Record<string,string>={};
  req.headers.forEach((v,k)=>{headers[k]=v;});
  const envelope={headers,body,query:Object.fromEntries(req.nextUrl.searchParams.entries())};

  const verified=await adapter.verifyWebhook(envelope);
  if(!verified.ok){
    const status=verified.error==="WEBHOOK_SIGNATURE_INVALID"?401:503;
    return jsonError(verified.message,status,verified.error);
  }

  if(!body||typeof body!=="object"||Array.isArray(body))return jsonError("Delivery webhook payload is invalid",422,"VALIDATION_ERROR");
  const payload=body as Record<string,unknown>;
  const providerMessageId=typeof payload.providerMessageId==="string"?payload.providerMessageId:"";
  const providerEventId=typeof payload.providerEventId==="string"?payload.providerEventId:"";
  if(!providerMessageId||!providerEventId)return jsonError("providerMessageId and providerEventId are required after provider verification",422,"WEBHOOK_DELIVERY_ID_REQUIRED");

  const delivery=await adapter.getDeliveryStatus(providerMessageId);
  if(!delivery.ok)return jsonError(delivery.message,503,delivery.error);

  const admin=serverAdminSupabase();
  if(!admin)return jsonError("Server webhook persistence is not configured",503,"WEBHOOK_SERVER_NOT_CONFIGURED");

  const {data:account,error:accountError}=await admin.rpc("sav_ai_crm_resolve_channel_account",{
    p_channel:channel,
    p_provider:delivery.provider,
    p_external_account_id:verified.channelAccountExternalId||null,
    p_webhook_external_key:verified.workspaceExternalKey||null
  });
  if(accountError)return jsonError(accountError.message,403,"CHANNEL_ACCOUNT_RESOLUTION_FAILED");

  const {data:applied,error:applyError}=await admin.rpc("sav_ai_crm_apply_delivery_event",{
    p_workspace_id:account.workspace_id,
    p_provider:delivery.provider,
    p_provider_event_id:providerEventId,
    p_provider_message_id:delivery.providerMessageId,
    p_status:delivery.status,
    p_error_code:null,
    p_error_message:null,
    p_metadata:delivery.raw||{}
  });
  if(applyError)return jsonError(applyError.message,500,"DELIVERY_PERSIST_FAILED");

  const event=delivery.status==="FAILED"?"MESSAGE_FAILED":delivery.status==="DELIVERED"||delivery.status==="READ"?"MESSAGE_DELIVERED":null;
  if(event&&!applied?.duplicate){
    await admin.schema("sav_ai_crm").rpc("dispatch_workflow_event_system",{
      p_workspace_id:account.workspace_id,
      p_event:event,
      p_context:{conversation:{id:applied.conversation_id},message:{id:applied.message_id,provider_message_id:delivery.providerMessageId,status:delivery.status},channel},
      p_event_key:`delivery:${providerEventId}:${event}`
    });
  }
  return Response.json({ok:true,duplicate:Boolean(applied?.duplicate),message_id:applied?.message_id,status:delivery.status});
}
