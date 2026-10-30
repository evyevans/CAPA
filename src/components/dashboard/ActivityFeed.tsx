import React, { useEffect, useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';

interface TaskLog {
  id: string;
  agent_id: string;
  task_type: string;
  status: string;
  timestamp: string;
  payload?: Record<string, unknown>;
}

const agentColors: Record<string, string> = {
  contact_agent: '#3b82f6',
  calendar_agent: '#10b981',
  market_agent: '#8b5cf6',
  email_agent: '#EAB308',
  deal_agent: '#ef4444',
  capa_orchestrator: '#A16207',
};

const agentIcons: Record<string, string> = {
  contact_agent: '👥',
  calendar_agent: '📅',
  market_agent: '📊',
  email_agent: '✉️',
  deal_agent: '🤝',
  capa_orchestrator: '🧠',
};

const SEED_LOGS: TaskLog[] = [
  { id: '1', agent_id: 'capa_orchestrator', task_type: 'intent.classify.route', status: 'completed', timestamp: new Date(Date.now() - 12000).toISOString() },
  { id: '2', agent_id: 'contact_agent', task_type: 'crm.lead.update_stage', status: 'completed', timestamp: new Date(Date.now() - 45000).toISOString(), payload: { fub_lead_id: 10482, stage: 'Active' } },
  { id: '3', agent_id: 'email_agent', task_type: 'email.draft.send', status: 'completed', timestamp: new Date(Date.now() - 90000).toISOString() },
  { id: '4', agent_id: 'calendar_agent', task_type: 'calendar.event.create', status: 'completed', timestamp: new Date(Date.now() - 3 * 60000).toISOString(), payload: { title: 'Buyer showing — 44 Oak Ave' } },
  { id: '5', agent_id: 'market_agent', task_type: 'market.report.generate', status: 'completed', timestamp: new Date(Date.now() - 8 * 60000).toISOString() },
  { id: '6', agent_id: 'deal_agent', task_type: 'deal.offer.draft', status: 'completed', timestamp: new Date(Date.now() - 15 * 60000).toISOString(), payload: { address: '123 Maple St', offer: '$485,000' } },
  { id: '7', agent_id: 'contact_agent', task_type: 'crm.lead.tag_add', status: 'completed', timestamp: new Date(Date.now() - 28 * 60000).toISOString() },
  { id: '8', agent_id: 'email_agent', task_type: 'email.inbox.triage', status: 'completed', timestamp: new Date(Date.now() - 42 * 60000).toISOString() },
];

const LIVE_EVENTS: TaskLog[] = [
  { id: 'l1', agent_id: 'contact_agent', task_type: 'crm.lead.enrich', status: 'completed', timestamp: '', payload: { leads_enriched: 3 } },
  { id: 'l2', agent_id: 'calendar_agent', task_type: 'calendar.availability.check', status: 'completed', timestamp: '' },
  { id: 'l3', agent_id: 'market_agent', task_type: 'market.comps.fetch', status: 'completed', timestamp: '', payload: { zip: '90210', count: 12 } },
  { id: 'l4', agent_id: 'capa_orchestrator', task_type: 'intent.classify.route', status: 'completed', timestamp: '' },
  { id: 'l5', agent_id: 'email_agent', task_type: 'email.followup.schedule', status: 'completed', timestamp: '' },
];

const timeAgo = (ts: string) => {
  const diff = (Date.now() - new Date(ts).getTime()) / 1000;
  if (diff < 60) return `${Math.floor(diff)}s ago`;
  if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
  return `${Math.floor(diff / 3600)}h ago`;
};

const ActivityFeed: React.FC = () => {
  const [logs, setLogs] = useState<TaskLog[]>(SEED_LOGS);
  const [liveIdx, setLiveIdx] = useState(0);

  // Simulate occasional live events trickling in
  useEffect(() => {
    const interval = setInterval(() => {
      const template = LIVE_EVENTS[liveIdx % LIVE_EVENTS.length];
      const newLog: TaskLog = {
        ...template,
        id: `live-${Date.now()}`,
        timestamp: new Date().toISOString(),
      };
      setLogs(prev => [newLog, ...prev].slice(0, 30));
      setLiveIdx(i => i + 1);
    }, 7000);
    return () => clearInterval(interval);
  }, [liveIdx]);

  return (
    <div className="px-4 py-6">
      <div className="flex items-center justify-between mb-5">
        <div>
          <h2 className="text-base font-orbitron font-bold text-slate-800">Activity Feed</h2>
          <p className="text-slate-400 text-xs font-inter mt-0.5">Real-time agent log</p>
        </div>
        <div className="flex items-center gap-1.5">
          <div className="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse" />
          <span className="text-emerald-600 text-xs font-medium">Live</span>
        </div>
      </div>

      <div className="space-y-2">
        <AnimatePresence initial={false}>
          {logs.map((log) => (
            <motion.div
              key={log.id}
              initial={{ opacity: 0, y: -8 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.2 }}
              className="glass-panel p-3.5 rounded-xl flex items-start gap-3"
            >
              <div
                className="w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0 text-sm"
                style={{ background: `${agentColors[log.agent_id] ?? '#EAB308'}14` }}
              >
                {agentIcons[log.agent_id] ?? '🤖'}
              </div>

              <div className="flex-1 min-w-0">
                <div className="flex items-center justify-between gap-2 mb-0.5">
                  <span
                    className="text-xs font-semibold uppercase tracking-wide truncate"
                    style={{ color: agentColors[log.agent_id] ?? '#A16207' }}
                  >
                    {log.agent_id.replace(/_/g, ' ')}
                  </span>
                  <span className="text-slate-400 text-xs flex-shrink-0">{timeAgo(log.timestamp)}</span>
                </div>
                <p className="text-slate-600 text-xs font-inter">
                  {log.task_type.split('.').join(' → ').replace(/_/g, ' ')}
                </p>
                {log.payload && (
                  <p className="text-slate-400 text-[10px] mt-0.5 font-mono truncate">
                    {JSON.stringify(log.payload)}
                  </p>
                )}
              </div>

              <div
                className="px-1.5 py-0.5 rounded text-[10px] font-medium flex-shrink-0"
                style={{
                  background: 'rgba(16,185,129,0.1)',
                  color: '#059669',
                }}
              >
                {log.status}
              </div>
            </motion.div>
          ))}
        </AnimatePresence>
      </div>
    </div>
  );
};

export default ActivityFeed;
