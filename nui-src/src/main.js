import { mount } from 'svelte';
import '@fontsource/kanit/latin-400.css';
import '@fontsource/kanit/latin-500.css';
import '@fontsource/kanit/latin-700.css';
import '@fontsource/kanit/thai-400.css';
import '@fontsource/kanit/thai-500.css';
import '@fontsource/kanit/thai-700.css';
import '@fontsource/chakra-petch/latin-500.css';
import '@fontsource/chakra-petch/latin-700.css';
import '@fontsource/chakra-petch/thai-500.css';
import '@fontsource/chakra-petch/thai-700.css';
import App from './App.svelte';
import './style.css';

mount(App, { target: document.getElementById('app') });
