import OpenAI from "openai";

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

const OPENAI_PROVIDER="openai";

function clampConfidence(value:unknown){
  const n=typeof value==="number"?value:Number(value);
  if(!Number.isFinite(n)) return 0;
  return Math.max(0,Math.min(1,n));
}

function parseJsonObject(text:string):Record<string,unknown>{
  const parsed=JSON.parse(text) as unknown;
  if(!parsed||typeof parsed!=="object"||Array.isArray(parsed)) throw new Error("Expected an object response");
  return parsed as Record<string,unknown>;
}

class UnconfiguredProvider implements AIProvider {
  private result<T>():AIProviderResult<T>{
    return {ok:false,error:"AI_PROVIDER_NOT_CONFIGURED",message:"OpenAI provider configuration requires AI_PROVIDER=openai, AI_API_KEY, and AI_MODEL in the server environment."};
  }
  generateResponse(){ return Promise.resolve(this.result<{text:string}>()); }
  classifyIntent(){ return Promise.resolve(this.result<{intent:string;confidence:number}>()); }
  extractLeadData(){ return Promise.resolve(this.result<Record<string,unknown>>()); }
  summarizeConversation(){ return Promise.resolve(this.result<{summary:string}>()); }
  planAction(){ return Promise.resolve(this.result<{action:string;payload:Record<string,unknown>;confidence:number}>()); }
  evaluateConfidence(){ return Promise.resolve(this.result<{confidence:number}>()); }
}

class AdapterUnavailableProvider extends UnconfiguredProvider {
  constructor(private readonly configuredProvider:string){ super(); }
  private unavailable<T>():AIProviderResult<T>{
    return {ok:false,error:"AI_PROVIDER_ERROR",message:`Unsupported AI_PROVIDER "${this.configuredProvider}". This build supports AI_PROVIDER=openai.`};
  }
  generateResponse(){ return Promise.resolve(this.unavailable<{text:string}>()); }
  classifyIntent(){ return Promise.resolve(this.unavailable<{intent:string;confidence:number}>()); }
  extractLeadData(){ return Promise.resolve(this.unavailable<Record<string,unknown>>()); }
  summarizeConversation(){ return Promise.resolve(this.unavailable<{summary:string}>()); }
  planAction(){ return Promise.resolve(this.unavailable<{action:string;payload:Record<string,unknown>;confidence:number}>()); }
  evaluateConfidence(){ return Promise.resolve(this.unavailable<{confidence:number}>()); }
}

class OpenAIProvider implements AIProvider {
  private readonly client:OpenAI;

  constructor(private readonly apiKey:string,private readonly model:string){
    this.client=new OpenAI({apiKey:this.apiKey});
  }

  private error<T>():AIProviderResult<T>{
    return {ok:false,error:"AI_PROVIDER_ERROR",message:"OpenAI Responses API request failed."};
  }

  async generateResponse(input:{prompt:string;context?:Record<string,unknown>}):Promise<AIProviderResult<{text:string}>>{
    try{
      const response=await this.client.responses.create({
        model:this.model,
        instructions:"Respond to the CRM user request accurately. Do not perform external actions. Return text only.",
        input:JSON.stringify({prompt:input.prompt,context:input.context||{}}),
        store:false
      });
      return {ok:true,data:{text:response.output_text},provider:OPENAI_PROVIDER};
    }catch{
      return this.error<{text:string}>();
    }
  }

  async classifyIntent(input:{text:string}):Promise<AIProviderResult<{intent:string;confidence:number}>>{
    try{
      const response=await this.client.responses.create({
        model:this.model,
        instructions:"Classify the CRM intent. Return the requested structured JSON only.",
        input:input.text,
        text:{format:{
          type:"json_schema",
          name:"crm_intent",
          strict:true,
          schema:{
            type:"object",
            additionalProperties:false,
            properties:{
              intent:{type:"string"},
              confidence:{type:"number",minimum:0,maximum:1}
            },
            required:["intent","confidence"]
          }
        }},
        store:false
      });
      const parsed=parseJsonObject(response.output_text);
      return {ok:true,data:{intent:String(parsed.intent||""),confidence:clampConfidence(parsed.confidence)},provider:OPENAI_PROVIDER};
    }catch{
      return this.error<{intent:string;confidence:number}>();
    }
  }

