"use client";
import Link from "next/link";
import { useEffect,useState } from "react";
import { Inbox,Loader2 } from "lucide-react";
import { crmSupabase, crmSupabaseConfigured } from "../supabase-client";
import InboxModule from "./InboxModule";
import "../crm.css";
export default function InboxRouteShell(){
 const [ready,setReady]=useState(false),[authed,setAuthed]=useState(false);
 useEffect(()=>{if(!crmSupabaseConfigured)return;crmSupabase.auth.getSession().then(({data})=>{setAuthed(Boolean(data.session));setReady(true);});},[]);
 if(!crmSupabaseConfigured)return <div className="crm-auth-page"><div className="crm-auth-card" role="alert"><h2>CRM configuration required</h2><p>Supabase environment is not configured for this deployment.</p></div></div>;
 if(!ready)return <div className="crm-auth-page"><Loader2 className="spin" size={20}/></div>;
 if(!authed)return <div className="crm-auth-page"><div className="crm-auth-card"><Inbox size={24}/><h2>CRM sign-in required</h2><p>Sign in before opening the unified Inbox.</p><Link href="/crm">Open CRM Login</Link></div></div>;
 return <div className="inbox-route-page"><header className="agent-route-head"><div><small>SAV AI COMMAND CENTER</small><h1>Inbox & Channels</h1></div><Link href="/crm">Back to CRM</Link></header><InboxModule/></div>;
}