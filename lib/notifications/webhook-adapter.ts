import "server-only";
export type NotificationWebhookResult={ok:true;provider:"webhook";providerMessageId:string;status:"SENT"|"DELIVERED"}|{ok:false;error:"WEBHOOK_PROVIDER_NOT_CONFIGURED"|"WEBHOOK_DELIVERY_FAILED"|"WEBHOOK_SIGNATURE_CONFIG_REQUIRED";message:string;retryable?:boolean};
export interface NotificationWebhookAdapter{
 createSignature(input:{workspaceId:string;endpointRef:string;payload:Record<string,unknown>}):Promise<{ok:true;signature:string}|NotificationWebhookResult>;
 sendWebhook(input:{workspaceId:string;notificationId:string;eventId:string;eventType:string;timestamp:string;endpointRef:string;payload:Record<string,unknown>}):Promise<NotificationWebhookResult>;
 getDeliveryStatus(providerMessageId:string):Promise<NotificationWebhookResult>;
}
class UnconfiguredWebhookAdapter implements NotificationWebhookAdapter{
 private fail():NotificationWebhookResult{return {ok:false,error:"WEBHOOK_PROVIDER_NOT_CONFIGURED",message:"Notification webhook endpoint/signing provider is not configured.",retryable:false};}
 async createSignature(){return this.fail();} async sendWebhook(){return this.fail();} async getDeliveryStatus(){return this.fail();}
}
export function getNotificationWebhookAdapter():NotificationWebhookAdapter{return new UnconfiguredWebhookAdapter();}
