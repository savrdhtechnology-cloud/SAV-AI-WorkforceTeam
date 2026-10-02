import "server-only";
import { ChannelAdapter,ChannelKind,getChannelAdapter } from "./adapter";

const allowed=new Set<ChannelKind>(["whatsapp","email","sms","voice","webchat"]);

export function resolveChannelAdapter(channel:string):ChannelAdapter{
  if(!allowed.has(channel as ChannelKind))throw new Error("CHANNEL_INVALID_REQUEST");
  return getChannelAdapter(channel as ChannelKind);
}
