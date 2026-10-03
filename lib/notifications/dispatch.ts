import "server-only";
import { NextRequest } from "next/server";
import { serverSupabase } from "../ai/server-supabase";
import { resolveChannelAdapter } from "../channels/server-registry";
import { getPushAdapter } from "./push-adapter";
import { getNotificationWebhookAdapter } from "./webhook-adapter";

type DispatchResult={ok:true;status:number;notification_id:string;delivery_status:string;provider:string;provider_message_id?:string|null}|{ok:false;status:number;notification_id:string;error:string;message:string};

export async function dispatchNotification(req:NextRequest,notificationId:string):Promise<DispatchResult>{
 const s=serverSupabase(req);
 const {data:p,error:prepareError}=await s.rpc("sav_ai_crm_notification_prepare_send",{p_notification_id:notificationId});
 if(prepareError)return {ok:false,status:409,notification_id:notificationId,error:"NOTIFICATION_NOT_SENDABLE",message:prepareError.message};
 if(p.channel==="in_app"){
   const {error}=await s.rpc("sav_ai_crm_notification_record_result",{p_notification_id:notificationId,p_ok:true,p_provider:"internal",p_provider_message_id:null,p_status:"DELIVERED",p_error_code:null,p_error_message:null,p_raw:{in_app:true},p_retryable:false});
   if(error)return {ok:false,status:500,notification_id:notificationId,error:"NOTIFICATION_RESULT_PERSIST_FAILED",message:error.message};
   return {ok:true,status:200,notification_id:notificationId,delivery_status:"DELIVERED",provider:"internal",provider_message_id:null};
 }
 if(["email","whatsapp","sms"].includes(p.channel)){
   let adapter; try{adapter=resolveChannelAdapter(p.channel);}catch{await recordFailure(s,notificationId,"unconfigured","CHANNEL_PROVIDER_NOT_CONFIGURED",p.channel+" provider is not configured.",false,{});return {ok:false,status:503,notification_id:notificationId,error:"CHANNEL_PROVIDER_NOT_CONFIGURED",message:p.channel+" provider is not configured."};}
   if(!p.recipient_address){await recordFailure(s,notificationId,adapter.provider,"NOTIFICATION_RECIPIENT_REQUIRED","No server-authorized recipient address is available.",false,{});return {ok:false,status:422,notification_id:notificationId,error:"NOTIFICATION_RECIPIENT_REQUIRED",message:"No server-authorized recipient address is available."};}
   const result=await adapter.sendMessage({channel:p.channel,workspaceId:p.workspace_id,conversationId:p.conversation_id||notificationId,messageId:notificationId,from:null,to:{address:p.recipient_address},messageType:"text",body:p.body,metadata:{...p.metadata,notification_id:notificationId,title:p.title}});
   if(!result.ok){await recordFailure(s,notificationId,adapter.provider,result.error,result.message,Boolean(result.retryable),result.raw||{});return {ok:false,status:503,notification_id:notificationId,error:result.error,message:result.message};}
   await s.rpc("sav_ai_crm_notification_record_result",{p_notification_id:notificationId,p_ok:true,p_provider:result.provider,p_provider_message_id:result.providerMessageId,p_status:result.status,p_error_code:null,p_error_message:null,p_raw:result.raw||{},p_retryable:false});
   return {ok:true,status:200,notification_id:notificationId,delivery_status:result.status,provider:result.provider,provider_message_id:result.providerMessageId};
 }
 if(p.channel==="push"){
   const adapter=getPushAdapter();const result=await adapter.sendPush({workspaceId:p.workspace_id,notificationId,title:p.title,body:p.body,deviceToken:"",deepLink:p.deep_link||null});
   if(!result.ok){await recordFailure(s,notificationId,"push",result.error,result.message,Boolean(result.retryable),{});return {ok:false,status:503,notification_id:notificationId,error:result.error,message:result.message};}
   await s.rpc("sav_ai_crm_notification_record_result",{p_notification_id:notificationId,p_ok:true,p_provider:result.provider,p_provider_message_id:result.providerMessageId,p_status:result.status,p_error_code:null,p_error_message:null,p_raw:{},p_retryable:false});
   return {ok:true,status:200,notification_id:notificationId,delivery_status:result.status,provider:result.provider,provider_message_id:result.providerMessageId};
 }
 if(p.channel==="webhook"){
   const adapter=getNotificationWebhookAdapter();const result=await adapter.sendWebhook({workspaceId:p.workspace_id,notificationId,eventId:"notification:"+notificationId+":"+(p.retry_count||0),eventType:p.notification_type||"NOTIFICATION",timestamp:new Date().toISOString(),endpointRef:String(p.metadata?.endpoint_ref||""),payload:{notification_id:notificationId,type:p.notification_type,title:p.title,body:p.body,deep_link:p.deep_link,metadata:p.metadata}});
   if(!result.ok){await recordFailure(s,notificationId,"webhook",result.error,result.message,Boolean(result.retryable),{});return {ok:false,status:503,notification_id:notificationId,error:result.error,message:result.message};}
   await s.rpc("sav_ai_crm_notification_record_result",{p_notification_id:notificationId,p_ok:true,p_provider:result.provider,p_provider_message_id:result.providerMessageId,p_status:result.status,p_error_code:null,p_error_message:null,p_raw:{},p_retryable:false});
   return {ok:true,status:200,notification_id:notificationId,delivery_status:result.status,provider:result.provider,provider_message_id:result.providerMessageId};
 }
 await recordFailure(s,notificationId,"unknown","CHANNEL_CAPABILITY_NOT_SUPPORTED","Unsupported notification channel.",false,{});return {ok:false,status:422,notification_id:notificationId,error:"CHANNEL_CAPABILITY_NOT_SUPPORTED",message:"Unsupported notification channel."};
}

async function recordFailure(s:ReturnType<typeof serverSupabase>,id:string,provider:string,code:string,message:string,retryable:boolean,raw:Record<string,unknown>){await s.rpc("sav_ai_crm_notification_record_result",{p_notification_id:id,p_ok:false,p_provider:provider,p_provider_message_id:null,p_status:null,p_error_code:code,p_error_message:message,p_raw:raw,p_retryable:retryable});}
