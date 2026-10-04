import "server-only";
export type PushSendResult={ok:true;provider:string;providerMessageId:string;status:"SENT"|"DELIVERED"}|{ok:false;error:"PUSH_PROVIDER_NOT_CONFIGURED"|"PUSH_PROVIDER_ERROR";message:string;retryable?:boolean};
export interface PushAdapter{
 registerDevice(input:{workspaceId:string;memberId:string;deviceToken:string;platform:string;metadata?:Record<string,unknown>}):Promise<{ok:true;deviceId:string}|PushSendResult>;
 unregisterDevice(input:{workspaceId:string;deviceId:string}):Promise<{ok:true}|PushSendResult>;
 sendPush(input:{workspaceId:string;notificationId:string;deviceToken:string;title:string;body:string;deepLink?:string|null}):Promise<PushSendResult>;
 getDeliveryStatus(providerMessageId:string):Promise<PushSendResult>;
}
class UnconfiguredPushAdapter implements PushAdapter{
 private fail():PushSendResult{return {ok:false,error:"PUSH_PROVIDER_NOT_CONFIGURED",message:"Push provider is not configured.",retryable:false};}
 async registerDevice(){return this.fail();} async unregisterDevice(){return this.fail();}
 async sendPush(){return this.fail();} async getDeliveryStatus(){return this.fail();}
}
export function getPushAdapter():PushAdapter{return new UnconfiguredPushAdapter();}
