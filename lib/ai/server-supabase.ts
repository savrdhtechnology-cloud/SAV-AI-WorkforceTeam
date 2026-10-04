import { createClient } from "@supabase/supabase-js";
import { NextRequest } from "next/server";

const url=process.env.NEXT_PUBLIC_SUPABASE_URL?.trim()||"";
const key=process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY?.trim()||"";

export function supabaseConfigured(){
  return Boolean(url&&key);
}

export function serverSupabase(req:NextRequest){
  if (!supabaseConfigured()) throw new Error("Supabase environment is not configured");
  const authorization=req.headers.get("authorization") || "";
  return createClient(url,key,{
    auth:{persistSession:false,autoRefreshToken:false},
    global:{headers: authorization ? {Authorization:authorization} : {}}
  });
}

export function jsonError(message:string,status=400,code?:string){
  return Response.json({error:code||"REQUEST_FAILED",message},{status});
}

export function bearerPresent(req:NextRequest){
  return /^Bearer\s+\S+$/i.test(req.headers.get("authorization")||"");
}

export function serverAdminSupabase(){
  const serviceKey=process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();
  if(!serviceKey || !supabaseConfigured()) return null;
  return createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
}
