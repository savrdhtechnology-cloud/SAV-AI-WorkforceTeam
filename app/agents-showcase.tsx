"use client";

import { useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import {
  Activity,
  ArrowRight,
  Bot,
  BrainCircuit,
  Clock,
  FileCheck,
  Grid3X3,
  Headphones,
  LockKeyhole,
  PhoneCall,
  ShieldCheck,
  SlidersHorizontal,
} from "lucide-react";

const agentData = [
  { id:"sales", name:"SAV-Sales", role:"Sales & Follow-up Agent", icon:PhoneCall, category:"sales", description:"Qualifies leads, executes follow-ups and updates the CRM with intent and next actions.", stat:"42 leads queued", channels:["WhatsApp","Voice"] },
  { id:"bde", name:"SAV-BDE", role:"Business Development Agent", icon:ArrowRight, category:"sales", description:"Researches prospects, prepares outreach and keeps business development pipelines moving.", stat:"18 prospects active", channels:["Email","CRM"] },
  { id:"manager", name:"SAV-Sales Manager", role:"Pipeline Coordination Agent", icon:BrainCircuit, category:"sales", description:"Coordinates agent activity, prioritizes queues and surfaces exceptions for managers.", stat:"8 pipelines", channels:["CRM","Analytics"] },
  { id:"support", name:"SAV-Support", role:"Customer Care Agent", icon:Headphones, category:"support", description:"Answers routine queries from approved knowledge and escalates complex conversations.", stat:"24×7 available", channels:["WhatsApp","Email"] },
  { id:"followup", name:"SAV-Followup", role:"Persistent Follow-up Agent", icon:Clock, category:"support", description:"Runs scheduled follow-ups based on lead stage, customer response and SLA rules.", stat:"63 follow-ups", channels:["SMS","WhatsApp"] },
  { id:"finance", name:"SAV-Finance", role:"Finance Operations Agent", icon:ShieldCheck, category:"operations", description:"Coordinates payment reminders, verification queues and finance-related workflow tasks.", stat:"14 actions ready", channels:["Email","CRM"] },
  { id:"credit", name:"SAV-Credit", role:"Credit Workflow Agent", icon:ShieldCheck, category:"operations", description:"Routes credit workflows, document checks and approval requests under configured policies.", stat:"11 cases active", channels:["CRM","Database"] },
  { id:"document", name:"SAV-Document", role:"Document Intelligence Agent", icon:FileCheck, category:"operations", description:"Organizes documents, checks completeness and routes missing-document requests automatically.", stat:"27 files checked", channels:["Docs","Email"] },
];

export default function AgentsShowcase() {
  const [mode,setMode] = useState<"slider"|"grid">("slider");
  const [index,setIndex] = useState(0);
  const [filter,setFilter] = useState("all");
  const [selected,setSelected] = useState<(typeof agentData)[number] | null>(null);

  const visible = filter === "all" ? agentData : agentData.filter(a => a.category === filter);
  const sliderAgents = [agentData[index % agentData.length], agentData[(index+1)%agentData.length], agentData[(index+2)%agentData.length]];

  return (
    <section id="agents" className="section agents-showcase-section">
      <div className="agents-showcase-header">
        <div>
          <div className="section-kicker"><Bot size={14}/> SPECIALIZED AI WORKFORCE</div>
          <h2>Specialized AI agents. One coordinated team.</h2>
          <p>Give every agent a defined role, approved knowledge and action boundaries. SAV coordinates execution and surfaces only the moments that need human judgment.</p>
        </div>

        <div className="view-toggle">
          <button onClick={()=>setMode("slider")} className={mode==="slider"?"active":""}>
            {mode==="slider" && <motion.span layoutId="agent-view-pill"/>}
            <SlidersHorizontal size={14}/><b>3-Agent Slider</b>
          </button>
          <button onClick={()=>setMode("grid")} className={mode==="grid"?"active":""}>
            {mode==="grid" && <motion.span layoutId="agent-view-pill"/>}
            <Grid3X3 size={14}/><b>All Agents Grid</b>
          </button>
        </div>
      </div>

      {mode === "slider" ? (
        <div className="agent-slider-wrap">
          <div className="agent-slider-nav">
            <span>Showing 3 active agents</span>
            <div>
              <button onClick={()=>setIndex(v=>(v-1+agentData.length)%agentData.length)}>‹</button>
              <button onClick={()=>setIndex(v=>(v+1)%agentData.length)}>›</button>
            </div>
          </div>

          <AnimatePresence mode="popLayout">
            <motion.div layout className="agent-slider-grid" key={index}>
              {sliderAgents.map((agent,i)=>{
                const Icon=agent.icon;
                return (
                  <motion.article
                    key={agent.id}
                    initial={{opacity:0,y:24,scale:.96}}
                    animate={{opacity:1,y:0,scale:1}}
                    exit={{opacity:0,y:-20,scale:.96}}
                    transition={{delay:i*.08}}
                    whileHover={{y:-8,scale:1.015}}
                    onClick={()=>setSelected(agent)}
                  >
                    <div className="agent-card-top">
                      <div className="agent-avatar"><Icon size={21}/></div>
                      <span className="agent-status"><i/> ACTIVE</span>
                    </div>
                    <h3>{agent.name}</h3>
                    <small>{agent.role}</small>
                    <p>{agent.description}</p>
                    <div className="agent-tags">{agent.channels.map(c=><span key={c}>{c}</span>)}</div>
                    <div className="agent-card-bottom"><b>{agent.stat}</b><em>Inspect <ArrowRight size={12}/></em></div>
                  </motion.article>
                );
              })}
            </motion.div>
          </AnimatePresence>
        </div>
      ) : (
        <>
          <div className="agent-filter-row">
            {[["all","All Agents (8)"],["sales","Sales & Growth"],["operations","Operations & Risk"],["support","Support & Care"]].map(([id,label])=>(
              <button key={id} className={filter===id?"active":""} onClick={()=>setFilter(id)}>{label}</button>
            ))}
          </div>
          <motion.div layout className="agents-all-grid">
            <AnimatePresence>
              {visible.map(agent=>{
                const Icon=agent.icon;
                return (
                  <motion.article
                    layout
                    key={agent.id}
                    initial={{opacity:0,scale:.92}}
                    animate={{opacity:1,scale:1}}
                    exit={{opacity:0,scale:.92}}
                    whileHover={{y:-6}}
                    onClick={()=>setSelected(agent)}
                  >
                    <div className="agent-card-top"><div className="agent-avatar"><Icon size={20}/></div><span className="agent-status"><i/> ACTIVE</span></div>
                    <h3>{agent.name}</h3>
                    <small>{agent.role}</small>
                    <p>{agent.description}</p>
                    <div className="agent-tags">{agent.channels.map(c=><span key={c}>{c}</span>)}</div>
                    <div className="agent-card-bottom"><b>{agent.stat}</b><em>Inspect <ArrowRight size={12}/></em></div>
                  </motion.article>
                );
              })}
            </AnimatePresence>
          </motion.div>
        </>
      )}

      <div className="agent-trust-row">
        <span><LockKeyhole size={15}/> Role-based execution boundaries</span>
        <span><Activity size={15}/> Real-time action audit trail</span>
        <span><BrainCircuit size={15}/> Shared working context</span>
      </div>

      <AnimatePresence>
        {selected && (
          <motion.div className="agent-modal-backdrop" initial={{opacity:0}} animate={{opacity:1}} exit={{opacity:0}} onClick={()=>setSelected(null)}>
            <motion.div className="agent-modal" initial={{opacity:0,scale:.95,y:16}} animate={{opacity:1,scale:1,y:0}} exit={{opacity:0,scale:.95,y:16}} onClick={e=>e.stopPropagation()}>
              <div className="agent-modal-head">
                <div className="agent-avatar"><selected.icon size={22}/></div>
                <div><h3>{selected.name}</h3><small>{selected.role}</small></div>
                <button onClick={()=>setSelected(null)}>×</button>
              </div>
              <p>{selected.description}</p>
              <div className="agent-modal-info">
                <div><span>LIVE WORKLOAD</span><b>{selected.stat}</b></div>
                <div><span>CHANNELS</span><b>{selected.channels.join(" · ")}</b></div>
              </div>
              <a href="#workflow" onClick={()=>setSelected(null)}>Test in Workflow Simulator →</a>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
    </section>
  )
}
