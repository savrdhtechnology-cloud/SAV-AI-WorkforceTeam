"use client";

import { useState } from "react";
import { motion } from "framer-motion";
import {
  BrainCircuit,
  CheckCircle2,
  Layers3,
  MessageCircleMore,
  PhoneCall,
  Play,
  Workflow,
} from "lucide-react";

const scenarios = [
  {
    id: "lead",
    title: "Lead Follow-up",
    description: "A new lead enters the CRM and SAV qualifies, contacts and updates the record automatically.",
    trigger: "New lead received in CRM",
    outcome: "Lead contacted, intent scored and CRM updated.",
    nodes: ["CRM Trigger", "SAV Orchestrator", "WhatsApp / Voice", "CRM Update"],
  },
  {
    id: "support",
    title: "Support Resolution",
    description: "An incoming customer question is answered from approved knowledge and escalated only if required.",
    trigger: "New support conversation",
    outcome: "Customer receives a grounded response or a human handoff.",
    nodes: ["Support Trigger", "SAV Orchestrator", "Knowledge Search", "Customer Reply"],
  },
  {
    id: "ops",
    title: "Operations Approval",
    description: "An operational task is validated, routed through policy and sent to the right system or approver.",
    trigger: "Pending operational action",
    outcome: "Task executed with approval and audit trail where required.",
    nodes: ["Task Trigger", "SAV Orchestrator", "Policy Gate", "System Action"],
  },
];

export default function InteractiveWorkflow() {
  const [scenarioIndex, setScenarioIndex] = useState(0);
  const [step, setStep] = useState(1);
  const [running, setRunning] = useState(false);
  const scenario = scenarios[scenarioIndex];

  const run = () => {
    setRunning(true);
    setStep(0);
    let next = 0;
    const id = window.setInterval(() => {
      next += 1;
      setStep(next);
      if (next >= 3) {
        window.clearInterval(id);
        window.setTimeout(() => setRunning(false), 450);
      }
    }, 800);
  };

  return (
    <section id="workflow" className="section interactive-workflow-section">
      <div className="workflow-header">
        <div>
          <div className="section-kicker">FROM INTENT TO EXECUTION</div>
          <h2>Describe the outcome. SAV coordinates the execution.</h2>
          <p>Test how SAV turns an event into coordinated, policy-aware actions across communication, approvals and connected systems.</p>
        </div>

        <div className="workflow-tabs">
          {scenarios.map((item, i) => (
            <button
              key={item.id}
              className={i === scenarioIndex ? "active" : ""}
              onClick={() => {
                setScenarioIndex(i);
                setStep(1);
              }}
            >
              {item.title}
            </button>
          ))}
        </div>
      </div>

      <div className="workflow-simulator">
        <div className="workflow-details">
          <span className="workflow-overline">SELECTED ORCHESTRATION PIPELINE</span>
          <h3>{scenario.title}</h3>
          <p>{scenario.description}</p>

          <div className="trigger-card">
            <small>EVENT TRIGGER IDENTIFIED</small>
            <strong><i /> {scenario.trigger}</strong>
          </div>

          <div className="workflow-run-row">
            <motion.button
              onClick={run}
              disabled={running}
              whileHover={{ scale: 1.035 }}
              whileTap={{ scale: 0.97 }}
            >
              <Play size={15} fill="currentColor" />
              {running ? "EXECUTING..." : "TEST PIPELINE EXECUTION"}
            </motion.button>
            <span>Step {Math.min(step + 1, 4)} of 4</span>
          </div>

          <div className="workflow-outcome">
            <CheckCircle2 size={17} />
            <span><b>Expected outcome:</b> {scenario.outcome}</span>
          </div>
        </div>

        <div className="workflow-graph">
          <motion.div
            className="graph-node trigger-node"
            animate={{
              scale: step === 0 ? 1.07 : 1,
              boxShadow: step === 0 ? "0 0 30px rgba(73,227,255,.35)" : "0 0 0 rgba(73,227,255,0)",
            }}
          >
            <MessageCircleMore size={18} />
            <div><small>NODE 01: TRIGGER</small><strong>{scenario.nodes[0]}</strong></div>
          </motion.div>

          <div className="graph-line">
            <motion.i
              animate={step >= 1 ? { y: [0, 42], opacity: [0, 1, 0] } : { opacity: .15 }}
              transition={{ duration: 1.2, repeat: Infinity, ease: "linear" }}
            />
          </div>

          <motion.div
            className="graph-node orchestrator-node"
            animate={{
              scale: step === 1 ? 1.08 : 1,
              boxShadow: step === 1 ? "0 0 35px rgba(91,140,255,.42)" : "0 0 10px rgba(91,140,255,.08)",
            }}
          >
            <BrainCircuit size={20} />
            <div><small>SAV ORCHESTRATOR</small><strong>{scenario.nodes[1]}</strong></div>
          </motion.div>

          <div className="graph-branches">
            <svg viewBox="0 0 360 60" preserveAspectRatio="none">
              <motion.path d="M180 0 V28 C180 38 62 38 62 60" fill="none" stroke="#49E3FF" strokeWidth="2" strokeDasharray="5 5" animate={{ pathLength: step >= 2 ? 1 : .15 }} />
              <motion.path d="M180 0 V60" fill="none" stroke="#5B8CFF" strokeWidth="2" animate={{ pathLength: step >= 2 ? 1 : .15 }} />
              <motion.path d="M180 0 V28 C180 38 298 38 298 60" fill="none" stroke="#7A5CFF" strokeWidth="2" strokeDasharray="5 5" animate={{ pathLength: step >= 2 ? 1 : .15 }} />
            </svg>
          </div>

          <div className="graph-results">
            {[
              [PhoneCall, "COMMUNICATION", scenario.nodes[2]],
              [Workflow, "ACTION GATE", "Policy decision"],
              [Layers3, "INTEGRATION", scenario.nodes[3]],
            ].map(([Icon, label, name], i) => {
              const I = Icon as typeof PhoneCall;
              return (
                <motion.div
                  key={label as string}
                  animate={{
                    y: step >= 2 ? [0, -5, 0] : 0,
                    borderColor: step >= 2 ? ["#244867", i === 0 ? "#49E3FF" : i === 1 ? "#5B8CFF" : "#7A5CFF", "#244867"] : "#244867",
                  }}
                  transition={{ duration: 2.6 + i * .3, repeat: Infinity }}
                >
                  <I size={16} />
                  <small>{label as string}</small>
                  <strong>{name as string}</strong>
                </motion.div>
              );
            })}
          </div>
        </div>
      </div>
    </section>
  );
}
