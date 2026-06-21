import { spawn } from 'node:child_process';

const mode = process.argv[2] || 'dev';
const npm = process.platform === 'win32' ? 'npm.cmd' : 'npm';

const targets = {
  darwin: {
    dev: 'macos:dev',
    pack: 'macos:package',
    dist: 'macos:package',
  },
  win32: {
    dev: 'windows:dev',
    pack: 'windows:dist',
    dist: 'windows:dist',
  },
  linux: {
    dev: 'windows:dev',
    pack: 'linux:dist',
    dist: 'linux:dist',
  },
};

const platformTargets = targets[process.platform] || targets.linux;
const script = platformTargets[mode];

if (!script) {
  console.error(`Unknown desktop mode "${mode}". Use dev, pack, or dist.`);
  process.exit(1);
}

const child = spawn(npm, ['run', script], {
  cwd: process.cwd(),
  stdio: 'inherit',
  shell: false,
});

child.on('exit', (code, signal) => {
  if (signal) {
    process.kill(process.pid, signal);
    return;
  }
  process.exit(code ?? 0);
});
