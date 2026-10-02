"use client";

import { useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { CheckCircle2, Network } from "lucide-react";

const integrations = [
  { name: "WhatsApp Business", latency: "18ms", type: "Messaging Gateway" },
  { name: "Voice Telephony AI", latency: "32ms", type: "SIP / WebRTC" },
  { name: "Savrdh CRM", latency: "12ms", type: "Native CRM" },
  { name: "Transactional Email", latency: "45ms", type: "SMTP / Resend" },
  { name: "SMS Gateway", latency: "28ms", type: "Messaging API" },
  { name: "Supabase Postgres", latency: "14ms", type: "Data + Vector Store" },
  { name: "Custom Webhooks", latency: "22ms", type: "Real-time Ingestion" },
  { name: "REST API", latency: "16ms", type: "Developer Interface" },
];

export default function InteractiveEcosystem() {
  const [selected, setSelected] = useState(integrations[0]);

  return (
    <section id="integrations" className="section ecosystem-section">
      <div className="section-kicker"><Network size={14} /> BUILT TO WORK WITH YOUR STACK</div>
      <div className="section-heading">
        <h2>Connect the systems your team already depends on.</h2>
        <p>Unify communication, CRM, business data and workflow systems so every SAV agent works from the same trusted context.</p>
      </div>

      <div className="ecosystem-panel">
        <div className="ecosystem-rings" aria-hidden="true">
          <motion.i animate={{ scale: [1, 1.8, 1], opacity: [.35, 0, .35] }} transition={{ duration: 6, repeat: Infinity }} />
          <motion.i animate={{ scale: [1, 2.15, 1], opacity: [.22, 0, .22] }} transition={{ duration: 7, delay: 1, repeat: Infinity }} />
        </div>

        <motion.div className="ecosystem-core" whileHover={{ scale: 1.05 }}>
          <div className="brand-mark"><span/><span/><span/></div>
          <strong>SAV</strong>
          <small>AI CORE</small>
        </motion.div>

        <div className="ecosystem-grid">
          {integrations.map((item) => {
            const active = selected.name === item.name;
            return (
              <motion.button
                key={item.name}
                onClick={() => setSelected(item)}
                whileHover={{ y: -5, scale: 1.02 }}
                whileTap={{ scale: .98 }}
                className={active ? "active" : ""}
              >
                <div className="eco-node-top"><i /><span>{item.latency}</span></div>
                <strong>{item.name}</strong>
                <small>{item.type}</small>
              </motion.button>
            );
          })}
        </div>

        <AnimatePresence mode="wait">
          <motion.div
            key={selected.name}
            className="ecosystem-status"
            initial={{ opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -10 }}
          >
            <CheckCircle2 size={17} />
            <div>
              <strong>{selected.name} Adapter</strong>
              <span>Continuous bi-directional synchronization</span>
            </div>
            <b>{selected.latency}</b>
            <em>ONLINE</em>
          </motion.div>
        </AnimatePresence>
      </div>
    </section>
  );
}
