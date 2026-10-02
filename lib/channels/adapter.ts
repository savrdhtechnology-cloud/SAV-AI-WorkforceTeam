export type ChannelKind="whatsapp"|"sms"|"email"|"voice"|"webchat";

export type ChannelIdentity={
  address:string;
  displayName?:string|null;
};

export type ChannelAttachment={
  fileName:string;
  mimeType:string;
  sizeBytes?:number|null;
  externalUrl?:string|null;
  providerAttachmentId?:string|null;
  metadata?:Record<string,unknown>;
};

export type ChannelOutboundMessage={
  channel:ChannelKind;
  workspaceId:string;
  channelAccountId?:string|null;
  conversationId:string;
  messageId:string;
  from?:ChannelIdentity|null;
  to:ChannelIdentity;
  messageType:"text"|"html"|"image"|"file"|"audio"|"video";
  body?:string|null;
  attachments?:ChannelAttachment[];
  metadata?:Record<string,unknown>;
};

export type ChannelSendSuccess={
  ok:true;
  provider:string;
  providerMessageId:string;
  status:"SENT"|"DELIVERED";
  raw?:Record<string,unknown>;
};
export type ChannelSendFailure={
  ok:false;
  error:"CHANNEL_PROVIDER_NOT_CONFIGURED"|"CHANNEL_PROVIDER_ERROR"|"CHANNEL_CAPABILITY_NOT_SUPPORTED"|"CHANNEL_INVALID_REQUEST";
  message:string;
  retryable?:boolean;
  raw?:Record<string,unknown>;
};
export type ChannelSendResult=ChannelSendSuccess|ChannelSendFailure;

export type ChannelDeliveryResult={
  ok:true;
  provider:string;
  providerMessageId:string;
  status:"SENT"|"DELIVERED"|"READ"|"FAILED";
  raw?:Record<string,unknown>;
}|ChannelSendFailure;

export type RawInboundEnvelope={
  headers:Record<string,string>;
  body:unknown;
  query?:Record<string,string>;
};

export type NormalizedInboundMessage={
  provider:string;
  channel:ChannelKind;
  workspaceExternalKey?:string|null;
  channelAccountExternalId?:string|null;
  providerEventId:string;
  providerMessageId:string;
  externalThreadId?:string|null;
  sender:ChannelIdentity;
  recipient:ChannelIdentity;
  messageType:"text"|"html"|"image"|"file"|"audio"|"video";
  body?:string|null;
  attachments?:ChannelAttachment[];
  receivedAt:string;
  metadata?:Record<string,unknown>;
};

export type WebhookVerification=
  |{ok:true;provider:string;workspaceExternalKey?:string|null;channelAccountExternalId?:string|null}
  |{ok:false;error:"CHANNEL_PROVIDER_NOT_CONFIGURED"|"WEBHOOK_SIGNATURE_INVALID"|"WEBHOOK_UNSUPPORTED";message:string};

export interface ChannelAdapter{
  kind:ChannelKind;
  provider:string;
  sendMessage(input:ChannelOutboundMessage):Promise<ChannelSendResult>;
  receiveMessage(input:NormalizedInboundMessage):Promise<{ok:true}>;
  getDeliveryStatus(providerMessageId:string):Promise<ChannelDeliveryResult>;
  verifyWebhook(envelope:RawInboundEnvelope):Promise<WebhookVerification>;
  normalizeInboundMessage(envelope:RawInboundEnvelope):Promise<NormalizedInboundMessage|ChannelSendFailure>;
}

export class UnconfiguredChannelAdapter implements ChannelAdapter{
  provider="unconfigured";
  constructor(public kind:ChannelKind){}
  private failure():ChannelSendFailure{
    return {ok:false,error:"CHANNEL_PROVIDER_NOT_CONFIGURED",message:`${this.kind} provider is not configured.`,retryable:false};
  }
  async sendMessage():Promise<ChannelSendResult>{return this.failure();}
  async receiveMessage():Promise<{ok:true}>{throw new Error("CHANNEL_PROVIDER_NOT_CONFIGURED");}
  async getDeliveryStatus():Promise<ChannelDeliveryResult>{return this.failure();}
  async verifyWebhook():Promise<WebhookVerification>{
    return {ok:false,error:"CHANNEL_PROVIDER_NOT_CONFIGURED",message:`${this.kind} provider webhook is not configured.`};
  }
  async normalizeInboundMessage():Promise<ChannelSendFailure>{return this.failure();}
}

// Backward compatibility for Phase 2 callers.
export type ChannelSendRequest={channel:ChannelKind;to:string;body:string;metadata?:Record<string,unknown>};
export interface LegacyChannelAdapter{kind:ChannelKind;send(input:ChannelSendRequest):Promise<ChannelSendResult>;}

export function getChannelAdapter(kind:ChannelKind):ChannelAdapter{
  // Provider implementations are intentionally absent in Phase 4 unless credentials/provider code already exists.
  // This registry must stay server-controlled. Never accept provider credentials or adapter classes from the frontend.
  return new UnconfiguredChannelAdapter(kind);
}
