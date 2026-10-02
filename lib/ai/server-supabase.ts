import { createClient } from "@supabase/supabase-js";
import { NextRequest } from "next/server";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL || "https://ldffgetuzoeupuhoaubn.supabase.co";
const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || "sb_publishable_KzdI4K0qLXgi3MhA5GXPhg_6f5vB8By";

export function serverSupabase(req:NextRequest){
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
