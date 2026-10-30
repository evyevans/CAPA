// Local sample playback only: no microphone, recognition service or agent.
import { useState, useCallback, useEffect, useRef } from 'react';
import { useVoiceStore } from '../stores/voiceStore';
import { Message, VoiceState } from '../types';
const DEMO_RESPONSES = [
  "I've reviewed your pipeline. You have 3 deals in negotiation and 12 leads requiring follow-up this week.",
  "Your calendar is clear tomorrow morning. Want me to schedule follow-up calls with your top 5 prospects?",
  "I found 8 new leads matching your criteria in the target zip codes. Shall I add them to your CRM?",
  "Email drafted and ready for review. Subject: 'Quick check-in — 123 Maple St offer timeline'.",
  "Market report complete. Median days-on-market dropped to 11 in your farm area — a good time to list.",
  "I've updated all contact records and set follow-up reminders for the next 30 days.",
  "Three appointments confirmed for Thursday. I've added them to your Google Calendar with Zoom links.",
];


export const useVoiceAssistant = () => {
  const [state, setState] = useState<VoiceState>('idle');
  const [messages, setMessages] = useState<Message[]>([]);
  const active = useRef(false);
  const timer = useRef<ReturnType<typeof setTimeout>>();
  const index = useRef(0);
  useEffect(() => () => { clearTimeout(timer.current); useVoiceStore.setState({ voiceState: 'idle', isSpeaking: false }); }, []);
  useEffect(() => { useVoiceStore.setState({ voiceState: state, isSpeaking: state === 'speaking' }); }, [state]);
  const handleUserInput = useCallback((text: string) => {
    if (active.current) return;
    active.current = true;
    setState('processing');
    setMessages(current => [...current, { id: crypto.randomUUID(), type: 'user', content: text, timestamp: new Date() }]);
    timer.current = setTimeout(() => {
      const content = 'Simulated reply: ' + DEMO_RESPONSES[index.current++ % DEMO_RESPONSES.length];
      setMessages(current => [...current, { id: crypto.randomUUID(), type: 'assistant', content, timestamp: new Date() }]);
      setState('speaking');
      timer.current = setTimeout(() => { setState('idle'); active.current = false; }, 1800);
    }, 900);
  }, []);
  return { state, messages, isSpeaking: state === 'speaking', handleUserInput };
};
