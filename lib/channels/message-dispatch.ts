import "server-only";
import { NextRequest } from "next/server";
import { serverSupabase } from "../ai/server-supabase";
import { resolveChannelAdapter } from "./server-registry";

export async function dispatchQueuedMessage(req:NextRequest,messageId:string){
  const supabase=serverSupabase(req);
  const {data:prepared,error:prepareError}=await supabase.rpc("sav_ai_crm_mark_message_sending",{p_message_id:messageId});
  if(prepareError) return {ok:false,status:409,error:"MESSAGE_NOT_SENDABLE",message:prepareError.message};

  const adapter=resolveChannelAdapter(String(prepared.channel));
  const result=await adapter.sendMessage({
    channel:prepared.channel,
    workspaceId:"",
    conversationId:prepared.conversation_id,
    messageId:prepared.message_id,
    from:prepared.sender?{address:prepared.sender}:null,
    to:{address:prepared.recipient||""},
    messageType:prepared.message_type,
    body:prepared.body,
    metadata:prepared.metadata||{}
  });

  const provider=result.ok?result.provider:adapter.provider;
  const {error:recordError}=await supabase.rpc("sav_ai_crm_record_message_result",{
    p_message_id:messageId,
    p_ok:result.ok,
    p_provider:provider,
    p_provider_message_id:result.ok?result.providerMessageId:null,
    p_status:result.ok?result.status:null,
    p_error_code:result.ok?null:result.error,
    p_error_message:result.ok?null:result.message,
    p_raw:result.raw||{}
  });
  if(recordError) return {ok:false,status:500,error:"MESSAGE_RESULT_PERSIST_FAILED",message:recordError.message};

  const event=result.ok && result.status==="DELIVERED"?"MESSAGE_DELIVERED":!result.ok?"MESSAGE_FAILED":null;
  if(event){
    await supabase.rpc("sav_ai_crm_dispatch_workflow_event",{
      p_event:event,
      p_context:{conversation:{id:prepared.conversation_id},message:{id:messageId,status:result.ok?result.status:"FAILED"},channel:prepared.channel},
      p_event_key:`message:${messageId}:${event}`
    });
  }

  if(!result.ok) return {ok:false,status:503,error:result.error,message:result.message,message_id:messageId};
  return {ok:true,status:200,message_id:messageId,provider_message_id:result.providerMessageId,delivery_status:result.status,provider:result.provider};
}
