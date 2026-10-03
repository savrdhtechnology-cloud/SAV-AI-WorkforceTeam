"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { Bot, Loader2 } from "lucide-react";
import { crmSupabase, crmSupabaseConfigured } from "../supabase-client";
import AgentsModule from "./AgentsModule";
import "../crm.css";

export default function AgentsRouteShell({agentId}:{agentId?:string}){
  const [ready,setReady]=useState(false);
  const [authed,setAuthed]=useState(false);
  useEffect(()=>{if(!crmSupabaseConfigured)return;crmSupabase.auth.getSession().then(({data})=>{setAuthed(Boolean(data.session));setReady(true);});},[]);
  if(!crmSupabaseConfigured)return <div className="crm-auth-page"><div className="crm-auth-card" role="alert"><h2>CRM configuration required</h2><p>Supabase environment is not configured for this deployment.</p></div></div>;
 if(!ready)return <div className="crm-auth-page"><Loader2 className="spin" size={20}/></div>;
  if(!authed)return <div className="crm-auth-page"><div className="crm-auth-card"><Bot size={24}/><h2>CRM sign-in required</h2><p>Sign in through the SAVRDH AI CRM before managing agents.</p><Link href="/crm">Open CRM Login</Link></div></div>;
  return <div className="agent-route-page">
    <header className="agent-route-head"><div><small>SAV AI COMMAND CENTER</small><h1>AI Agents</h1></div><Link href="/crm">Back to CRM</Link></header>
    <AgentsModule focusedId={agentId}/>
  </div>;
}
