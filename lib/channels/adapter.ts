export type ChannelKind = "whatsapp"|"sms"|"email"|"voice"|"webchat";

export type ChannelSendRequest = {
  channel: ChannelKind;
  to: string;
  body: string;
  metadata?: Record<string,unknown>;
};

export type ChannelSendResult =
  | { ok:true; provider:string; externalId:string }
  | { ok:false; error:"CHANNEL_PROVIDER_NOT_CONFIGURED"|"CHANNEL_PROVIDER_ERROR"; message:string };

export interface ChannelAdapter {
  kind: ChannelKind;
  send(input:ChannelSendRequest):Promise<ChannelSendResult>;
}

export class UnconfiguredChannelAdapter implements ChannelAdapter {
  constructor(public kind:ChannelKind){}
  async send():Promise<ChannelSendResult>{
    return {ok:false,error:"CHANNEL_PROVIDER_NOT_CONFIGURED",message:`${this.kind} provider is not configured.`};
  }
}

export function getChannelAdapter(kind:ChannelKind):ChannelAdapter{
  // Real providers are intentionally not implemented in Phase 2.
  return new UnconfiguredChannelAdapter(kind);
}
