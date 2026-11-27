import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const python = process.platform === 'win32' ? 'python' : 'python3';
const script = fileURLToPath(new URL('./build.py', import.meta.url));
execFileSync(python, ['-X', 'utf8', script], {stdio: 'inherit'});
