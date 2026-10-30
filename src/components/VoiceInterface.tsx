import { VoiceState } from '../types';
export default function VoiceInterface({ state, onSample }: { state: VoiceState; onSample: () => void }) {
  return <div className="text-center space-y-3">
    <button className="rounded-lg bg-yellow-400 text-black px-6 py-3" onClick={onSample}
      disabled={state !== 'idle'}>{state === 'idle' ? 'Show a sample exchange' : 'Playing sample…'}</button>
    <p className="text-xs text-gray-500">Simulated conversation · no microphone or agent connection</p>
  </div>;
}
