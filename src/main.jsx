import { createRoot } from 'react-dom/client';
import { MotionConfig } from 'framer-motion';
import './index.css';
import App from './App';
import { selfCheck } from './engine';

if (import.meta.env.DEV) selfCheck(); // the matchmaking rules the iPad app is tested on; a failure logs "Assertion failed"
createRoot(document.getElementById('root')).render(<MotionConfig reducedMotion="user"><App /></MotionConfig>);