  async extractLeadData(input:{text:string}):Promise<AIProviderResult<Record<string,unknown>>>{
    try{
      const response=await this.client.responses.create({
        model:this.model,
        instructions:"Extract only CRM lead facts explicitly present in the input. Return a JSON object and do not infer missing facts.",
        input:input.text,
        text:{format:{type:"json_object"}},
        store:false
      });
      return {ok:true,data:parseJsonObject(response.output_text),provider:OPENAI_PROVIDER};
    }catch{
      return this.error<Record<string,unknown>>();
    }
  }

  async summarizeConversation(input:{messages:Array<{role:string;content:string}>}):Promise<AIProviderResult<{summary:string}>>{
    try{
      const response=await this.client.responses.create({
        model:this.model,
        instructions:"Summarize this CRM conversation factually. Do not perform or propose an external action unless the conversation explicitly asks for one.",
        input:JSON.stringify(input.messages),
        store:false
      });
      return {ok:true,data:{summary:response.output_text},provider:OPENAI_PROVIDER};
    }catch{
      return this.error<{summary:string}>();
    }
  }

  async planAction(input:{command:string;context?:Record<string,unknown>}):Promise<AIProviderResult<{action:string;payload:Record<string,unknown>;confidence:number}>>{
    try{
      const response=await this.client.responses.create({
        model:this.model,
        instructions:[
          "You are SAV-Sales, a sales qualification and follow-up planning agent inside SAVRDH AI Workforce.",
          "Analyze only the CRM information provided in the request.",
          "Do not send messages, call anyone, change CRM data, trigger tools, or perform any external action.",
          "Return a sales qualification plan with exactly the requested structured fields.",
          "If information is missing, state that explicitly instead of inventing it.",
          "The next best action and follow-up are recommendations for a human or approved workflow only."
        ].join("\n"),
        input:JSON.stringify({command:input.command,context:input.context||{}}),
        text:{format:{
          type:"json_schema",
          name:"sav_sales_qualification_plan",
          strict:true,
          schema:{
            type:"object",
            additionalProperties:false,
            properties:{
              lead_requirement:{type:"string"},
              qualification_status:{type:"string"},
              missing_information:{type:"array",items:{type:"string"}},
              next_best_action:{type:"string"},
              recommended_follow_up:{type:"string"},
              confidence:{type:"number",minimum:0,maximum:1}
            },
            required:[
              "lead_requirement",
              "qualification_status",
              "missing_information",
              "next_best_action",
              "recommended_follow_up",
              "confidence"
            ]
          }
        }},
        store:false
      });

      const parsed=parseJsonObject(response.output_text);
      const missing=Array.isArray(parsed.missing_information)
        ? parsed.missing_information.filter((value):value is string=>typeof value==="string")
        : [];

      const payload:Record<string,unknown>={
        lead_requirement:String(parsed.lead_requirement||""),
        qualification_status:String(parsed.qualification_status||""),
        missing_information:missing,
        next_best_action:String(parsed.next_best_action||""),
        recommended_follow_up:String(parsed.recommended_follow_up||""),
        external_action_performed:false
      };

      return {
        ok:true,
        data:{
          action:"sales_qualification_plan",
          payload,
          confidence:clampConfidence(parsed.confidence)
        },
        provider:OPENAI_PROVIDER
      };
    }catch{
      return this.error<{action:string;payload:Record<string,unknown>;confidence:number}>();
    }
  }

  async evaluateConfidence(input:{output:unknown}):Promise<AIProviderResult<{confidence:number}>>{
    try{
      const response=await this.client.responses.create({
        model:this.model,
        instructions:"Evaluate confidence in the supplied CRM analysis based only on the supplied content. Return structured JSON.",
        input:JSON.stringify(input.output),
        text:{format:{
          type:"json_schema",
          name:"crm_confidence",
          strict:true,
          schema:{
            type:"object",
            additionalProperties:false,
            properties:{confidence:{type:"number",minimum:0,maximum:1}},
            required:["confidence"]
          }
        }},
        store:false
      });
      const parsed=parseJsonObject(response.output_text);
      return {ok:true,data:{confidence:clampConfidence(parsed.confidence)},provider:OPENAI_PROVIDER};
    }catch{
      return this.error<{confidence:number}>();
    }
  }
}

export function getAIProvider():AIProvider {
  const provider=(process.env.AI_PROVIDER||"").trim().toLowerCase();
  const apiKey=(process.env.AI_API_KEY||"").trim();
  const model=(process.env.AI_MODEL||"").trim();

  if(!provider||!apiKey||!model) return new UnconfiguredProvider();
  if(provider!==OPENAI_PROVIDER) return new AdapterUnavailableProvider(provider);
  return new OpenAIProvider(apiKey,model);
}
