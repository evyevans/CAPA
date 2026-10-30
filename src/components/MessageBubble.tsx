import React from 'react';
import { motion } from 'framer-motion';
import { Message } from '../types';

interface MessageBubbleProps {
  message: Message;
}

const MessageBubble: React.FC<MessageBubbleProps> = ({ message }) => {
  const isUser = message.type === 'user';

  return (
    <motion.div
      initial={{ opacity: 0, x: isUser ? 20 : -20 }}
      animate={{ opacity: 1, x: 0 }}
      transition={{ duration: 0.3 }}
      className={`flex ${isUser ? 'justify-end' : 'justify-start'}`}
    >
      <div
        className={`px-4 py-2 max-w-xs text-sm font-inter rounded-lg shadow-soft ${
          isUser
            ? 'bg-gray-100 border border-gray-200 text-gray-800'
            : 'bg-cyan-50 border-l-4 border-l-cyan-glow text-slate-800'
        }`}
      >
        <p className="leading-relaxed">{message.content}</p>
        <span className="text-xs text-slate-400 mt-1 block">
          {message.timestamp.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
        </span>
      </div>
    </motion.div>
  );
};

export default MessageBubble;
