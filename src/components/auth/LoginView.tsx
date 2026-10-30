import { useAuth } from '../../hooks/useAuth';
export default function LoginView() {
  const { enterDemo } = useAuth();
  return <main className="min-h-screen bg-[#050508] text-white flex items-center justify-center p-8">
    <section className="max-w-lg space-y-6">
      <h1 className="text-4xl text-yellow-400">CAPA · Visual demo</h1>
      <p>This is the earlier browser showcase. Tasks, replies and connector status are simulated;
        this page does not connect to Hermes or perform work.</p>
      <p>The experimental Hermes companion lives in the native Mac and iPhone apps.
        No account, payment or API key is needed to explore this demo.</p>
      <button onClick={enterDemo} className="rounded-lg bg-yellow-400 text-black px-6 py-3">Explore visual demo</button>
    </section>
  </main>;
}
