import { NextRequest } from "next/server";
import { serverAdminSupabase,jsonError } from "../../../../../lib/ai/server-supabase";
import { resolveChannelAdapter } from "../../../../../lib/channels/server-registry";

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
  const normalized=await adapter.normalizeInboundMessage(envelope);
  if("ok" in normalized && normalized.ok===false)return jsonError(normalized.message,422,normalized.error);

  const admin=serverAdminSupabase();
  if(!admin)return jsonError("Server webhook persistence is not configured",503,"WEBHOOK_SERVER_NOT_CONFIGURED");

  const {data:account,error:accountError}=await admin.rpc("sav_ai_crm_resolve_channel_account",{
    p_channel:normalized.channel,
    p_provider:normalized.provider,
    p_external_account_id:normalized.channelAccountExternalId||null,
    p_webhook_external_key:normalized.workspaceExternalKey||null
  });
  if(accountError)return jsonError(accountError.message,403,"CHANNEL_ACCOUNT_RESOLUTION_FAILED");

  const {data:persisted,error:persistError}=await admin.rpc("sav_ai_crm_persist_inbound_message",{
    p_workspace_id:account.workspace_id,
    p_channel_account_id:account.id,
    p_provider:normalized.provider,
    p_provider_event_id:normalized.providerEventId,
    p_provider_message_id:normalized.providerMessageId,
    p_channel:normalized.channel,
    p_sender:normalized.sender.address,
    p_recipient:normalized.recipient.address,
    p_body:normalized.body||"",
    p_message_type:normalized.messageType,
    p_external_thread_id:normalized.externalThreadId||null,
    p_received_at:normalized.receivedAt,
    p_attachments:normalized.attachments||[],
    p_metadata:normalized.metadata||{}
  });
  if(persistError)return jsonError(persistError.message,500,"INBOUND_PERSIST_FAILED");
  if(persisted?.duplicate)return Response.json({ok:true,duplicate:true});

  const workflow=admin.schema("sav_ai_crm");
  if(persisted?.conversation_created){
    await workflow.rpc("dispatch_workflow_event_system",{
      p_workspace_id:account.workspace_id,
      p_event:"CONVERSATION_CREATED",
      p_context:{conversation:{id:persisted.conversation_id,channel:normalized.channel,lead_id:persisted.lead_id||null,contact_id:persisted.contact_id||null}},
      p_event_key:`webhook:${normalized.providerEventId}:conversation`
    });
  }
  await workflow.rpc("dispatch_workflow_event_system",{
    p_workspace_id:account.workspace_id,
    p_event:"MESSAGE_RECEIVED",
    p_context:{conversation:{id:persisted.conversation_id,channel:normalized.channel},message:{id:persisted.message_id,provider_message_id:normalized.providerMessageId,direction:"inbound"}},
    p_event_key:`webhook:${normalized.providerEventId}:message`
  });
  return Response.json({ok:true,conversation_id:persisted.conversation_id,message_id:persisted.message_id});
}
