export type AIProviderResult<T> =
  | { ok:true; data:T; provider:string }
  | { ok:false; error:"AI_PROVIDER_NOT_CONFIGURED"|"AI_PROVIDER_ERROR"; message:string };

export interface AIProvider {
  generateResponse(input:{prompt:string;context?:Record<string,unknown>}):Promise<AIProviderResult<{text:string}>>;
  classifyIntent(input:{text:string}):Promise<AIProviderResult<{intent:string;confidence:number}>>;
  extractLeadData(input:{text:string}):Promise<AIProviderResult<Record<string,unknown>>>;
  summarizeConversation(input:{messages:Array<{role:string;content:string}>}):Promise<AIProviderResult<{summary:string}>>;
  planAction(input:{command:string;context?:Record<string,unknown>}):Promise<AIProviderResult<{action:string;payload:Record<string,unknown>;confidence:number}>>;
  evaluateConfidence(input:{output:unknown}):Promise<AIProviderResult<{confidence:number}>>;
}

class UnconfiguredProvider implements AIProvider {
  private result<T>():AIProviderResult<T>{
    return {ok:false,error:"AI_PROVIDER_NOT_CONFIGURED",message:"No AI provider credentials are configured for this environment."};
  }
  generateResponse(){ return Promise.resolve(this.result<{text:string}>()); }
  classifyIntent(){ return Promise.resolve(this.result<{intent:string;confidence:number}>()); }
  extractLeadData(){ return Promise.resolve(this.result<Record<string,unknown>>()); }
  summarizeConversation(){ return Promise.resolve(this.result<{summary:string}>()); }
  planAction(){ return Promise.resolve(this.result<{action:string;payload:Record<string,unknown>;confidence:number}>()); }
  evaluateConfidence(){ return Promise.resolve(this.result<{confidence:number}>()); }
}

export function getAIProvider():AIProvider {
  // Provider adapters will be wired here later. Configuration is deliberately
  // not treated as successful AI execution until a real adapter is present.
  return new UnconfiguredProvider();
}
