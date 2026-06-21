import { chmodSync, cpSync, existsSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { arch, platform } from 'node:process';
import { spawnSync } from 'node:child_process';

if (platform !== 'darwin') {
  console.error('macos:package must run on macOS.');
  process.exit(1);
}

const root = resolve(new URL('..', import.meta.url).pathname);
const releaseRoot = join(root, 'release');
const appName = 'Stemacle';
const appBundle = join(releaseRoot, `${appName}.app`);
const contents = join(appBundle, 'Contents');
const macOSDir = join(contents, 'MacOS');
const resourcesDir = join(contents, 'Resources');
const binaryName = 'StemacleMac';
const binaryCandidates = [
  join(root, 'native/macos/.build/release/StemacleMac'),
  join(root, 'native/macos/.build/apple/Products/Release/StemacleMac'),
];
const binaryPath = binaryCandidates.find((candidate) => existsSync(candidate));

if (!binaryPath) {
  console.error('Missing release binary. Run `npm run macos:build` first.');
  process.exit(1);
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: root,
    stdio: 'inherit',
    ...options,
  });
  if (result.status !== 0) {
    process.exit(result.status || 1);
  }
}

rmSync(appBundle, { recursive: true, force: true });
mkdirSync(macOSDir, { recursive: true });
mkdirSync(resourcesDir, { recursive: true });

cpSync(binaryPath, join(macOSDir, binaryName));
chmodSync(join(macOSDir, binaryName), 0o755);

cpSync(join(root, 'dist/native'), join(resourcesDir, 'repo/dist/native'), { recursive: true });
cpSync(join(root, 'assets'), join(resourcesDir, 'repo/assets'), { recursive: true });
cpSync(join(root, 'app'), join(resourcesDir, 'repo/app'), { recursive: true });
cpSync(join(root, 'apps'), join(resourcesDir, 'repo/apps'), { recursive: true });
cpSync(join(root, 'samples'), join(resourcesDir, 'repo/samples'), { recursive: true });

writeFileSync(join(contents, 'Info.plist'), `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>Stemacle</string>
  <key>CFBundleExecutable</key>
  <string>${binaryName}</string>
  <key>CFBundleIdentifier</key>
  <string>com.stemacle.mac</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Stemacle</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.music</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
`);

const distribution = process.env.STEMACLE_MAC_DISTRIBUTION || 'github';
const identity = distribution === 'appstore'
  ? process.env.MAC_APP_STORE_IDENTITY
  : (process.env.MAC_DEVELOPER_ID || '-');
const entitlements = join(root, 'native/macos/StemacleMac.entitlements');

if (distribution === 'appstore' && !identity) {
  console.error('Missing MAC_APP_STORE_IDENTITY for App Store signing.');
  process.exit(1);
}

run('codesign', [
  '--force',
  '--sign',
  identity,
  '--entitlements',
  entitlements,
  '--options',
  'runtime',
  appBundle,
]);

const outputArch = process.env.STEMACLE_MAC_ARCH || (arch === 'arm64' ? 'arm64' : 'x64');
const zipPath = join(releaseRoot, `Stemacle-mac-${outputArch}.zip`);
rmSync(zipPath, { force: true });
run('ditto', ['-c', '-k', '--keepParent', appBundle, zipPath], { cwd: releaseRoot });

if (distribution === 'appstore') {
  const installerIdentity = process.env.MAC_INSTALLER_IDENTITY;
  if (!installerIdentity) {
    console.error('Missing MAC_INSTALLER_IDENTITY for App Store packaging.');
    process.exit(1);
  }
  const pkgPath = join(releaseRoot, `Stemacle-mac-appstore-${outputArch}.pkg`);
  rmSync(pkgPath, { force: true });
  run('productbuild', [
    '--component',
    appBundle,
    '/Applications',
    '--sign',
    installerIdentity,
    pkgPath,
  ]);
}

console.log(`Packaged ${appBundle}`);
console.log(`Created ${zipPath}`);
