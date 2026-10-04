"use client";
import Link from "next/link";
import { useEffect,useState } from "react";
import { Activity,Loader2 } from "lucide-react";
import { crmSupabase } from "../supabase-client";
import "../crm.css";
export default function ExecutionList(){
 const [ready,setReady]=useState(false),[rows,setRows]=useState<any[]>([]),[error,setError]=useState("");
 useEffect(()=>{crmSupabase.auth.getSession().then(async({data})=>{if(!data.session){setReady(true);return;}const {data:r,error:e}=await crmSupabase.rpc("sav_ai_crm_workflow_executions",{p_workflow_id:null});if(e)setError(e.message);else setRows(r||[]);setReady(true);});},[]);
 if(!ready)return <div className="workflow-loading"><Loader2 className="spin" size={20}/>Loading executions...</div>;
 return <div className="workflow-execution-page"><header className="agent-route-head"><div><small>SAV AI COMMAND CENTER</small><h1>Workflow Executions</h1></div><Link href="/crm/workflows">Back to Workflows</Link></header>{error&&<div className="task-error">{error}</div>}<div className="crm-panel">{rows.length?<table className="crm-table"><thead><tr><th>WORKFLOW</th><th>TRIGGER</th><th>CURRENT NODE</th><th>STATUS</th><th>STARTED</th><th>UPDATED</th><th>COMPLETED</th><th>ERROR</th></tr></thead><tbody>{rows.map(r=><tr key={r.id}><td><Link href={`/crm/workflows/executions/${r.id}`}>{r.workflow_name}</Link></td><td>{r.trigger}</td><td>{r.current_node_id||"—"}</td><td>{r.execution_state}</td><td>{fmt(r.started_at)}</td><td>{fmt(r.updated_at)}</td><td>{fmt(r.completed_at)}</td><td>{r.error||"—"}</td></tr>)}</tbody></table>:<div className="crm-empty"><div><Activity size={24}/><h3>No workflow executions</h3><p>Execution history will appear here.</p></div></div>}</div></div>;
}
function fmt(v?:string|null){return v?new Date(v).toLocaleString("en-IN"):"—";}
